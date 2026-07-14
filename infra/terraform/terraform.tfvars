############################################
# Environment values
#
# bucket_name MUST be globally unique across all AWS accounts.
# "fraud-lake-dev" is taken — append a unique suffix (org slug, AWS account id, etc.)
############################################

project             = "fraud"
environment         = "dev"
aws_region          = "ap-southeast-1"
bucket_name         = "fraud-lake-800380167165" # globally unique (account-id suffix)
dynamodb_table_name = "user_features_v1"
glue_database_name  = "fraud_detection_dev"

github_org  = "vinhky123"
github_repo = "realtime-fraud-detection"

tags = {
  Team = "data-platform"
  Cost = "fraud-detection"
}
