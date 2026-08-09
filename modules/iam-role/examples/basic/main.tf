# Service role assumable by ECS tasks with a read-only managed policy attached.

terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0, < 6.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

module "task_role" {
  source = "../../"

  role_name                  = "example-app-task"
  trusted_service_principals = ["ecs-tasks.amazonaws.com"]
  managed_policy_arns        = ["arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess"]

  tags = {
    Environment = "dev"
    Owner       = "platform"
  }
}
