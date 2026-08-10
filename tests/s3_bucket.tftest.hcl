# Native unit tests for the s3-bucket module.
#
# Every run plans against a mocked AWS provider (no credentials, no API calls)
# and asserts only on values that are known at plan time — module locals surfaced
# through outputs, and configuration arguments set from inputs. Negative runs use
# `expect_failures` to prove the input validations reject bad configuration.

mock_provider "aws" {}

variables {
  bucket_name = "example-app-data"
}

# --- Secure-by-default baseline --------------------------------------------

run "defaults_secure_baseline" {
  command = plan

  module {
    source = "../modules/s3-bucket"
  }

  assert {
    condition     = output.sse_algorithm == "AES256"
    error_message = "Without a KMS key the bucket should fall back to SSE-S3 (AES256)."
  }

  assert {
    condition     = output.bucket_policy_attached == true
    error_message = "TLS enforcement is on by default, so a bucket policy should be attached."
  }

  assert {
    condition     = aws_s3_bucket.this.bucket == "example-app-data"
    error_message = "Bucket name should match the input."
  }

  assert {
    condition     = aws_s3_bucket.this.force_destroy == false
    error_message = "force_destroy must default to false to protect data."
  }

  assert {
    condition     = aws_s3_bucket_ownership_controls.this.rule[0].object_ownership == "BucketOwnerEnforced"
    error_message = "Object ownership should default to BucketOwnerEnforced (ACLs disabled)."
  }

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.this.block_public_acls,
      aws_s3_bucket_public_access_block.this.block_public_policy,
      aws_s3_bucket_public_access_block.this.ignore_public_acls,
      aws_s3_bucket_public_access_block.this.restrict_public_buckets,
    ])
    error_message = "All four public-access-block settings must default to true."
  }

  assert {
    condition     = aws_s3_bucket_versioning.this.versioning_configuration[0].status == "Enabled"
    error_message = "Versioning should be enabled by default."
  }

  assert {
    condition     = aws_s3_bucket_server_side_encryption_configuration.this.rule[0].apply_server_side_encryption_by_default[0].sse_algorithm == "AES256"
    error_message = "Default SSE algorithm should be AES256."
  }

  assert {
    condition     = aws_s3_bucket_server_side_encryption_configuration.this.rule[0].bucket_key_enabled == false
    error_message = "A bucket key only applies with KMS, so it must be off under SSE-S3."
  }

  assert {
    condition     = length(aws_s3_bucket_policy.this) == 1
    error_message = "A bucket policy resource should exist when TLS enforcement is on."
  }

  assert {
    condition     = length(aws_s3_bucket_logging.this) == 0
    error_message = "Server access logging should be off unless a target bucket is supplied."
  }

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.this.rule) == 1
    error_message = "Only the abort-incomplete-multipart housekeeping rule should exist by default."
  }
}

# --- KMS encryption + bucket key -------------------------------------------

run "kms_encryption_and_bucket_key" {
  command = plan

  module {
    source = "../modules/s3-bucket"
  }

  variables {
    bucket_name = "example-app-data"
    kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"
  }

  assert {
    condition     = output.sse_algorithm == "aws:kms"
    error_message = "Supplying a KMS key should switch SSE to aws:kms."
  }

  assert {
    condition     = aws_s3_bucket_server_side_encryption_configuration.this.rule[0].apply_server_side_encryption_by_default[0].kms_master_key_id == "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"
    error_message = "The KMS key ARN should be wired into the SSE configuration."
  }

  assert {
    condition     = aws_s3_bucket_server_side_encryption_configuration.this.rule[0].bucket_key_enabled == true
    error_message = "Bucket key should default on when a KMS key is set."
  }
}

# --- TLS toggle drives the bucket policy -----------------------------------

run "tls_disabled_drops_policy" {
  command = plan

  module {
    source = "../modules/s3-bucket"
  }

  variables {
    bucket_name = "example-app-data"
    enforce_tls = false
  }

  assert {
    condition     = output.bucket_policy_attached == false
    error_message = "With TLS enforcement off and no extra statements, no bucket policy should be attached."
  }

  assert {
    condition     = length(aws_s3_bucket_policy.this) == 0
    error_message = "No bucket policy resource should be created when there are no statements."
  }
}

