############################################
# Variables
############################################

variable "project" {
  description = "Short project identifier."
  type        = string
  default     = "fraud"
}

variable "environment" {
  description = "Deployment environment identifier used for naming and tags."
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region. Matches AWS_REGION in .env."
  type        = string
  default     = "ap-southeast-1"
}

variable "bucket_name" {
  description = "Data lake bucket name. Globally unique — override in tfvars with an unclaimed name."
  type        = string
}

variable "dynamodb_table_name" {
  description = "Feature store table name."
  type        = string
  default     = "user_features_v1"
}

variable "glue_database_name" {
  description = "Glue catalog database name."
  type        = string
  default     = "fraud_detection_dev"
}

variable "github_org" {
  description = "GitHub org/username for Actions OIDC trust."
  type        = string
  default     = ""
}

variable "github_repo" {
  description = "GitHub repo name for Actions OIDC trust."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Extra resource tags."
  type        = map(string)
  default     = {}
}

# ---------- Networking ----------

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets."
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "azs" {
  description = "Availability zones."
  type        = list(string)
  default     = ["ap-southeast-1a", "ap-southeast-1b"]
}

# ---------- Compute (ECS Fargate) ----------

variable "backend_desired_count" {
  description = "Desired number of backend Fargate tasks."
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
  description = "Use FARGATE_SPOT capacity provider for cost savings."
  type        = bool
  default     = true
}

variable "ecr_image_tag" {
  description = "ECR image tag for backend deployment."
  type        = string
  default     = "latest"
}
