output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_arn" {
  description = "ARN of the VPC."
  value       = aws_vpc.this.arn
}

output "vpc_cidr_block" {
  description = "Primary CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "Map of availability zone to public subnet ID."
  value       = { for az, s in aws_subnet.public : az => s.id }
}

output "private_subnet_ids" {
  description = "Map of availability zone to private subnet ID."
  value       = { for az, s in aws_subnet.private : az => s.id }
}

output "public_subnet_id_list" {
  description = "List of public subnet IDs."
  value       = [for s in aws_subnet.public : s.id]
}

output "private_subnet_id_list" {
  description = "List of private subnet IDs."
  value       = [for s in aws_subnet.private : s.id]
}

output "internet_gateway_id" {
  description = "ID of the internet gateway, or null when no public subnets exist."
  value       = one(aws_internet_gateway.this[*].id)
}

output "nat_gateway_ids" {
  description = "Map of availability zone to NAT gateway ID."
  value       = { for az, ngw in aws_nat_gateway.this : az => ngw.id }
}

output "nat_gateway_public_ips" {
  description = "Map of availability zone to NAT gateway public (Elastic) IP."
  value       = { for az, eip in aws_eip.nat : az => eip.public_ip }
}

output "public_route_table_id" {
  description = "ID of the public route table, or null when no public subnets exist."
  value       = one(aws_route_table.public[*].id)
}

output "private_route_table_ids" {
  description = "Map of route-table key to private route table ID."
  value       = { for k, rt in aws_route_table.private : k => rt.id }
}

output "flow_log_group_name" {
  description = "Name of the Flow Logs CloudWatch group, or null when flow logs are disabled."
  value       = one(aws_cloudwatch_log_group.flow_log[*].name)
}
