################################################################################
# Security Group
################################################################################

output "security_group_id" {
  description = "The ID of the security group."
  value       = aws_security_group.this.id
}

output "security_group_arn" {
  description = "The ARN of the security group."
  value       = aws_security_group.this.arn
}

output "security_group_name" {
  description = "The name of the security group."
  value       = aws_security_group.this.name
}

output "security_group_vpc_id" {
  description = "The VPC ID of the security group."
  value       = aws_security_group.this.vpc_id
}

output "security_group_owner_id" {
  description = "The owner ID (AWS account ID) of the security group."
  value       = aws_security_group.this.owner_id
}

################################################################################
# Ingress Rules
################################################################################

output "ingress_rule_ids" {
  description = "Map of ingress rule keys to their IDs."
  value       = { for k, v in aws_vpc_security_group_ingress_rule.this : k => v.id }
}

output "ingress_rule_arns" {
  description = "Map of ingress rule keys to their ARNs."
  value       = { for k, v in aws_vpc_security_group_ingress_rule.this : k => v.arn }
}

################################################################################
# Egress Rules
################################################################################

output "egress_rule_ids" {
  description = "Map of egress rule keys to their IDs."
  value       = { for k, v in aws_vpc_security_group_egress_rule.this : k => v.id }
}

output "egress_rule_arns" {
  description = "Map of egress rule keys to their ARNs."
  value       = { for k, v in aws_vpc_security_group_egress_rule.this : k => v.arn }
}
