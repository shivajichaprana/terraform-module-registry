output "bucket_id" {
  description = "Name of the created bucket."
  value       = module.bucket.bucket_id
}

output "bucket_arn" {
  description = "ARN of the created bucket."
  value       = module.bucket.bucket_arn
}

output "bucket_policy_attached" {
  description = "Whether a bucket policy was attached."
  value       = module.bucket.bucket_policy_attached
}
