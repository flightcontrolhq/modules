################################################################################
# Network Load Balancer
################################################################################

output "nlb_id" {
  description = "The ID of the Network Load Balancer."
  value       = aws_lb.this.id
}

output "nlb_arn" {
  description = "The ARN of the Network Load Balancer."
  value       = aws_lb.this.arn
}

output "nlb_arn_suffix" {
  description = "The ARN suffix of the NLB for use with CloudWatch Metrics."
  value       = aws_lb.this.arn_suffix
}

output "nlb_dns_name" {
  description = "The DNS name of the Network Load Balancer."
  value       = aws_lb.this.dns_name
}

output "nlb_zone_id" {
  description = "The canonical hosted zone ID of the NLB (for Route53 alias records)."
  value       = aws_lb.this.zone_id
}

################################################################################
# Listeners
################################################################################

output "listener_arns" {
  description = "Map of listener ARNs keyed by listener name."
  value       = { for k, v in aws_lb_listener.this : k => v.arn }
}

output "listener_ids" {
  description = "Map of listener IDs keyed by listener name."
  value       = { for k, v in aws_lb_listener.this : k => v.id }
}

################################################################################
# Target Groups
################################################################################

output "target_group_arns" {
  description = "Map of target group ARNs keyed by target group name."
  value       = { for k, v in aws_lb_target_group.this : k => v.arn }
}

output "target_group_arn_suffixes" {
  description = "Map of target group ARN suffixes keyed by target group name (for CloudWatch Metrics)."
  value       = { for k, v in aws_lb_target_group.this : k => v.arn_suffix }
}

output "target_group_names" {
  description = "Map of target group names keyed by target group key."
  value       = { for k, v in aws_lb_target_group.this : k => v.name }
}

################################################################################
# Access Logs
################################################################################

output "access_logs_bucket_name" {
  description = "The name of the S3 bucket for access logs (null if access logs disabled or using existing bucket)."
  value       = local.create_access_logs_bucket ? aws_s3_bucket.access_logs[0].id : null
}

output "access_logs_bucket_arn" {
  description = "The ARN of the S3 bucket for access logs (null if access logs disabled or using existing bucket)."
  value       = local.create_access_logs_bucket ? aws_s3_bucket.access_logs[0].arn : null
}
