############################################
# Storage module — input variables
############################################

variable "project" {
  description = "Short project identifier used for naming and tags."
  type        = string
  default     = "fraud"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod). Drives name isolation and tags."
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "tags" {
  description = "Extra tags merged onto every resource. Module adds Project/Environment/ManagedBy/Module."
  type        = map(string)
  default     = {}
}

# ---------- S3 data lake ----------

variable "bucket_name" {
  description = "Override the derived data-lake bucket name. Defaults to $${project}-lake-$${environment} (e.g. fraud-lake-dev)."
  type        = string
  default     = null
}

variable "bucket_versioning_enabled" {
  description = "Enable S3 object versioning on the data lake."
  type        = bool
  default     = true
}

variable "bucket_force_destroy" {
  description = "Allow `terraform destroy` to delete a non-empty bucket. Leave false in prod."
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "Optional CMK ARN for SSE-KMS. When null, the bucket uses SSE-S3 (AES256)."
  type        = string
  default     = null
}

variable "glacier_transition_days" {
  description = "Days before raw objects move to S3 Glacier Instant Retrieval. Phase 8 target = 90."
  type        = number
  default     = 90
}

variable "expiration_days" {
  description = "Days before raw objects expire permanently. Phase 8 target = 365."
  type        = number
  default     = 365
}

# ---------- DynamoDB feature store ----------

variable "dynamodb_table_name" {
  description = "DynamoDB table name. Defaults to user_features_v1 (Uber-pattern feature store)."
  type        = string
  default     = "user_features_v1"
}

variable "dynamodb_hash_key" {
  description = "Partition key attribute name."
  type        = string
  default     = "user_id"
}

variable "dynamodb_hash_key_type" {
  description = "Partition key DynamoDB type: S (string), N (number), B (binary)."
  type        = string
  default     = "S"
  validation {
    condition     = contains(["S", "N", "B"], var.dynamodb_hash_key_type)
    error_message = "dynamodb_hash_key_type must be S, N, or B."
  }
}

variable "dynamodb_point_in_time_recovery" {
  description = "Enable point-in-time recovery (PITR) for the feature store."
  type        = bool
  default     = true
}

variable "dynamodb_deletion_protection" {
  description = "Protect the table from accidental deletion. Enable in prod."
  type        = bool
  default     = false
}

# ---------- Glue catalog + crawler ----------

variable "glue_database_name" {
  description = "Glue catalog database name. Defaults to fraud_detection_$${environment}."
  type        = string
  default     = null
}

variable "crawler_schedule" {
  description = "Crawler schedule expression. Default = daily at 01:00 UTC. Use 'cron(0 1 * * ? *)'."
  type        = string
  default     = "cron(0 1 * * ? *)"
}

variable "crawler_s3_path" {
  description = "Sub-path inside the bucket the crawler scans (Flink Parquet sink). Default raw/."
  type        = string
  default     = "raw/"
}

variable "create_crawler_role" {
  description = "Create a tightly-scoped IAM role for the crawler. Set false to pass crawler_role_arn instead."
  type        = bool
  default     = true
}

variable "crawler_role_arn" {
  description = "Existing IAM role ARN for the crawler. Used only when create_crawler_role = false."
  type        = string
  default     = null
}

# ---------- Athena workgroup ----------

variable "create_athena_workgroup" {
  description = "Create a dedicated Athena workgroup with query results in the data lake."
  type        = bool
  default     = true
}

variable "athena_workgroup_name" {
  description = "Athena workgroup name. Defaults to $${project}-$${environment}."
  type        = string
  default     = null
}
