variable "project" {
  description = "Short project identifier."
  type        = string
  default     = "fraud"
}

variable "environment" {
  description = "Deployment environment."
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging, or prod."
  }
}

variable "aws_region" {
  description = "AWS region."
  type        = string
  default     = "ap-southeast-1"
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}

variable "vpc_id" {
  description = "VPC ID."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for ALB."
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for ECS tasks."
  type        = list(string)
}

variable "alb_sg_id" {
  description = "ALB security group ID."
  type        = string
}

variable "ecs_tasks_sg_id" {
  description = "ECS tasks security group ID."
  type        = string
}

variable "task_execution_role_arn" {
  description = "ECS task execution role ARN."
  type        = string
}

variable "backend_task_role_arn" {
  description = "Backend task role ARN."
  type        = string
}

variable "pipeline_task_role_arn" {
  description = "Pipeline task role ARN."
  type        = string
}

variable "dynamodb_table_name" {
  description = "DynamoDB feature store table name."
  type        = string
  default     = "user_features_v1"
}

variable "backend_desired_count" {
  description = "Number of backend Fargate tasks."
  type        = number
  default     = 3
}

variable "backend_cpu" {
  description = "CPU units for backend task (256 = 0.25 vCPU)."
  type        = number
  default     = 512
}

variable "backend_memory" {
  description = "Memory MiB for backend task."
  type        = number
  default     = 1024
}

variable "use_fargate_spot" {
  description = "Use FARGATE_SPOT capacity provider."
  type        = bool
  default     = true
}

variable "ecr_image_tag" {
  description = "Backend image tag to deploy."
  type        = string
  default     = "latest"
}