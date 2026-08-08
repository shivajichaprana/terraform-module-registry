# Hardened S3 bucket: encryption on by default, public access blocked, ACLs
# disabled, TLS enforced, and a safe multipart/versioning lifecycle baseline.

locals {
  # Choose SSE-KMS when a key is supplied, otherwise fall back to SSE-S3.
  sse_algorithm = var.kms_key_arn != null ? "aws:kms" : "AES256"

  # A Bucket Key only makes sense with KMS.
  bucket_key_enabled = var.kms_key_arn != null ? var.bucket_key_enabled : false

  # Deny-non-TLS statement, included only when TLS enforcement is requested.
  tls_statements = var.enforce_tls ? [
    {
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        aws_s3_bucket.this.arn,
        "${aws_s3_bucket.this.arn}/*",
      ]
      Condition = {
        Bool = {
          "aws:SecureTransport" = "false"
        }
      }
    }
  ] : []

  all_policy_statements = concat(local.tls_statements, var.additional_policy_statements)
  create_bucket_policy  = length(local.all_policy_statements) > 0
}

resource "aws_s3_bucket" "this" {
  bucket        = var.bucket_name
  force_destroy = var.force_destroy
  tags          = var.tags
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = var.object_ownership
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = var.block_public_access.block_public_acls
  block_public_policy     = var.block_public_access.block_public_policy
  ignore_public_acls      = var.block_public_access.ignore_public_acls
  restrict_public_buckets = var.block_public_access.restrict_public_buckets
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = local.sse_algorithm
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = local.bucket_key_enabled
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  # Housekeeping rule: abort dangling multipart uploads. Only rendered when enabled.
  dynamic "rule" {
    for_each = var.abort_incomplete_multipart_days > 0 ? [1] : []

    content {
      id     = "abort-incomplete-multipart-uploads"
      status = "Enabled"

      filter {}

      abort_incomplete_multipart_upload {
        days_after_initiation = var.abort_incomplete_multipart_days
      }
    }
  }

  # Caller-supplied rules.
  dynamic "rule" {
    for_each = { for r in var.lifecycle_rules : r.id => r }

    content {
      id     = rule.value.id
      status = rule.value.enabled ? "Enabled" : "Disabled"

      filter {
        prefix = rule.value.prefix
      }

      dynamic "transition" {
        for_each = rule.value.transitions
        content {
          days          = transition.value.days
          storage_class = transition.value.storage_class
        }
      }

      dynamic "expiration" {
        for_each = rule.value.expiration_days != null ? [rule.value.expiration_days] : []
        content {
          days = expiration.value
        }
      }

      dynamic "noncurrent_version_expiration" {
        for_each = rule.value.noncurrent_version_expiration != null ? [rule.value.noncurrent_version_expiration] : []
        content {
          noncurrent_days = noncurrent_version_expiration.value
        }
      }
    }
  }

  # The multipart housekeeping rule references bucket versioning implicitly;
  # depend on it so ordering stays deterministic.
  depends_on = [aws_s3_bucket_versioning.this]
}

resource "aws_s3_bucket_logging" "this" {
  count = var.logging != null ? 1 : 0

  bucket        = aws_s3_bucket.this.id
  target_bucket = var.logging.target_bucket
  target_prefix = var.logging.target_prefix
}

resource "aws_s3_bucket_policy" "this" {
  count = local.create_bucket_policy ? 1 : 0

  bucket = aws_s3_bucket.this.id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = local.all_policy_statements
  })

  # A policy that denies non-TLS traffic must not race the public-access block.
  depends_on = [aws_s3_bucket_public_access_block.this]
}
