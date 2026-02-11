################################################################################
# Cluster Outputs
################################################################################

output "cluster_id" {
  description = "The ID of the Aurora cluster."
  value       = aws_rds_cluster.this.id
}

output "cluster_arn" {
  description = "The ARN of the Aurora cluster."
  value       = aws_rds_cluster.this.arn
}

output "cluster_identifier" {
  description = "The cluster identifier of the Aurora cluster."
  value       = aws_rds_cluster.this.cluster_identifier
}

output "cluster_resource_id" {
  description = "The resource ID of the Aurora cluster."
  value       = aws_rds_cluster.this.cluster_resource_id
}

output "cluster_engine_version_actual" {
  description = "The actual engine version running on the Aurora cluster."
  value       = aws_rds_cluster.this.engine_version_actual
}

################################################################################
# Connection Outputs
################################################################################

output "cluster_endpoint" {
  description = "The writer endpoint for the Aurora cluster."
  value       = aws_rds_cluster.this.endpoint
}

output "cluster_reader_endpoint" {
  description = "The reader endpoint for the Aurora cluster (load-balanced across readers)."
  value       = aws_rds_cluster.this.reader_endpoint
}

output "cluster_port" {
  description = "The port on which the Aurora cluster accepts connections."
  value       = aws_rds_cluster.this.port
}

output "cluster_hosted_zone_id" {
  description = "The Route53 hosted zone ID of the Aurora cluster."
  value       = aws_rds_cluster.this.hosted_zone_id
}

################################################################################
# Database Outputs
################################################################################

output "cluster_database_name" {
  description = "The database name on the Aurora cluster."
  value       = aws_rds_cluster.this.database_name
}

output "cluster_master_username" {
  description = "The master username for the Aurora cluster."
  value       = aws_rds_cluster.this.master_username
}

output "cluster_master_user_secret_arn" {
  description = "The ARN of the Secrets Manager secret containing the master user credentials."
  value       = var.manage_master_user_password ? try(aws_rds_cluster.this.master_user_secret[0].secret_arn, null) : null
}

################################################################################
# Instance Outputs
################################################################################

output "instance_identifiers" {
  description = "Map of instance key to instance identifier."
  value       = { for k, v in aws_rds_cluster_instance.this : k => v.identifier }
}

output "instance_arns" {
  description = "Map of instance key to instance ARN."
  value       = { for k, v in aws_rds_cluster_instance.this : k => v.arn }
}

output "instance_endpoints" {
  description = "Map of instance key to instance endpoint."
  value       = { for k, v in aws_rds_cluster_instance.this : k => v.endpoint }
}

################################################################################
# Custom Endpoint Outputs
################################################################################

output "custom_endpoint_arns" {
  description = "Map of custom endpoint key to endpoint ARN."
  value       = { for k, v in aws_rds_cluster_endpoint.this : k => v.arn }
}

################################################################################
# Security Group Outputs
################################################################################

output "security_group_id" {
  description = "The ID of the security group."
  value       = local.create_security_group ? module.security_group[0].security_group_id : var.security_group_id
}

output "security_group_arn" {
  description = "The ARN of the security group."
  value       = local.create_security_group ? module.security_group[0].security_group_arn : null
}

################################################################################
# Subnet Group Outputs
################################################################################

output "db_subnet_group_name" {
  description = "The name of the DB subnet group."
  value       = local.db_subnet_group_name
}

output "db_subnet_group_arn" {
  description = "The ARN of the DB subnet group."
  value       = local.create_subnet_group ? aws_db_subnet_group.this[0].arn : null
}

################################################################################
# Parameter Group Outputs
################################################################################

output "cluster_parameter_group_name" {
  description = "The name of the cluster parameter group."
  value       = local.cluster_parameter_group_name
}

output "cluster_parameter_group_arn" {
  description = "The ARN of the cluster parameter group."
  value       = var.create_cluster_parameter_group ? aws_rds_cluster_parameter_group.this[0].arn : null
}

output "db_parameter_group_name" {
  description = "The name of the DB parameter group."
  value       = local.db_parameter_group_name
}

output "db_parameter_group_arn" {
  description = "The ARN of the DB parameter group."
  value       = var.create_db_parameter_group ? aws_db_parameter_group.this[0].arn : null
}

################################################################################
# Monitoring Outputs
################################################################################

output "enhanced_monitoring_iam_role_arn" {
  description = "The ARN of the IAM role used for Enhanced Monitoring."
  value       = local.create_monitoring_role ? aws_iam_role.monitoring[0].arn : var.monitoring_role_arn
}

output "cloudwatch_alarm_arns" {
  description = "Map of CloudWatch alarm ARNs created by this module."
  value = local.create_cloudwatch_alarms ? {
    cpu_utilization      = aws_cloudwatch_metric_alarm.cpu_utilization[0].arn
    freeable_memory      = aws_cloudwatch_metric_alarm.freeable_memory[0].arn
    database_connections = aws_cloudwatch_metric_alarm.database_connections[0].arn
  } : {}
}

################################################################################
# Global Database Outputs
################################################################################

output "global_cluster_id" {
  description = "The ID of the global cluster."
  value       = var.create_global_cluster ? aws_rds_global_cluster.this[0].id : null
}

output "global_cluster_arn" {
  description = "The ARN of the global cluster."
  value       = var.create_global_cluster ? aws_rds_global_cluster.this[0].arn : null
}

################################################################################
# Activity Stream Outputs
################################################################################

output "activity_stream_kinesis_stream_name" {
  description = "The name of the Kinesis data stream used for the database activity stream."
  value       = var.enable_activity_stream ? aws_rds_cluster_activity_stream.this[0].kinesis_stream_name : null
}

output "activity_stream_kms_key_id" {
  description = "The KMS key ID used for the database activity stream."
  value       = var.enable_activity_stream ? aws_rds_cluster_activity_stream.this[0].kms_key_id : null
}

################################################################################
# Auto-scaling Outputs
################################################################################

output "autoscaling_target_arn" {
  description = "The ARN of the Application Auto Scaling target."
  value       = var.enable_autoscaling ? aws_appautoscaling_target.this[0].arn : null
}
