# Implementation Plan

Uber fraud detection pattern: **DynamoDB as real-time feature store** — Backend reads features on request, Flink updates features after each event. No direct Flink ↔ Backend communication. No Kafka result topic feeding Backend.

---

## Phase 1: Foundation Infrastructure

**Objective:** AWS infra + DynamoDB table + local Docker environment.

| Area | Task | Details | Duration |
|---|---|---|---|
| AWS | VPC | 2 public subnets, 2 private subnets, Internet Gateway, Route Tables | 0.5d |
| | Security Groups | ALB (443 inbound), Backend (ALB → 8080), DynamoDB (VPC endpoint) | 0.25d |
| | IAM User | `flink-local` — access key + secret, policies: `s3:PutObject` + `dynamodb:PutItem` + `dynamodb:GetItem` | 0.25d |
| | IAM Role | ECS Task Execution Role + ECS Task Role (S3 read, Glue, DynamoDB read) | 0.25d |
| | S3 Bucket | `fraud-lake-dev`, path: `raw/dt={yyyy-MM-dd}/hour={HH}/` | 0.25d |
| | DynamoDB | `user_features_v1` table. Partition key: `user_id` (String). On-demand capacity. Attributes: `velocity_15m`, `rolling_avg_50`, `rolling_std_50`, `last_txn_ts`, `last_geo_lat`, `last_geo_lon`, `risk_score`, `is_abnormal`, `updated_at` | 0.5d |
| | Glue Database | `fraud_detection_dev` | 0.1d |
| | Glue Crawler | `fraud-raw-crawler` — target S3 raw path, schedule daily, IAM role | 0.25d |
| Local | Docker Compose | Zookeeper + Kafka + Flink (jobmanager + taskmanager), networks, volumes | 0.5d |
| | JAR dependencies | `flink-sql-connector-kafka`, `flink-s3-fs-hadoop`, `hadoop-aws`, `flink-sql-connector-dynamodb` or custom sink | 0.25d |
| | AWS creds in Flink | Env vars: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION` | 0.1d |
| | Verify | Test Flink → S3 upload + Flink → DynamoDB write → success | 0.5d |

**Deliverables:**
- Docker Compose file + `lib/` with connector JARs
- S3 bucket with Hive-style partition structure
- DynamoDB `user_features_v1` table
- IAM user with S3 + DynamoDB permissions
- Verified connectivity: Flink → S3, Flink → DynamoDB

**Total:** ~4 days

---

## Phase 2: Core Data Pipeline (Faker → Kafka → Flink → S3 + DynamoDB)

**Objective:** End-to-end data flow with DynamoDB feature update.

### 2.1 — Faker

| Task | Details |
|---|---|
| Python script | `faker.py`, library: `faker`, `kafka-python` |
| Env config | `TXN_INTERVAL_MIN`, `TXN_INTERVAL_MAX` (seconds) |
| Schema | `txn_id (UUID)`, `user_id`, `amount (1-5000)`, `timestamp (epoch ms)`, `merchant_id`, `geo_lat`, `geo_lon`, `decision (APPROVE 95% / DECLINE 5%)` |
| Kafka | Push to `raw_transactions` topic directly |
| Speed control | `TXN_INTERVAL_MIN=0.1 MAX=0.5` (fast) / `MIN=2 MAX=5` (slow) |

### 2.2 — Kafka

| Task | Details |
|---|---|
| Topic | `raw_transactions`, partitions=3, replication=1 |
| Bootstrap | `localhost:9092` |

### 2.3 — Flink SQL Job

**File:** `sql/fraud_job.sql`

Consume Kafka → compute features → risk score → 2 sinks: DynamoDB + S3.

| Section | SQL |
|---|---|
| **Source** | Kafka connector → JSON format → watermark on `ts` (1min out-of-orderness) |
| **Features** | `velocity_15m` (sliding window count), `rolling_avg_50`, `rolling_std_50` (OVER window) |
| **Risk Score** | `0.4 * z_score(amount) + 0.3 * velocity_15m/100 + 0.3 * geo_anomaly` |
| **Classification** | `risk_score > 0.7 → is_abnormal = TRUE` |
| **Sink 1: DynamoDB** | Flink writes `user_id → { velocity_15m, rolling_avg_50, rolling_std_50, last_txn_ts, last_geo_lat, last_geo_lon, risk_score, is_abnormal }`. Table: `user_features_v1`. Key: `user_id` |
| **Sink 2: S3** | Filesystem connector → Parquet → Snappy → partition by `dt`, `hour`. Path: `s3a://fraud-lake-dev/raw/`. Rolling: 128MB file size, 30-min rollover |

