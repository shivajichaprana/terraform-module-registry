output "bucket_id" {
  description = "Name (ID) of the bucket."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN of the bucket."
  value       = aws_s3_bucket.this.arn
}

output "bucket_domain_name" {
  description = "Global domain name of the bucket."
  value       = aws_s3_bucket.this.bucket_domain_name
}

output "bucket_regional_domain_name" {
  description = "Regional domain name of the bucket."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "sse_algorithm" {
  description = "Server-side encryption algorithm in effect (aws:kms or AES256)."
  value       = local.sse_algorithm
}

output "bucket_policy_attached" {
  description = "Whether a bucket policy was attached."
  value       = local.create_bucket_policy
}
