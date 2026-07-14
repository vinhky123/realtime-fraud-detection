############################################
# Storage layer
#
# Wires the reusable storage module. Add the networking, iam, and compute
# modules here as those phases land.
############################################

module "storage" {
  source = "./modules/storage"

  project     = var.project
  environment = var.environment

  # S3 data lake
  bucket_name             = var.bucket_name
  bucket_force_destroy    = true
  glacier_transition_days = 90
  expiration_days         = 365

  # DynamoDB feature store
  dynamodb_table_name             = var.dynamodb_table_name
  dynamodb_point_in_time_recovery = true
  dynamodb_deletion_protection    = false

  # Glue catalog + crawler
  glue_database_name = var.glue_database_name
  crawler_s3_path    = "raw/"

  tags = var.tags
}

############################################
# Networking layer
#
# VPC, subnets, NAT, routing, security groups,
# and VPC endpoints for private service access.
############################################

module "networking" {
  source = "./modules/networking"

  project     = var.project
  environment = var.environment

  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  azs                  = var.azs
  aws_region           = var.aws_region

  tags = var.tags
}

############################################
# IAM layer
#
# ECS task execution and application roles
# with least-privilege permissions for
# DynamoDB, S3, Glue, Athena.
############################################

module "iam" {
  source = "./modules/iam"

  project     = var.project
  environment = var.environment

  dynamodb_table_arn = module.storage.dynamodb_table_arn
  s3_bucket_arn      = module.storage.s3_bucket_arn

  github_org  = var.github_org
  github_repo = var.github_repo

  tags = var.tags
}

############################################
# Compute layer
#
# ECR repository, ECS Fargate cluster,
# ALB, and backend API service.
############################################

module "compute" {
  source = "./modules/compute"

  project     = var.project
  environment = var.environment

  vpc_id             = module.networking.vpc_id
  public_subnet_ids  = module.networking.public_subnet_ids
  private_subnet_ids = module.networking.private_subnet_ids
  alb_sg_id          = module.networking.alb_sg_id
  ecs_tasks_sg_id    = module.networking.ecs_tasks_sg_id

  task_execution_role_arn = module.iam.task_execution_role_arn
  backend_task_role_arn   = module.iam.backend_task_role_arn
  pipeline_task_role_arn  = module.iam.pipeline_task_role_arn

  dynamodb_table_name = var.dynamodb_table_name
  aws_region          = var.aws_region

  backend_desired_count = var.backend_desired_count
  backend_cpu           = var.backend_cpu
  backend_memory        = var.backend_memory
  use_fargate_spot      = var.use_fargate_spot

  tags = var.tags
}
