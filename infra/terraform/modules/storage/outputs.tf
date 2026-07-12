############################################
# Storage module — outputs
############################################

output "s3_bucket_name" {
  description = "Data lake bucket name (e.g. fraud-lake-dev)."
  value       = aws_s3_bucket.lake.bucket
}

output "s3_bucket_arn" {
  description = "Data lake bucket ARN."
  value       = aws_s3_bucket.lake.arn
}

output "s3_raw_prefix" {
  description = "S3 prefix Flink writes Parquet to (Glue/Athena scan from here)."
  value       = "s3://${aws_s3_bucket.lake.bucket}/raw/"
}

output "dynamodb_table_name" {
  description = "Feature store table name (Backend reads / Flink writes)."
  value       = aws_dynamodb_table.user_features.name
}

output "dynamodb_table_arn" {
  description = "Feature store table ARN. Feed into the IAM module for ECS task policy scoping."
  value       = aws_dynamodb_table.user_features.arn
}

output "glue_database_name" {
  description = "Glue catalog database for the lake."
  value       = aws_glue_catalog_database.fraud.name
}

output "glue_crawler_name" {
  description = "Glue crawler name (discovers raw_transactions schema)."
  value       = aws_glue_crawler.raw.name
}

output "crawler_role_arn" {
  description = "IAM role used by the crawler (empty if an external role was supplied)."
  value       = var.create_crawler_role ? aws_iam_role.crawler[0].arn : var.crawler_role_arn
}

output "athena_workgroup_name" {
  description = "Athena workgroup name (null when workgroup creation is disabled)."
  value       = var.create_athena_workgroup ? aws_athena_workgroup.this[0].name : null
}
