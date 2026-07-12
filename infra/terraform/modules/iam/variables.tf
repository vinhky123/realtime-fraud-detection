variable "project" {
  description = "Short project identifier."
  type        = string
  default     = "fraud"
}

variable "environment" {
  description = "Deployment environment."
  type        = string
  default     = "dev"
}

variable "dynamodb_table_arn" {
  description = "DynamoDB feature store table ARN."
  type        = string
}

variable "s3_bucket_arn" {
  description = "S3 data lake bucket ARN."
  type        = string
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}