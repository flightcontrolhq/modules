################################################################################
# Outputs
################################################################################

output "allocation_ids" {
  description = "List of Elastic IP allocation IDs, ordered by index. Use these to associate the EIPs with NAT Gateways or other AWS resources that consume pre-allocated EIPs."
  value       = aws_eip.this[*].allocation_id
}

output "public_ips" {
  description = "List of Elastic IP public addresses, ordered by index."
  value       = aws_eip.this[*].public_ip
}

output "public_ip_cidrs" {
  description = "List of Elastic IP public addresses in /32 CIDR notation. Ready to drop directly into an IAM aws:SourceIp condition block or a security group rule."
  value       = [for ip in aws_eip.this[*].public_ip : "${ip}/32"]
}

output "arns" {
  description = "List of Elastic IP ARNs, ordered by index."
  value       = aws_eip.this[*].arn
}

output "eip_count" {
  description = "The number of Elastic IPs allocated by this module invocation."
  value       = length(aws_eip.this)
}
