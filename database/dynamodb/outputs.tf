################################################################################
# Table Outputs
################################################################################

output "table_id" {
  description = "The ID (name) of the DynamoDB table."
  value       = aws_dynamodb_table.this.id
}

output "table_name" {
  description = "The name of the DynamoDB table."
  value       = aws_dynamodb_table.this.name
}

output "table_arn" {
  description = "The ARN of the DynamoDB table."
  value       = aws_dynamodb_table.this.arn
}

output "table_hash_key" {
  description = "The hash (partition) key of the table."
  value       = aws_dynamodb_table.this.hash_key
}

output "table_range_key" {
  description = "The range (sort) key of the table, if set."
  value       = aws_dynamodb_table.this.range_key
}

output "billing_mode" {
  description = "The billing mode of the table."
  value       = aws_dynamodb_table.this.billing_mode
}

output "table_class" {
  description = "The storage class of the table."
  value       = aws_dynamodb_table.this.table_class
}

################################################################################
# Stream Outputs
################################################################################

output "stream_arn" {
  description = "The ARN of the DynamoDB Stream. Null when streams are disabled."
  value       = aws_dynamodb_table.this.stream_arn
}

output "stream_label" {
  description = "A timestamp that uniquely identifies the stream. Null when streams are disabled."
  value       = aws_dynamodb_table.this.stream_label
}

################################################################################
# Index Outputs
################################################################################

output "global_secondary_index_names" {
  description = "List of GSI names configured on the table."
  value       = [for gsi in var.global_secondary_indexes : gsi.name]
}

output "local_secondary_index_names" {
  description = "List of LSI names configured on the table."
  value       = [for lsi in var.local_secondary_indexes : lsi.name]
}

################################################################################
# Autoscaling Outputs
################################################################################

output "autoscaling_table_read_target_arn" {
  description = "ARN of the read-capacity autoscaling target for the table. Null when autoscaling is disabled."
  value       = local.create_table_autoscaling ? aws_appautoscaling_target.table_read[0].arn : null
}

output "autoscaling_table_write_target_arn" {
  description = "ARN of the write-capacity autoscaling target for the table. Null when autoscaling is disabled."
  value       = local.create_table_autoscaling ? aws_appautoscaling_target.table_write[0].arn : null
}

output "autoscaling_gsi_target_arns" {
  description = "Map of GSI autoscaling target ARNs, keyed by \"<index>/<read|write>\"."
  value       = { for k, v in aws_appautoscaling_target.gsi : k => v.arn }
}

################################################################################
# CloudWatch Alarm Outputs
################################################################################

output "cloudwatch_alarm_arns" {
  description = "Map of CloudWatch alarm ARNs created by this module."
  value = var.create_cloudwatch_alarms ? {
    read_throttle  = aws_cloudwatch_metric_alarm.read_throttle[0].arn
    write_throttle = aws_cloudwatch_metric_alarm.write_throttle[0].arn
    system_errors  = aws_cloudwatch_metric_alarm.system_errors[0].arn
  } : {}
}

################################################################################
# Replica Outputs
################################################################################

output "replica_regions" {
  description = "List of regions where the global table is replicated."
  value       = [for r in var.replicas : r.region_name]
}

output "region" {
  description = "The AWS region where the table is created."
  value       = data.aws_region.current.region
}
