output "bucket_arn" {
  description = "ARN of the created bucket."
  value       = module.bucket.bucket_arn
}

output "sse_algorithm" {
  description = "Encryption algorithm applied to the bucket."
  value       = module.bucket.sse_algorithm
}
