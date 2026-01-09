################################################################################
# Replication Group Outputs (Redis/Valkey)
################################################################################

output "replication_group_id" {
  description = "The ID of the ElastiCache replication group."
  value       = local.create_replication_group ? aws_elasticache_replication_group.this[0].id : null
}

output "replication_group_arn" {
  description = "The ARN of the ElastiCache replication group."
  value       = local.create_replication_group ? aws_elasticache_replication_group.this[0].arn : null
}

output "primary_endpoint_address" {
  description = "The address of the primary endpoint for the replication group (non-cluster mode)."
  value       = local.create_replication_group && !local.cluster_mode_enabled ? aws_elasticache_replication_group.this[0].primary_endpoint_address : null
}

output "reader_endpoint_address" {
  description = "The address of the reader endpoint for the replication group (non-cluster mode)."
  value       = local.create_replication_group && !local.cluster_mode_enabled ? aws_elasticache_replication_group.this[0].reader_endpoint_address : null
}

output "configuration_endpoint_address" {
  description = "The address of the configuration endpoint for the replication group (cluster mode)."
  value       = local.create_replication_group && local.cluster_mode_enabled ? aws_elasticache_replication_group.this[0].configuration_endpoint_address : null
}

################################################################################
# Cluster Outputs (Memcached)
################################################################################

output "cluster_id" {
  description = "The ID of the ElastiCache cluster (Memcached)."
  value       = local.create_cluster ? aws_elasticache_cluster.this[0].cluster_id : null
}

output "cluster_arn" {
  description = "The ARN of the ElastiCache cluster (Memcached)."
  value       = local.create_cluster ? aws_elasticache_cluster.this[0].arn : null
}

output "cluster_address" {
  description = "The DNS name of the cache cluster without the port (Memcached)."
  value       = local.create_cluster ? aws_elasticache_cluster.this[0].cluster_address : null
}

output "configuration_endpoint" {
  description = "The configuration endpoint for the Memcached cluster."
  value       = local.create_cluster ? aws_elasticache_cluster.this[0].configuration_endpoint : null
}

output "cache_nodes" {
  description = "List of cache node objects with id, address, port, and availability_zone (Memcached)."
  value       = local.create_cluster ? aws_elasticache_cluster.this[0].cache_nodes : null
}

################################################################################
# Serverless Outputs (Redis/Valkey)
################################################################################

output "serverless_cache_arn" {
  description = "The ARN of the ElastiCache Serverless cache."
  value       = local.create_serverless_cache ? aws_elasticache_serverless_cache.this[0].arn : null
}

output "serverless_cache_endpoint" {
  description = "The endpoint of the ElastiCache Serverless cache."
  value       = local.create_serverless_cache ? aws_elasticache_serverless_cache.this[0].endpoint : null
}

output "serverless_cache_reader_endpoint" {
  description = "The reader endpoint of the ElastiCache Serverless cache."
  value       = local.create_serverless_cache ? aws_elasticache_serverless_cache.this[0].reader_endpoint : null
}

################################################################################
# Common Outputs
################################################################################

output "port" {
  description = "The port number on which the cache accepts connections."
  value       = local.port
}

output "engine" {
  description = "The cache engine used (redis, valkey, or memcached)."
  value       = var.engine
}

output "engine_version" {
  description = "The version of the cache engine."
  value = local.create_replication_group ? aws_elasticache_replication_group.this[0].engine_version_actual : (
    local.create_cluster ? aws_elasticache_cluster.this[0].engine_version_actual : var.engine_version
  )
}

################################################################################
# Security Group Outputs
################################################################################

output "security_group_id" {
  description = "The ID of the security group."
  value       = local.security_group_id
}

output "security_group_arn" {
  description = "The ARN of the security group."
  value       = local.create_security_group ? aws_security_group.this[0].arn : null
}

################################################################################
# Subnet Group Outputs
################################################################################

output "subnet_group_name" {
  description = "The name of the ElastiCache subnet group."
  value       = local.is_serverless ? null : aws_elasticache_subnet_group.this[0].name
}

output "subnet_group_arn" {
  description = "The ARN of the ElastiCache subnet group."
  value       = local.is_serverless ? null : aws_elasticache_subnet_group.this[0].arn
}

################################################################################
# Parameter Group Outputs
################################################################################

output "parameter_group_name" {
  description = "The name of the ElastiCache parameter group."
  value       = local.is_serverless ? null : aws_elasticache_parameter_group.this[0].name
}

output "parameter_group_arn" {
  description = "The ARN of the ElastiCache parameter group."
  value       = local.is_serverless ? null : aws_elasticache_parameter_group.this[0].arn
}

################################################################################
# CloudWatch Alarm Outputs
################################################################################

output "cloudwatch_alarm_arns" {
  description = "Map of CloudWatch alarm ARNs created by this module."
  value = local.create_cloudwatch_alarms ? {
    cpu_utilization     = aws_cloudwatch_metric_alarm.cpu_utilization[0].arn
    current_connections = aws_cloudwatch_metric_alarm.current_connections[0].arn
    evictions           = aws_cloudwatch_metric_alarm.evictions[0].arn
    memory_usage        = local.is_redis_compatible ? aws_cloudwatch_metric_alarm.database_memory_usage[0].arn : null
  } : {}
}