**Flink SQL pseudo for DynamoDB sink:**
```sql
CREATE TABLE dynamodb_sink (
  user_id STRING,
  velocity_15m BIGINT,
  rolling_avg_50 DOUBLE,
  rolling_std_50 DOUBLE,
  last_txn_ts BIGINT,
  last_geo_lat DOUBLE,
  last_geo_lon DOUBLE,
  risk_score DOUBLE,
  is_abnormal BOOLEAN,
  updated_at STRING
) WITH (
  'connector' = 'dynamodb',
  'table-name' = 'user_features_v1',
  'region' = 'ap-southeast-1'
);

INSERT INTO dynamodb_sink
SELECT user_id, velocity_15m, rolling_avg_50, rolling_std_50,
  ts_ms, geo_lat, geo_lon, risk_score, is_abnormal,
  DATE_FORMAT(CURRENT_TIMESTAMP, 'yyyy-MM-dd''T''HH:mm:ss')
FROM scored;
```

### 2.4 — Geo Anomaly UDF (Optional)

| Task | Details |
|---|---|
| Approach | Python UDF (PyFlink) hoặc Flink SQL temporary system function |
| Algorithm | Haversine distance → speed (distance / time_diff) → score [0,1] |
| Fallback | If skip: geo_score = 0.0 (placeholder), only 2 features active |

### 2.5 — Verify

```sql
-- Athena query: data in S3
SELECT dt, hour, COUNT(*) AS txns, AVG(risk_score) AS avg_risk
FROM fraud_detection_dev.raw_transactions
GROUP BY dt, hour ORDER BY dt DESC, hour DESC;
```

```python
# Python: features in DynamoDB
import boto3
ddb = boto3.resource('dynamodb')
table = ddb.Table('user_features_v1')
resp = table.get_item(Key={'user_id': '<some_user_id>'})
print(resp['Item'])
```

**Deliverables:**
- `faker.py` script (configurable via env vars)
- `sql/fraud_job.sql` Flink SQL job (Kafka → S3 + DynamoDB sinks)
- Data visible on S3 (Parquet, Athena queryable)
- Features per user visible in DynamoDB

**Total:** ~5 days

---

## Phase 3: Data Lake & Analytics

**Objective:** Query S3 data → transform → dashboards.

### 3.1 — Glue + Athena

| Task | Tool | Details | Duration |
|---|---|---|---|
| Glue Crawler run | AWS Glue | Crawl S3 raw path → register table in `fraud_detection_dev` | 0.25d |
| Partition projection | Glue Catalog | `dt`, `hour` partition keys | 0.25d |

### 3.2 — dbt Models (GitHub Actions)

| Task | Details | Duration |
|---|---|---|
| dbt project init | `dbt init`, `dbt-athena` adapter, `profiles.yml` | 0.5d |
| `sources.yml` | Source `raw_transactions` from Glue Catalog | 0.25d |
| `stg_transactions.sql` | Clean types, null handling, `hour_of_day`, `day_of_week` derived | 0.5d |
| `fct_normal.sql` | `SELECT * FROM stg WHERE is_abnormal = FALSE` | 0.25d |
| `fct_abnormal.sql` | `SELECT * FROM stg WHERE is_abnormal = TRUE` | 0.25d |
| `agg_daily_fraud.sql` | GROUP BY dt: total_txns, fraud_count, fraud_rate, avg_risk, unique_users, unique_merchants | 0.5d |
| dbt tests | `unique` on txn_id, `not_null` on key columns | 0.25d |
| GitHub Actions | Schedule 6AM UTC daily: `dbt run` + `dbt test` | 0.5d |

### 3.3 — QuickSight Dashboards

| Dashboard | Metrics |
|---|---|
| Daily Summary | Total txns, fraud count, fraud rate %, avg risk score, unique users |
| Fraud Trend | 30-day line chart: fraud rate + total txns overlay |
| Top Risky Users | Bar chart: top 20 users by abnormal txns |
| Amount Distribution | Histogram: amount bins, split normal (blue) vs abnormal (red) |
| Geo Heatmap | Map: transaction density + abnormal highlight |
| Hourly Pattern | Heatmap/line: fraud rate by hour of day, by day of week |

**Deliverables:**
- dbt project on GitHub
- GitHub Actions daily dbt run + tests
- QuickSight dashboards with live data

**Total:** ~4.5 days

---

## Phase 4: Backend Service + DynamoDB Feature Store

**Objective:** Backend Cluster API reads features from DynamoDB on each request to make real-time decisions. Uber pattern: DynamoDB is the bridge.

### 4.1 — ECS + ALB

| Task | Details | Duration |
|---|---|---|
| ECS Cluster | Fargate, task definition: 0.5 vCPU, 1GB RAM | 0.5d |
| Container Image | Python FastAPI. ECR push. Endpoint: `POST /pay` | 1d |
| ALB | Public subnet, HTTPS listener (443) → target group → Backend Cluster | 0.5d |
| Route53 | DNS A record → ALB. e.g. `api.fraud-system.local` | 0.25d |

