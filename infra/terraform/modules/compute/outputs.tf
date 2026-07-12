output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = aws_ecr_repository.backend.repository_url
}

output "ecr_repository_arn" {
  description = "ECR repository ARN"
  value       = aws_ecr_repository.backend.arn
}

output "ecs_cluster_id" {
  description = "ECS cluster ID"
  value       = aws_ecs_cluster.main.id
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "ecs_cluster_arn" {
  description = "ECS cluster ARN"
  value       = aws_ecs_cluster.main.arn
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = aws_lb.backend.dns_name
}

output "alb_arn" {
  description = "ALB ARN"
  value       = aws_lb.backend.arn
}

output "target_group_arn" {
  description = "Target group ARN"
  value       = aws_lb_target_group.backend.arn
}

output "backend_task_definition_arn" {
  description = "Backend task definition ARN"
  value       = aws_ecs_task_definition.backend.arn
}

output "backend_service_name" {
  description = "Backend service name"
  value       = aws_ecs_service.backend.name
}

output "pipeline_task_definition_arn" {
  description = "Pipeline task definition ARN"
  value       = aws_ecs_task_definition.pipeline.arn
}

output "log_group_backend" {
  description = "Backend log group name"
  value       = aws_cloudwatch_log_group.backend.name
}

output "log_group_pipeline" {
  description = "Pipeline log group name"
  value       = aws_cloudwatch_log_group.pipeline.name
}