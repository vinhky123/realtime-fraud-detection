locals {
  common_tags = merge({
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    Module      = "iam"
  }, var.tags)

  name_prefix = "${var.project}-${var.environment}"
}

############################################
# ECS Task Execution Role
# Used by ECS agent to pull images, write logs
############################################

data "aws_iam_policy_document" "task_execution_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task_execution" {
  name               = "${local.name_prefix}-ecs-task-execution"
  assume_role_policy = data.aws_iam_policy_document.task_execution_assume.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "task_execution" {
  statement {
    sid    = "ECRImagePull"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "task_execution" {
  name   = "${local.name_prefix}-task-execution-policy"
  role   = aws_iam_role.task_execution.id
  policy = data.aws_iam_policy_document.task_execution.json
}

############################################
# Backend Task Role
# Permissions for the FastAPI backend service
############################################

data "aws_iam_policy_document" "backend_task_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "backend_task" {
  name               = "${local.name_prefix}-backend-task"
  assume_role_policy = data.aws_iam_policy_document.backend_task_assume.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "backend_task" {
  # DynamoDB - read user features
  statement {
    sid    = "DynamoDBReadFeatures"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:BatchGetItem"
    ]
    resources = [
      var.dynamodb_table_arn
    ]
  }

  # S3 - read from data lake (for any batch operations)
  statement {
    sid    = "S3ReadLake"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket"
    ]
    resources = [
      var.s3_bucket_arn,
      "${var.s3_bucket_arn}/*"
    ]
  }

  # ECR - pull images (if needed at runtime)
  statement {
    sid    = "ECRPull"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "backend_task" {
  name   = "${local.name_prefix}-backend-task-policy"
  role   = aws_iam_role.backend_task.id
  policy = data.aws_iam_policy_document.backend_task.json
}

############################################
# Pipeline Task Role
# Permissions for batch processing jobs
############################################

data "aws_iam_policy_document" "pipeline_task_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "pipeline_task" {
  name               = "${local.name_prefix}-pipeline-task"
  assume_role_policy = data.aws_iam_policy_document.pipeline_task_assume.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "pipeline_task" {
  # S3 - full access to data lake for batch processing
  statement {
    sid    = "S3FullLake"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]
    resources = [
      var.s3_bucket_arn,
      "${var.s3_bucket_arn}/*"
    ]
  }

  # DynamoDB - read features
  statement {
    sid    = "DynamoDBReadFeatures"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:BatchGetItem",
      "dynamodb:Query",
      "dynamodb:Scan"
    ]
    resources = [
      var.dynamodb_table_arn
    ]
  }

  # Glue - read catalog
  statement {
    sid    = "GlueRead"
    effect = "Allow"
    actions = [
      "glue:GetDatabase",
      "glue:GetDatabases",
      "glue:GetTable",
      "glue:GetTables",
      "glue:GetPartition",
      "glue:GetPartitions"
    ]
    resources = ["*"]
  }

  # Athena - query
  statement {
    sid    = "AthenaQuery"
    effect = "Allow"
    actions = [
      "athena:StartQueryExecution",
      "athena:GetQueryExecution",
      "athena:GetQueryResults",
      "athena:GetWorkGroup"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "pipeline_task" {
  name   = "${local.name_prefix}-pipeline-task-policy"
  role   = aws_iam_role.pipeline_task.id
  policy = data.aws_iam_policy_document.pipeline_task.json
}