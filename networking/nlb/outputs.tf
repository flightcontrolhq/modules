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
