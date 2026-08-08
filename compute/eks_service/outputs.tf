################################################################################
# Target Group
################################################################################

output "target_group_arn" {
  description = "ARN of the target group. Passed to the workload chart as targetGroupArns so the AWS Load Balancer Controller registers the Service's pod IPs into it."
  value       = aws_lb_target_group.this.arn
}

output "target_group_arn_suffix" {
  description = "ARN suffix of the target group, for CloudWatch ApplicationELB metrics."
  value       = aws_lb_target_group.this.arn_suffix
}

output "target_group_name" {
  description = "Name of the target group."
  value       = aws_lb_target_group.this.name
}

################################################################################
# Listener Rule
################################################################################

output "listener_rule_arn" {
  description = "ARN of the listener rule routing requests to the target group."
  value       = aws_lb_listener_rule.this.arn
}

output "listener_rule_priority" {
  description = "Priority assigned to the listener rule, whether configured or auto-assigned by AWS."
  value       = aws_lb_listener_rule.this.priority
}

################################################################################
# Load Balancer
################################################################################

output "load_balancer_arn" {
  description = "ARN of the shared load balancer the listener belongs to."
  value       = data.aws_lb.attached.arn
}

output "load_balancer_dns_name" {
  description = "DNS name of the shared load balancer serving this workload."
  value       = data.aws_lb.attached.dns_name
}

output "load_balancer_zone_id" {
  description = "Route 53 hosted zone ID of the shared load balancer, for alias records."
  value       = data.aws_lb.attached.zone_id
}

output "load_balancer_arn_suffix" {
  description = "ARN suffix of the shared load balancer, for CloudWatch ApplicationELB metrics."
  value       = data.aws_lb.attached.arn_suffix
}

################################################################################
# General
################################################################################

output "vpc_id" {
  description = "ID of the VPC the target group was created in."
  value       = aws_lb_target_group.this.vpc_id
}

output "region" {
  description = "AWS region where the resources are deployed."
  value       = local.region
}
