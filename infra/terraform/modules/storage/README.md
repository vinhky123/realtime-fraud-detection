# Storage Module

Provisions the **storage layer** of the streaming fraud-detection system (Uber pattern).
Everything Flink writes to and the Backend reads from lives here.

| Resource | Role in the pipeline |
|----------|----------------------|
| **S3 data lake** | Raw transaction Parquet archive (`raw/dt=…/hour=…`, Snappy), dbt output, ML training set |
| **DynamoDB** | Real-time feature store (`user_features_v1`, PK `user_id`). Backend reads on every `/pay`; Flink writes after each event |
| **Glue catalog DB** | Schema-on-read for the lake |
| **Glue crawler** | Discovers the `raw_transactions` schema + partitions on a daily schedule |
| **Athena workgroup** | Serverless SQL over the lake; query results in `s3://<bucket>/athena-results/` |

## Usage

```hcl
module "storage" {
  source = "../../modules/storage"

  project     = "fraud"
  environment = "dev"

  bucket_name         = "fraud-lake-dev"   # must be globally unique
  dynamodb_table_name = "user_features_v1"
  glue_database_name  = "fraud_detection_dev"

  glacier_transition_days = 90
  expiration_days         = 365

  tags = { Team = "data-platform" }
}
```

Outputs (`s3_bucket_arn`, `dynamodb_table_arn`, `glue_database_name`, …) are meant to
be consumed by the **iam**, **compute**, and **networking** modules — e.g. scope the
ECS task role to `dynamodb_table_arn` for `GetItem`, and the Flink IAM user to
`s3_bucket_arn` for `PutObject`.

## Notes & defaults

- **Encryption:** SSE-S3 (AES256) out of the box. Pass `kms_key_arn` to switch the
  bucket to a customer-managed key (SSE-KMS).
- **Retention:** raw objects → S3 Glacier Instant Retrieval at `glacier_transition_days`
  (default 90), expire at `expiration_days` (default 365) — the Phase 8 retention policy.
- **DynamoDB:** on-demand (`PAY_PER_REQUEST`), PITR enabled by default, optional
  `dynamodb_deletion_protection` for prod.
- **Crawler role:** the module creates a least-privilege role by default. For a shared
  IAM module, set `create_crawler_role = false` and pass `crawler_role_arn`.
- **Bucket name:** must be **globally unique** across all AWS accounts. `fraud-lake-dev`
  is almost certainly taken — override `bucket_name` with something unique per account.
