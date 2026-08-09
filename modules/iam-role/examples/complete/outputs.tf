output "role_arn" {
  description = "ARN of the created role."
  value       = module.deployer.role_arn
}

output "assume_role_policy_json" {
  description = "Rendered trust policy document."
  value       = module.deployer.assume_role_policy_json
}
