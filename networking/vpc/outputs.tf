################################################################################
# VPC
################################################################################

output "vpc_id" {
  description = "The ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_arn" {
  description = "The ARN of the VPC."
  value       = aws_vpc.this.arn
}

output "vpc_cidr_block" {
  description = "The IPv4 CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "vpc_ipv6_cidr_block" {
  description = "The IPv6 CIDR block of the VPC (if IPv6 is enabled)."
  value       = var.enable_ipv6 ? aws_vpc.this.ipv6_cidr_block : null
}

################################################################################
# Subnets
################################################################################

output "public_subnet_ids" {
  description = "List of IDs of public subnets."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "List of IDs of private subnets."
  value       = aws_subnet.private[*].id
}

output "public_subnet_cidrs" {
  description = "List of IPv4 CIDR blocks of public subnets."
  value       = aws_subnet.public[*].cidr_block
}

output "private_subnet_cidrs" {
  description = "List of IPv4 CIDR blocks of private subnets."
  value       = aws_subnet.private[*].cidr_block
}

output "public_subnet_ipv6_cidrs" {
  description = "List of IPv6 CIDR blocks of public subnets (if IPv6 is enabled)."
  value       = var.enable_ipv6 ? aws_subnet.public[*].ipv6_cidr_block : []
}

output "private_subnet_ipv6_cidrs" {
  description = "List of IPv6 CIDR blocks of private subnets (if IPv6 is enabled)."
  value       = var.enable_ipv6 ? aws_subnet.private[*].ipv6_cidr_block : []
}

output "public_subnet_arns" {
  description = "List of ARNs of public subnets."
  value       = aws_subnet.public[*].arn
}

output "private_subnet_arns" {
  description = "List of ARNs of private subnets."
  value       = aws_subnet.private[*].arn
}

output "availability_zones" {
  description = "List of availability zones used for subnets."
  value       = local.azs
}

################################################################################
# Internet Gateway
################################################################################

output "internet_gateway_id" {
  description = "The ID of the Internet Gateway."
  value       = aws_internet_gateway.this.id
}

output "internet_gateway_arn" {
  description = "The ARN of the Internet Gateway."
  value       = aws_internet_gateway.this.arn
}

################################################################################
# NAT Gateway
################################################################################

output "nat_gateway_ids" {
  description = "List of NAT Gateway IDs (if NAT Gateway is enabled)."
  value       = aws_nat_gateway.this[*].id
}

output "nat_gateway_public_ips" {
  description = "List of public IP addresses of NAT Gateways (if NAT Gateway is enabled)."
  value       = aws_eip.nat[*].public_ip
}

output "nat_gateway_allocation_ids" {
  description = "List of Elastic IP allocation IDs for NAT Gateways (if NAT Gateway is enabled)."
  value       = aws_eip.nat[*].allocation_id
}

################################################################################
# Route Tables
################################################################################

output "public_route_table_id" {
  description = "The ID of the public route table."
  value       = aws_route_table.public.id
}

output "private_route_table_ids" {
  description = "List of IDs of private route tables."
  value       = aws_route_table.private[*].id
}

################################################################################
# Egress-Only Internet Gateway (IPv6)
################################################################################

output "egress_only_internet_gateway_id" {
  description = "The ID of the Egress-Only Internet Gateway (if IPv6 is enabled)."
  value       = var.enable_ipv6 ? aws_egress_only_internet_gateway.this[0].id : null
}

################################################################################
# VPC Flow Logs
################################################################################

output "flow_log_id" {
  description = "The ID of the VPC Flow Log (if flow logs are enabled)."
  value       = var.enable_flow_logs ? (local.create_flow_log_cloudwatch ? aws_flow_log.cloudwatch[0].id : aws_flow_log.s3[0].id) : null
}

output "flow_log_cloudwatch_log_group_name" {
  description = "The name of the CloudWatch Log Group for VPC Flow Logs (if destination is cloudwatch)."
  value       = local.create_flow_log_cloudwatch ? aws_cloudwatch_log_group.flow_logs[0].name : null
}

output "flow_log_cloudwatch_log_group_arn" {
  description = "The ARN of the CloudWatch Log Group for VPC Flow Logs (if destination is cloudwatch)."
  value       = local.create_flow_log_cloudwatch ? aws_cloudwatch_log_group.flow_logs[0].arn : null
}

output "flow_log_cloudwatch_iam_role_arn" {
  description = "The ARN of the IAM Role for VPC Flow Logs to CloudWatch (if destination is cloudwatch)."
  value       = local.create_flow_log_cloudwatch ? aws_iam_role.flow_logs[0].arn : null
}

output "flow_log_s3_bucket_arn" {
  description = "The ARN of the S3 bucket for VPC Flow Logs (if destination is s3)."
  value       = local.create_flow_log_s3 ? local.flow_log_s3_bucket_arn : null
}
