output "vpc_id" {
  description = "ID of the created VPC."
  value       = module.vpc.vpc_id
}

output "nat_gateway_public_ips" {
  description = "Public IPs of the NAT gateway(s)."
  value       = module.vpc.nat_gateway_public_ips
}

output "flow_log_group_name" {
  description = "CloudWatch Logs group receiving Flow Logs."
  value       = module.vpc.flow_log_group_name
}
