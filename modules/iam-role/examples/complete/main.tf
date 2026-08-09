# Cross-account role: trusts another account's principals, requires MFA and an
# ExternalId, applies a permissions boundary, and grants a scoped inline policy.

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

variable "trusted_account_id" {
  description = "Account ID whose principals may assume the role."
  type        = string
  default     = "123456789012"
}

variable "permissions_boundary_arn" {
  description = "Permissions boundary policy ARN."
  type        = string
  default     = "arn:aws:iam::123456789012:policy/example-boundary"
}

module "deployer" {
  source = "../../"

  role_name                = "example-deployer"
  trusted_account_ids      = [var.trusted_account_id]
  require_mfa              = true
  external_id              = "example-external-id"
  max_session_duration     = 7200
  permissions_boundary_arn = var.permissions_boundary_arn

  inline_policies = {
    artifact-access = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = "arn:aws:s3:::example-artifacts/*"
      }]
    })
  }

  tags = {
    Environment = "prod"
    Owner       = "platform"
    CostCenter  = "cc-1001"
  }
}