### 4.2 — Backend API Logic (Uber Pattern)

```
Request   POST /pay
Body      { user_id, amount, merchant_id, geo_lat, geo_lon, timestamp }
Response  { status: "APPROVE"|"DECLINE", txn_id, reason }

Flow:
  1. Receive request
  2. GetItem(user_id) from DynamoDB → get current user features
  3. Rules engine:
     - z_score(amount) vs rolling_avg + rolling_std from DynamoDB
     - velocity_15m check vs threshold
     - Geo anomaly: distance from last_geo to current geo
  4. Decision → HTTP Response
  5. AFTER response: push event (txn + decision) → Kafka (via EC2 Relay + Tailscale)
  6. Flink consumes Kafka → recomputes features → updates DynamoDB for next request
```

| Task | Details | Duration |
|---|---|---|
| DynamoDB read | FastAPI middleware or service layer: `boto3 DynamoDB.Table.get_item(user_id)` | 0.5d |
| Rules engine | z_score check (amount), velocity check, geo check. Decision: APPROVE / DECLINE | 0.5d |
| Kafka producer | After HTTP response → `kafka-python` producer → send to EC2 Relay IP (Tailscale) → Kafka | 0.5d |
| Tests | Curl / Postman: send requests, verify DynamoDB reads, verify Kafka events | 0.5d |

**Faker integration:** After this phase, Faker switches from Kafka direct → HTTP POST to ALB → Backend.

**Deliverables:**
- ECS Fargate Backend Cluster running
- ALB + Route53 routing
- Backend reads DynamoDB features on each request (+~10ms latency)
- Backend pushes events to Kafka after response
- Full Uber pattern operational: DynamoDB read → decision → Kafka → Flink → DynamoDB write

**Total:** ~4.5 days

---

## Phase 5: Hybrid Networking (Tailscale + EC2 Relay)

**Objective:** Connect AWS Backend Cluster → On-Premise Kafka via Tailscale VPN (one-direction push only).

| Task | Details | Duration |
|---|---|---|
| EC2 Relay | t3.micro in public subnet. Install tailscale, join tailnet | 0.5d |
| On-Premise Tailscale | Docker container or native install. Join same tailnet | 0.5d |
| Tailscale ACL | Allow EC2 Relay ↔ On-Premise, port 9092 | 0.25d |
| Kafka listener | Add tailscale listener: `PLAINTEXT://<tailscale-ip>:9092` | 0.5d |
| Backend → Kafka | Backend Fargate → Kafka via EC2 Relay Tailscale IP | 0.5d |
| Verify | Backend push event → Kafka topic → Flink consume → DynamoDB + S3 updated | 0.5d |

**Flow:**
```
Backend (Fargate) → push event → EC2 Relay (pub subnet) → Tailscale → On-Premise Docker
                                                                             │
                                                                             ▼
                                                                           Kafka
                                                                             │
                                                                             ▼
                                                                          Flink
                                                                             │
                                                                   ┌─────────┴──────────┐
                                                                   ▼                    ▼
                                                               DynamoDB              S3
                                                          (update features)    (data lake)
```

**Deliverables:**
- EC2 Relay running tailscale
- On-Premise Docker joined tailnet
- Backend → Kafka one-direction push verified
- Full closed loop: request → DynamoDB read → decision → Kafka → Flink → DynamoDB update

**Total:** ~3 days

---

## Phase 6: Pipeline Cluster — Batch Processing

**Objective:** Scheduled batch jobs on S3 data (Fargate).

| Task | Details | Duration |
|---|---|---|
| ECS Cluster | Fargate task def: 1 vCPU, 2GB RAM | 0.5d |
| Job 1: Daily Report | Python/Polars script: read S3 Parquet → aggregate → generate report JSON/CSV → save S3 `reports/` | 1d |
| Job 2: Data Quality | Daily scan: missing fields %, duplicate check, schema drift alert | 1d |
| Job 3: Fraud Pattern Detection | Scan for: fraud rings (same merchant + multiple users high risk), velocity spikes | 1.5d |
| Orchestration | AWS Step Functions or EventBridge → schedule triggers: 2AM, 6AM, 12PM | 0.5d |
| Alerting | Job result → SNS → Slack/Email for fraud anomalies | 0.5d |

**Deliverables:**
- Pipeline Cluster Fargate running
- 3 batch jobs on schedule
- Alert notification setup

**Total:** ~5 days

---

## Phase 7: ML Training & Feedback Loop

**Objective:** Train ML model from historical S3 data → deploy to Flink → replace rule-based classification.

