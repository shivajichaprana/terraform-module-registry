output "role_name" {
  description = "Name of the IAM role."
  value       = aws_iam_role.this.name
}

output "role_arn" {
  description = "ARN of the IAM role."
  value       = aws_iam_role.this.arn
}

output "role_id" {
  description = "Stable, unique ID of the IAM role."
  value       = aws_iam_role.this.unique_id
}

output "assume_role_policy_json" {
  description = "Rendered trust policy document attached to the role."
  value       = aws_iam_role.this.assume_role_policy
}

output "attached_managed_policy_arns" {
  description = "Managed policy ARNs attached to the role."
  value       = [for a in aws_iam_role_policy_attachment.managed : a.policy_arn]
}

output "inline_policy_names" {
  description = "Names of the inline policies created on the role."
  value       = keys(var.inline_policies)
}
