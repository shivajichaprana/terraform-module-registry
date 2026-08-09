# Cost-optimized VPC: a single shared NAT gateway, custom Flow Logs retention,
# and a KMS-encrypted Flow Logs group.

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

variable "flow_log_kms_key_arn" {
  description = "KMS key ARN encrypting the Flow Logs group."
  type        = string
  default     = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"
}

module "vpc" {
  source = "../../"

  name               = "example-complete"
  cidr_block         = "10.20.0.0/16"
  availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]

  public_subnet_cidrs  = ["10.20.0.0/24", "10.20.1.0/24", "10.20.2.0/24"]
  private_subnet_cidrs = ["10.20.10.0/24", "10.20.11.0/24", "10.20.12.0/24"]

  single_nat_gateway      = true
  flow_log_retention_days = 365
  flow_log_kms_key_arn    = var.flow_log_kms_key_arn

  tags = {
    Environment = "prod"
    Owner       = "platform"
    CostCenter  = "cc-1001"
  }
}