run "additional_statements_force_policy" {
  command = plan

  module {
    source = "../modules/s3-bucket"
  }

  variables {
    bucket_name = "example-app-data"
    enforce_tls = false
    additional_policy_statements = [
      {
        Sid       = "AllowAccountRead"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::123456789012:root" }
        Action    = "s3:GetObject"
        Resource  = "arn:aws:s3:::example-app-data/*"
      }
    ]
  }

  assert {
    condition     = output.bucket_policy_attached == true
    error_message = "An additional statement should force a bucket policy even with TLS enforcement off."
  }

  assert {
    condition     = length(aws_s3_bucket_policy.this) == 1
    error_message = "A bucket policy resource should be created for the additional statement."
  }
}

# --- Versioning can be suspended -------------------------------------------

run "versioning_suspended" {
  command = plan

  module {
    source = "../modules/s3-bucket"
  }

  variables {
    bucket_name        = "example-app-data"
    versioning_enabled = false
  }

  assert {
    condition     = aws_s3_bucket_versioning.this.versioning_configuration[0].status == "Suspended"
    error_message = "Disabling versioning should suspend it, not remove the configuration."
  }
}

# --- Logging + lifecycle rules ---------------------------------------------

run "logging_and_lifecycle_rules" {
  command = plan

  module {
    source = "../modules/s3-bucket"
  }

  variables {
    bucket_name = "example-app-data"
    logging = {
      target_bucket = "central-access-logs"
      target_prefix = "app-data/"
    }
    lifecycle_rules = [
      {
        id                            = "archive-and-expire"
        transitions                   = [{ days = 30, storage_class = "STANDARD_IA" }]
        expiration_days               = 365
        noncurrent_version_expiration = 90
      }
    ]
  }

  assert {
    condition     = length(aws_s3_bucket_logging.this) == 1
    error_message = "Supplying a logging target should create the logging resource."
  }

  assert {
    condition     = aws_s3_bucket_logging.this[0].target_bucket == "central-access-logs"
    error_message = "Logging target bucket should match the input."
  }

  assert {
    condition     = aws_s3_bucket_logging.this[0].target_prefix == "app-data/"
    error_message = "Logging target prefix should match the input."
  }

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.this.rule) == 2
    error_message = "Housekeeping rule plus one caller rule should yield two lifecycle rules."
  }
}

run "abort_multipart_disabled_no_rules" {
  command = plan

  module {
    source = "../modules/s3-bucket"
  }

  variables {
    bucket_name                     = "example-app-data"
    abort_incomplete_multipart_days = 0
  }

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.this.rule) == 0
    error_message = "Disabling multipart abort with no caller rules should leave zero lifecycle rules."
  }
}

# --- Input validation (negative) -------------------------------------------

run "reject_short_bucket_name" {
  command = plan

  module {
    source = "../modules/s3-bucket"
  }

  variables {
    bucket_name = "ab"
  }

  expect_failures = [var.bucket_name]
}

run "reject_uppercase_bucket_name" {
  command = plan

  module {
    source = "../modules/s3-bucket"
  }

  variables {
    bucket_name = "Example-App-Data"
  }

  expect_failures = [var.bucket_name]
}

run "reject_consecutive_dots" {
  command = plan

  module {
    source = "../modules/s3-bucket"
  }

  variables {
    bucket_name = "example..data"
  }

  expect_failures = [var.bucket_name]
}

run "reject_ip_formatted_name" {
  command = plan

  module {
    source = "../modules/s3-bucket"
  }

  variables {
    bucket_name = "192.168.0.1"
  }

  expect_failures = [var.bucket_name]
}

run "reject_invalid_object_ownership" {
  command = plan

  module {
    source = "../modules/s3-bucket"
  }

  variables {
    bucket_name      = "example-app-data"
    object_ownership = "NotAValidValue"
  }

  expect_failures = [var.object_ownership]
}

run "reject_invalid_kms_arn" {
  command = plan

  module {
    source = "../modules/s3-bucket"
  }

  variables {
    bucket_name = "example-app-data"
    kms_key_arn = "not-an-arn"
  }

  expect_failures = [var.kms_key_arn]
}

run "reject_abort_days_out_of_range" {
  command = plan

  module {
    source = "../modules/s3-bucket"
  }

  variables {
    bucket_name                     = "example-app-data"
    abort_incomplete_multipart_days = 5000
  }

  expect_failures = [var.abort_incomplete_multipart_days]
}
