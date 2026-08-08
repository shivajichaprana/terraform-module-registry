# Minimal private, encrypted, TLS-only bucket using module defaults.

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

module "bucket" {
  source = "../../"

  bucket_name = "example-basic-bucket-123456789012"

  tags = {
    Environment = "dev"
    Owner       = "platform"
  }
}
