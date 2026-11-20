terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Local state keeps this demo stack independent of the EC2 stack.
  # For a team, move it to S3 with locking, as in ../terraform/versions.tf:
  #   backend "s3" { encrypt = true, use_lockfile = true }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project_name
      Stack     = "ecs-container"
      ManagedBy = "terraform"
    }
  }
}
