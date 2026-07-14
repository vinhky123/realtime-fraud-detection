output "s3_bucket_name" {
  description = "Data lake bucket."
  value       = module.storage.s3_bucket_name
}

output "s3_raw_prefix" {
  description = "Flink Parquet sink prefix."
  value       = module.storage.s3_raw_prefix
}

output "dynamodb_table_name" {
  description = "Feature store table."
  value       = module.storage.dynamodb_table_name
}

output "dynamodb_table_arn" {
  description = "Feature store ARN — scope the IAM module's ECS task policy to this."
  value       = module.storage.dynamodb_table_arn
}

output "glue_database_name" {
  description = "Glue catalog database."
  value       = module.storage.glue_database_name
}

output "glue_crawler_name" {
  description = "Glue crawler."
  value       = module.storage.glue_crawler_name
}

output "athena_workgroup_name" {
  description = "Athena workgroup."
  value       = module.storage.athena_workgroup_name
}

# ---------- Networking ----------

output "vpc_id" {
  description = "VPC ID."
  value       = module.networking.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs."
  value       = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs."
  value       = module.networking.private_subnet_ids
}

output "alb_sg_id" {
  description = "ALB security group ID."
  value       = module.networking.alb_sg_id
}

output "ecs_tasks_sg_id" {
  description = "ECS tasks security group ID."
  value       = module.networking.ecs_tasks_sg_id
}

# ---------- Compute ----------

output "ecr_repository_url" {
  description = "ECR repository URL for backend API."
  value       = module.compute.ecr_repository_url
}

output "ecs_cluster_name" {
  description = "ECS cluster name."
  value       = module.compute.ecs_cluster_name
}

output "alb_dns_name" {
  description = "ALB DNS name."
  value       = module.compute.alb_dns_name
}

output "backend_service_name" {
  description = "Backend ECS service name."
  value       = module.compute.backend_service_name
}

output "backend_task_definition_arn" {
  description = "Backend task definition ARN."
  value       = module.compute.backend_task_definition_arn
}

output "backend_log_group" {
  description = "Backend CloudWatch log group."
  value       = module.compute.log_group_backend
}

output "github_actions_role_arn" {
  description = "GitHub Actions OIDC role ARN — set as AWS_ROLE_ARN secret."
  value       = module.iam.github_actions_role_arn
}
