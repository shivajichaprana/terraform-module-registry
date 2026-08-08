variable "bucket_name" {
  description = "Name of the S3 bucket. Must be globally unique and DNS-compliant."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be 3-63 chars, lowercase alphanumerics, dots, or hyphens, and start/end alphanumeric."
  }

  validation {
    condition     = !can(regex("\\.\\.", var.bucket_name)) && !can(regex("^[0-9]+(\\.[0-9]+){3}$", var.bucket_name))
    error_message = "bucket_name must not contain consecutive dots or be formatted as an IP address."
  }
}

variable "force_destroy" {
  description = "Allow deletion of a non-empty bucket. Keep false for buckets holding real data."
  type        = bool
  default     = false
}

variable "object_ownership" {
  description = "Object ownership control. BucketOwnerEnforced disables ACLs (recommended)."
  type        = string
  default     = "BucketOwnerEnforced"

  validation {
    condition     = contains(["BucketOwnerEnforced", "BucketOwnerPreferred", "ObjectWriter"], var.object_ownership)
    error_message = "object_ownership must be one of BucketOwnerEnforced, BucketOwnerPreferred, ObjectWriter."
  }
}

variable "versioning_enabled" {
  description = "Enable object versioning. Recommended for recoverability and lifecycle transitions."
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = "KMS key ARN for server-side encryption. When null, SSE-S3 (AES256) is used."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws[a-zA-Z-]*:kms:", var.kms_key_arn))
    error_message = "kms_key_arn must be null or a valid KMS key ARN."
  }
}

variable "bucket_key_enabled" {
  description = "Use an S3 Bucket Key to reduce KMS request costs. Only applies when a KMS key is set."
  type        = bool
  default     = true
}

variable "block_public_access" {
  description = "Public access block settings. All four should stay true unless there is a documented exception."
  type = object({
    block_public_acls       = optional(bool, true)
    block_public_policy     = optional(bool, true)
    ignore_public_acls      = optional(bool, true)
    restrict_public_buckets = optional(bool, true)
  })
  default = {}
}

variable "enforce_tls" {
  description = "Attach a bucket policy statement denying any request not using TLS (aws:SecureTransport)."
  type        = bool
  default     = true
}

variable "additional_policy_statements" {
  description = "Extra IAM policy statement objects merged into the bucket policy. Each must be a valid statement."
  type        = list(any)
  default     = []
}

variable "lifecycle_rules" {
  description = <<-EOT
    List of lifecycle rules. Each entry supports:
      id                              - unique rule identifier
      enabled                         - whether the rule is active
      prefix                          - optional key prefix filter
      transitions                     - list of { days, storage_class }
      expiration_days                 - optional current-version expiration
      noncurrent_version_expiration   - optional noncurrent-version expiration in days
  EOT
  type = list(object({
    id                            = string
    enabled                       = optional(bool, true)
    prefix                        = optional(string, null)
    transitions                   = optional(list(object({ days = number, storage_class = string })), [])
    expiration_days               = optional(number, null)
    noncurrent_version_expiration = optional(number, null)
  }))
  default = []
}

variable "abort_incomplete_multipart_days" {
  description = "Automatically abort incomplete multipart uploads after this many days. Set to 0 to disable."
  type        = number
  default     = 7

  validation {
    condition     = var.abort_incomplete_multipart_days >= 0 && var.abort_incomplete_multipart_days <= 3650
    error_message = "abort_incomplete_multipart_days must be between 0 and 3650."
  }
}

variable "logging" {
  description = "Optional server access logging target. When target_bucket is null, logging is disabled."
  type = object({
    target_bucket = string
    target_prefix = optional(string, "s3-access-logs/")
  })
  default = null
}

variable "tags" {
  description = "Tags applied to the bucket."
  type        = map(string)
  default     = {}
}
