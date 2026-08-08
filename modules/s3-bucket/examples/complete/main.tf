# Full-featured bucket: SSE-KMS with a Bucket Key, lifecycle transitions,
# noncurrent-version expiration, and server access logging.

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

variable "kms_key_arn" {
  description = "KMS key ARN used for bucket encryption."
  type        = string
  default     = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"
}

variable "access_log_bucket" {
  description = "Existing central bucket receiving server access logs."
  type        = string
  default     = "example-central-access-logs"
}

module "bucket" {
  source = "../../"

  bucket_name        = "example-complete-bucket-123456789012"
  kms_key_arn        = var.kms_key_arn
  bucket_key_enabled = true
  versioning_enabled = true

  lifecycle_rules = [
    {
      id     = "archive-and-expire"
      prefix = "archive/"
      transitions = [
        { days = 30, storage_class = "STANDARD_IA" },
        { days = 90, storage_class = "GLACIER" },
      ]
      expiration_days               = 3650
      noncurrent_version_expiration = 365
    },
  ]

  logging = {
    target_bucket = var.access_log_bucket
    target_prefix = "complete-bucket/"
  }

  tags = {
    Environment = "prod"
    Owner       = "platform"
    CostCenter  = "cc-1001"
  }
}
