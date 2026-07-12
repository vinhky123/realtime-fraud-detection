terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote state — uncomment once the state bucket + DynamoDB lock exist.
  # Keep state local (gitignored) while the infra is being bootstrapped.
  #
  # backend "s3" {
  #   bucket         = "fraud-tfstate"
  #   key            = "storage/terraform.tfstate"
  #   region         = "ap-southeast-1"
  #   dynamodb_table = "terraform-locks"
  #   encrypt        = true
  # }
}
