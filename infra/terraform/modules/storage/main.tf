############################################
# Storage module — AWS resources
#
# Provisions the entire storage layer of the
# fraud-detection system (Uber pattern):
#   - S3 data lake      (raw Parquet archive, dbt output, ML training set)
#   - DynamoDB          (real-time feature store, on-demand)
#   - Glue catalog DB   (schema-on-read for S3 Parquet)
#   - Glue crawler      (discovers raw_transactions schema, daily)
#   - Athena workgroup  (serverless SQL on the lake)
############################################

locals {
  common_tags = merge({
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    Module      = "storage"
  }, var.tags)

  bucket_name      = coalesce(var.bucket_name, "${var.project}-lake-${var.environment}")
  glue_database    = coalesce(var.glue_database_name, "fraud_detection_${var.environment}")
  athena_workgroup = coalesce(var.athena_workgroup_name, "${var.project}-${var.environment}")
}

############################################
# S3 — data lake
# Path layout (written by Flink S3 filesystem sink):
#   s3://<bucket>/raw/dt=yyyy-MM-dd/hour=HH/part-*.parquet  (Snappy)
############################################

resource "aws_s3_bucket" "lake" {
  bucket        = local.bucket_name
  force_destroy = var.bucket_force_destroy
  tags          = local.common_tags
}

resource "aws_s3_bucket_versioning" "lake" {
  bucket = aws_s3_bucket.lake.id

  versioning_configuration {
    status = var.bucket_versioning_enabled ? "Enabled" : "Suspended"
  }
}

# BucketOwnerEnforced disables ACLs and makes the bucket owner own every object —
# the recommended posture for a modern data lake.
resource "aws_s3_bucket_ownership_controls" "lake" {
  bucket = aws_s3_bucket.lake.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "lake" {
  bucket                  = aws_s3_bucket.lake.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "lake" {
  bucket = aws_s3_bucket.lake.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn != null ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

# Lifecycle: Glacier Instant Retrieval at 90d, expire at 365d, reap incomplete
# multipart uploads (Flink S3 sink streams in parts). Phase 8 retention policy.
resource "aws_s3_bucket_lifecycle_configuration" "lake" {
  bucket = aws_s3_bucket.lake.id

  rule {
    id     = "raw-retention"
    status = "Enabled"

    filter {
      prefix = "raw/"
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    transition {
      days          = var.glacier_transition_days
      storage_class = "GLACIER_IR"
    }

    expiration {
      days = var.expiration_days
    }
  }
}

############################################
# DynamoDB — real-time feature store
# table: user_features_v1, PK: user_id (String)
# Read on every /pay request; written by Flink after each event (Uber bridge).
############################################

resource "aws_dynamodb_table" "user_features" {
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST" # on-demand capacity
  hash_key     = var.dynamodb_hash_key

  attribute {
    name = var.dynamodb_hash_key
    type = var.dynamodb_hash_key_type
  }

  server_side_encryption {
    enabled = true # AWS-owned key by default
  }

  point_in_time_recovery {
    enabled = var.dynamodb_point_in_time_recovery
  }

  deletion_protection_enabled = var.dynamodb_deletion_protection

  tags = local.common_tags
}

############################################
# Glue catalog — schema-on-read for the lake
############################################

resource "aws_glue_catalog_database" "fraud" {
  name        = local.glue_database
  description = "Fraud detection data lake catalog (${var.environment})."
}

############################################
# Glue crawler IAM role (optional, self-contained)
############################################

data "aws_iam_policy_document" "glue_assume" {
  statement {
    sid     = "AllowGlueAssume"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "crawler" {
  count              = var.create_crawler_role ? 1 : 0
  name               = "${var.project}-${var.environment}-glue-crawler"
  assume_role_policy = data.aws_iam_policy_document.glue_assume.json
  tags               = local.common_tags
}

# AWSGlueServiceRole grants the catalog write + CloudWatch Logs the crawler needs.
resource "aws_iam_role_policy_attachment" "crawler_glue_service" {
  count      = var.create_crawler_role ? 1 : 0
  role       = aws_iam_role.crawler[0].id
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# Read-only on the data lake — the crawler never writes back to S3.
data "aws_iam_policy_document" "crawler_s3_read" {
  count = var.create_crawler_role ? 1 : 0

  statement {
    sid    = "ReadLakeForCatalog"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.lake.arn,
      "${aws_s3_bucket.lake.arn}/*",
    ]
  }
}

resource "aws_iam_role_policy" "crawler_s3_read" {
  count  = var.create_crawler_role ? 1 : 0
  name   = "s3-read-lake"
  role   = aws_iam_role.crawler[0].id
  policy = data.aws_iam_policy_document.crawler_s3_read[0].json
}

############################################
# Glue crawler — discovers raw_transactions schema daily
############################################

resource "aws_glue_crawler" "raw" {
  name          = "${var.project}-${var.environment}-raw-crawler"
  database_name = aws_glue_catalog_database.fraud.name
  role          = var.create_crawler_role ? aws_iam_role.crawler[0].arn : var.crawler_role_arn
  schedule      = var.crawler_schedule
  table_prefix  = "raw_"

  s3_target {
    path = "s3://${aws_s3_bucket.lake.bucket}/${trimsuffix(var.crawler_s3_path, "/")}/"
  }

  # Append new partitions/columns; never auto-delete catalog objects.
  schema_change_policy {
    delete_behavior = "LOG"
    update_behavior = "UPDATE_IN_DATABASE"
  }

  configuration = jsonencode({
    Version = 1.0
    CrawlerOutput = {
      Partitions = {
        AddOrUpdateBehavior = "InheritFromTable"
      }
    }
  })

  tags = local.common_tags
}

############################################
# Athena workgroup — serverless SQL on the lake
# Query results land in s3://<bucket>/athena-results/
############################################

resource "aws_athena_workgroup" "this" {
  count = var.create_athena_workgroup ? 1 : 0
  name  = local.athena_workgroup

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.lake.bucket}/athena-results/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }

  tags = local.common_tags
}
