output "task_execution_role_arn" {
  description = "ECS task execution role ARN"
  value       = aws_iam_role.task_execution.arn
}

output "task_execution_role_name" {
  description = "ECS task execution role name"
  value       = aws_iam_role.task_execution.name
}

output "backend_task_role_arn" {
  description = "Backend task role ARN"
  value       = aws_iam_role.backend_task.arn
}

output "backend_task_role_name" {
  description = "Backend task role name"
  value       = aws_iam_role.backend_task.name
}

output "pipeline_task_role_arn" {
  description = "Pipeline task role ARN"
  value       = aws_iam_role.pipeline_task.arn
}

output "pipeline_task_role_name" {
  description = "Pipeline task role name"
  value       = aws_iam_role.pipeline_task.name
}

output "github_actions_role_arn" {
  description = "GitHub Actions OIDC role ARN"
  value       = var.github_org != "" ? aws_iam_role.github_actions[0].arn : null
}