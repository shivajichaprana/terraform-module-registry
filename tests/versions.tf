# Root configuration for the native test harness.
#
# `terraform test` needs an initialized configuration to run from. This root
# declares only the provider requirement so `terraform init` installs the AWS
# provider schema; every test file supplies a `mock_provider "aws"`, so no real
# credentials or provider configuration are needed and no API calls are made.
# The modules under test are pulled in per-run via `module { source = ... }`.

terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0, < 6.0"
    }
  }
}