| Task | Details | Duration |
|---|---|---|
| Data export | Query S3/Athena: labeled transactions (features + is_abnormal) → CSV/Parquet training set | 0.5d |
| Feature engineering | PySpark or Python: extract features (velocity, avg, std, geo, time-of-day, day-of-week) | 1d |
| Model training | XGBoost / Random Forest. Train on 80%, eval on 20% | 1d |
| Evaluation | Precision, recall, F1, confusion matrix, false positive rate | 0.5d |
| Model registry | Save model artifact (pickle/onnx) → S3 `models/` | 0.5d |
| Deploy to Flink | PyFlink UDF loads model → `risk_score` computed by ML instead of weighted sum | 1.5d |
| A/B testing | Run rule-based vs ML model side-by-side → compare F1, false positive rate | 1d |
| Switch | Replace rule-based weights with ML model if it outperforms | 0.5d |

**Deliverables:**
- Trained ML model stored on S3
- PyFlink UDF loading model for real-time inference
- A/B test results showing ML vs rule-based performance
- ML model in production (risk_score = model.predict(features))

**Total:** ~6.5 days

---

## Phase 8: Monitoring, Scaling & Production

**Objective:** Production readiness.

| Task | Details | Duration |
|---|---|---|
| CloudWatch dashboards | Flink (records/sec, checkpoint size, latency), Backend (req/sec, error rate, p99 latency), DynamoDB (read/write capacity, throttled), S3 (bytes written) | 1d |
| CloudWatch Alarms | Flink job restart, S3 write failure, DynamoDB throttle, fraud rate spike > 2x | 0.5d |
| Auto-scaling | Backend Cluster: service auto-scaling based on CPU/request count. Pipeline: scheduled scaling | 0.5d |
| Flink HA | Configure Flink checkpointing (S3), jobmanager high-availability | 0.5d |
| Load testing | K6 / Locust: simulate 1000+ concurrent users → tune scaling, DynamoDB capacity | 1d |
| Backup & Retention | S3 lifecycle: move to Glacier after 90 days, delete after 1 year. DynamoDB: point-in-time recovery | 0.5d |
| Terraform | IaC for all AWS resources (VPC, S3, DynamoDB, IAM, ECS, ALB, Glue) | 1d |

**Deliverables:**
- CloudWatch dashboards + alarms
- Auto-scaling + HA
- Load test results
- Terraform codebase (infrastructure as code)

**Total:** ~5 days

---

## Timeline Summary

```
Phase 1  [4d]    █████
Phase 2  [5d]    ██████
Phase 3  [4.5d]  ██████
Phase 4  [4.5d]  ██████
Phase 5  [3d]    ████
Phase 6  [5d]    ██████
Phase 7  [6.5d]  ████████
Phase 8  [5d]    ██████
────────────────────────
Total: ~37.5 days
```

## Dependencies

```
Phase 1 ──► Phase 2 ──► Phase 3 (analytics)
                │
                ├──► Phase 4 (Backend + DynamoDB)
                │         │
                │         └──► Phase 5 (Tailscale networking)
                │
                ├──► Phase 6 (Pipeline batch, parallel with 4-5)
                │
                └──► Phase 7 (ML, needs Phase 3 data)
                          │
Phase 3 + 5 + 6 + 7 ──► Phase 8 (production)
```

- **Phase 1** is the hard dependency for everything
- **Phase 2** must complete before Phase 3 (data needed in S3) and Phase 4 (Flink → DynamoDB pattern verified)
- **Phase 4 → 5** sequential (Backend ready → add Tailscale networking)
- **Phase 6** can run in parallel with Phase 4-5
- **Phase 7** needs Phase 3 data (historical transactions for training)
- **Phase 8** depends on everything operational

## Key Design Decisions

| Decision | Value | Rationale |
|---|---|---|
| Feature Store | DynamoDB (not Redis/PostgreSQL) | AWS native, serverless, low-latency reads (<10ms), auto-scaling, Uber pattern |
| Feedback Loop | No Kafka result topic. DynamoDB IS the bridge | Backend reads features on next request from DynamoDB. Flink updates DynamoDB. Simpler, no extra topic |
| Backend → Kafka | One-direction push only | Backend pushes event after response. Never reads from Kafka |
| Flink → DynamoDB | Per-event update via DynamoDB connector | Each transaction triggers an update to that user's features |

## Immediate Action Items (Phase 1)

- [ ] Create VPC + subnets + Security Groups + IAM
- [ ] Create S3 bucket `fraud-lake-dev`
- [ ] Create DynamoDB table `user_features_v1` (partition key: `user_id`)
- [ ] Create Glue database `fraud_detection_dev`
- [ ] Write `docker-compose.yml` (Zookeeper, Kafka, Flink)
- [ ] Download and place connector JARs in `lib/`
- [ ] Verify Flink → S3 + Flink → DynamoDB connectivity
