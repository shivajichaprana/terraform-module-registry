# s3-bucket

A hardened, opinionated S3 bucket module. Secure defaults are applied out of the
box so a bare call produces a private, encrypted, TLS-only bucket.

## Security posture

- **Public access blocked** — all four public-access-block settings default to `true`.
- **ACLs disabled** — `BucketOwnerEnforced` ownership by default.
- **Encryption always on** — SSE-S3 (`AES256`) by default, or SSE-KMS with a Bucket Key when `kms_key_arn` is set.
- **TLS enforced** — an optional bucket policy denies any request where `aws:SecureTransport` is `false` (default on).
- **Versioning on** — enabled by default for recoverability.
- **Multipart hygiene** — incomplete multipart uploads are aborted after a configurable number of days.

## Usage

```hcl
module "logs" {
  source = "github.com/<your-github-org>/terraform-module-registry//modules/s3-bucket?ref=v1.0.0"

  bucket_name = "example-app-logs"

  tags = {
    Environment = "prod"
    Owner       = "platform"
  }
}
```

### With KMS and lifecycle rules

```hcl
module "data" {
  source = "github.com/<your-github-org>/terraform-module-registry//modules/s3-bucket?ref=v1.0.0"

  bucket_name = "example-app-data"
  kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/<key-id>"

  lifecycle_rules = [
    {
      id = "archive-old-objects"
      transitions = [
        { days = 30, storage_class = "STANDARD_IA" },
        { days = 90, storage_class = "GLACIER" },
      ]
      noncurrent_version_expiration = 365
    },
  ]

  logging = {
    target_bucket = "example-central-access-logs"
    target_prefix = "app-data/"
  }
}
```

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `bucket_name` | `string` | — | Globally unique, DNS-compliant bucket name. |
| `force_destroy` | `bool` | `false` | Allow deleting a non-empty bucket. |
| `object_ownership` | `string` | `BucketOwnerEnforced` | Object ownership control. |
| `versioning_enabled` | `bool` | `true` | Enable object versioning. |
| `kms_key_arn` | `string` | `null` | KMS key ARN; `null` uses SSE-S3. |
| `bucket_key_enabled` | `bool` | `true` | Use an S3 Bucket Key (KMS only). |
| `block_public_access` | `object` | all `true` | Public-access-block settings. |
| `enforce_tls` | `bool` | `true` | Deny non-TLS requests via bucket policy. |
| `additional_policy_statements` | `list(any)` | `[]` | Extra bucket-policy statements. |
| `lifecycle_rules` | `list(object)` | `[]` | Lifecycle transition/expiration rules. |
| `abort_incomplete_multipart_days` | `number` | `7` | Abort incomplete MPUs after N days (0 disables). |
| `logging` | `object` | `null` | Server access logging target. |
| `tags` | `map(string)` | `{}` | Tags applied to the bucket. |

## Outputs

| Name | Description |
|------|-------------|
| `bucket_id` | Bucket name (ID). |
| `bucket_arn` | Bucket ARN. |
| `bucket_domain_name` | Global domain name. |
| `bucket_regional_domain_name` | Regional domain name. |
| `sse_algorithm` | Encryption algorithm in effect. |
| `bucket_policy_attached` | Whether a bucket policy was attached. |

## Examples

- [`examples/basic`](./examples/basic) — minimal private encrypted bucket.
- [`examples/complete`](./examples/complete) — KMS, lifecycle rules, and access logging.
