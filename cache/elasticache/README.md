# AWS ElastiCache

Creates an ElastiCache cluster with support for Redis, Valkey, Memcached, and ElastiCache Serverless. Includes subnet group, parameter group, security group, and optional CloudWatch alarms.

## Features

- **Multiple Engines**: Support for Redis, Valkey (open-source Redis fork), and Memcached
- **Serverless Option**: ElastiCache Serverless for Redis/Valkey with automatic scaling
- **Cluster Mode**: Redis/Valkey cluster mode (sharding) for horizontal scaling
- **High Availability**: Multi-AZ with automatic failover
- **Security**: Encryption at rest, encryption in transit (TLS), and AUTH token support
- **Monitoring**: Optional CloudWatch alarms for CPU, memory, connections, and evictions
- **Flexible Security Groups**: Create new or use existing security groups

## Usage

### Basic Redis Cluster

```hcl
module "redis" {
  source = "git::https://github.com/user/ravion-modules.git//cache/elasticache?ref=v1.0.0"

  name      = "my-redis"
  engine    = "redis"
  node_type = "cache.t4g.micro"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  allowed_security_group_ids = [module.app.security_group_id]

  tags = {
    Environment = "production"
  }
}
```

### Valkey Cluster (Redis-compatible, Open Source)

```hcl
module "valkey" {
  source = "git::https://github.com/user/ravion-modules.git//cache/elasticache?ref=v1.0.0"

  name           = "my-valkey"
  engine         = "valkey"
  engine_version = "8.0"
  node_type      = "cache.r7g.large"

  replicas_per_node_group    = 2
  automatic_failover_enabled = true
  multi_az_enabled           = true

  transit_encryption_enabled = true
  at_rest_encryption_enabled = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  allowed_security_group_ids = [module.app.security_group_id]
}
```

### Redis with Cluster Mode (Sharding)

```hcl
module "redis_cluster" {
  source = "git::https://github.com/user/ravion-modules.git//cache/elasticache?ref=v1.0.0"

  name                    = "my-redis-cluster"
  engine                  = "redis"
  node_type               = "cache.r7g.large"
  cluster_mode_enabled    = true
  num_node_groups         = 3
  replicas_per_node_group = 2

  automatic_failover_enabled = true
  multi_az_enabled           = true
  transit_encryption_enabled = true
  at_rest_encryption_enabled = true

  snapshot_retention_limit = 7
  snapshot_window          = "03:00-05:00"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  allowed_security_group_ids = [module.app.security_group_id]
}
```

### Memcached Cluster

```hcl
module "memcached" {
  source = "git::https://github.com/user/ravion-modules.git//cache/elasticache?ref=v1.0.0"

  name            = "my-memcached"
  engine          = "memcached"
  node_type       = "cache.t4g.micro"
  num_cache_nodes = 3

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  allowed_security_group_ids = [module.app.security_group_id]
}
```

### ElastiCache Serverless (Redis/Valkey)

```hcl
module "redis_serverless" {
  source = "git::https://github.com/user/ravion-modules.git//cache/elasticache?ref=v1.0.0"

  name               = "my-serverless-redis"
  engine             = "redis"
  serverless_enabled = true

  serverless_cache_usage_limits = {
    data_storage_maximum    = 10    # GB
    ecpu_per_second_maximum = 5000
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  allowed_security_group_ids = [module.app.security_group_id]
}
```

### With CloudWatch Alarms

```hcl
module "redis" {
  source = "git::https://github.com/user/ravion-modules.git//cache/elasticache?ref=v1.0.0"

  name      = "my-redis"
  engine    = "redis"
  node_type = "cache.t4g.small"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  allowed_security_group_ids = [module.app.security_group_id]

  # CloudWatch Alarms
  create_cloudwatch_alarms               = true
  cloudwatch_alarm_cpu_threshold         = 75
  cloudwatch_alarm_memory_threshold      = 80
  cloudwatch_alarm_connections_threshold = 500
  cloudwatch_alarm_actions               = [aws_sns_topic.alerts.arn]
  cloudwatch_ok_actions                  = [aws_sns_topic.alerts.arn]
}
```

### Using Existing Security Group

```hcl
module "redis" {
  source = "git::https://github.com/user/ravion-modules.git//cache/elasticache?ref=v1.0.0"

  name      = "my-redis"
  engine    = "redis"
  node_type = "cache.t4g.micro"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  # Use existing security group instead of creating one
  create_security_group = false
  security_group_id     = aws_security_group.existing.id
}
```

### With Custom Parameters

```hcl
module "redis" {
  source = "git::https://github.com/user/ravion-modules.git//cache/elasticache?ref=v1.0.0"

  name      = "my-redis"
  engine    = "redis"
  node_type = "cache.r7g.large"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  allowed_security_group_ids = [module.app.security_group_id]

  # Custom parameters
  parameter_group_family = "redis7"
  parameters = [
    {
      name  = "maxmemory-policy"
      value = "volatile-lru"
    },
    {
      name  = "notify-keyspace-events"
      value = "Ex"
    }
  ]
}
```

## Requirements

| Name               | Version   |
| ------------------ | --------- |
| opentofu/terraform | >= 1.10.0 |
| aws                | >= 5.0    |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Name prefix for all resources created by this module. | `string` | n/a | yes |
| vpc_id | The ID of the VPC where the ElastiCache cluster will be created. | `string` | n/a | yes |
| subnet_ids | A list of subnet IDs for the ElastiCache subnet group. | `list(string)` | n/a | yes |
| tags | A map of tags to assign to all resources. | `map(string)` | `{}` | no |
| engine | The cache engine to use: redis, valkey, or memcached. | `string` | `"redis"` | no |
| engine_version | The version number of the cache engine. | `string` | `null` | no |
| node_type | The compute and memory capacity of the nodes. | `string` | `"cache.t4g.micro"` | no |
| num_cache_nodes | The number of cache nodes (Memcached only). | `number` | `1` | no |
| num_node_groups | The number of node groups (shards) for Redis cluster mode. | `number` | `1` | no |
| replicas_per_node_group | The number of replica nodes in each node group. | `number` | `0` | no |
| cluster_mode_enabled | Enable cluster mode (sharding) for Redis/Valkey. | `bool` | `false` | no |
| port | The port number on which the cache accepts connections. | `number` | `null` (6379 for Redis/Valkey, 11211 for Memcached) | no |
| create_security_group | Whether to create a security group for the cluster. | `bool` | `true` | no |
| security_group_id | The ID of an existing security group to use. | `string` | `null` | no |
| allowed_security_group_ids | A list of security group IDs allowed to access the cluster. | `list(string)` | `[]` | no |
| allowed_cidr_blocks | A list of CIDR blocks allowed to access the cluster. | `list(string)` | `[]` | no |
| auth_token | The password for Redis/Valkey AUTH. Requires transit encryption. | `string` | `null` | no |
| transit_encryption_enabled | Enable encryption in-transit (TLS). | `bool` | `true` | no |
| at_rest_encryption_enabled | Enable encryption at-rest. | `bool` | `true` | no |
| kms_key_arn | The ARN of the KMS key for at-rest encryption. | `string` | `null` | no |
| automatic_failover_enabled | Enable automatic failover. Requires at least one replica. | `bool` | `false` | no |
| multi_az_enabled | Enable Multi-AZ support. | `bool` | `false` | no |
| snapshot_retention_limit | The number of days to retain automatic snapshots. | `number` | `0` | no |
| snapshot_window | The daily time range for automated backups (HH:MM-HH:MM). | `string` | `null` | no |
| final_snapshot_identifier | The name of the final snapshot on deletion. | `string` | `null` | no |
| maintenance_window | The weekly maintenance window (ddd:HH:MM-ddd:HH:MM). | `string` | `null` | no |
| apply_immediately | Whether to apply changes immediately. | `bool` | `false` | no |
| auto_minor_version_upgrade | Enable automatic minor version upgrades. | `bool` | `true` | no |
| parameter_group_family | The family of the parameter group. | `string` | `null` (auto-detected) | no |
| parameters | A list of parameter name/value pairs. | `list(object)` | `[]` | no |
| notification_topic_arn | The ARN of an SNS topic for notifications. | `string` | `null` | no |
| create_cloudwatch_alarms | Create CloudWatch alarms. | `bool` | `false` | no |
| cloudwatch_alarm_cpu_threshold | CPU utilization threshold (percent). | `number` | `80` | no |
| cloudwatch_alarm_memory_threshold | Memory utilization threshold (percent). | `number` | `80` | no |
| cloudwatch_alarm_connections_threshold | Current connections threshold. | `number` | `1000` | no |
| cloudwatch_alarm_actions | A list of ARNs to notify on ALARM state. | `list(string)` | `[]` | no |
| cloudwatch_ok_actions | A list of ARNs to notify on OK state. | `list(string)` | `[]` | no |
| serverless_enabled | Create an ElastiCache Serverless cache. | `bool` | `false` | no |
| serverless_cache_usage_limits | Usage limits for Serverless (data_storage_maximum in GB, ecpu_per_second_maximum). | `object` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| replication_group_id | The ID of the ElastiCache replication group (Redis/Valkey). |
| replication_group_arn | The ARN of the ElastiCache replication group. |
| primary_endpoint_address | The address of the primary endpoint (non-cluster mode). |
| reader_endpoint_address | The address of the reader endpoint (non-cluster mode). |
| configuration_endpoint_address | The address of the configuration endpoint (cluster mode). |
| cluster_id | The ID of the ElastiCache cluster (Memcached). |
| cluster_arn | The ARN of the ElastiCache cluster (Memcached). |
| cluster_address | The DNS name of the cache cluster (Memcached). |
| configuration_endpoint | The configuration endpoint (Memcached). |
| cache_nodes | List of cache node objects (Memcached). |
| serverless_cache_arn | The ARN of the ElastiCache Serverless cache. |
| serverless_cache_endpoint | The endpoint of the Serverless cache. |
| serverless_cache_reader_endpoint | The reader endpoint of the Serverless cache. |
| port | The port number on which the cache accepts connections. |
| engine | The cache engine used. |
| engine_version | The version of the cache engine. |
| security_group_id | The ID of the security group. |
| security_group_arn | The ARN of the security group. |
| subnet_group_name | The name of the ElastiCache subnet group. |
| parameter_group_name | The name of the ElastiCache parameter group. |
| cloudwatch_alarm_arns | Map of CloudWatch alarm ARNs. |

## Architecture

```
                    ┌─────────────────────────────────────────────────────┐
                    │              ElastiCache Module                      │
                    │  ┌───────────────────────────────────────────────┐  │
                    │  │        Replication Group (Redis/Valkey)       │  │
                    │  │  ┌─────────┐  ┌─────────┐  ┌─────────┐       │  │
                    │  │  │ Primary │  │ Replica │  │ Replica │       │  │
                    │  │  │  Node   │  │  Node   │  │  Node   │       │  │
                    │  │  └─────────┘  └─────────┘  └─────────┘       │  │
                    │  └───────────────────────────────────────────────┘  │
                    │                        OR                            │
                    │  ┌───────────────────────────────────────────────┐  │
                    │  │            Cluster (Memcached)                │  │
                    │  │  ┌─────────┐  ┌─────────┐  ┌─────────┐       │  │
                    │  │  │  Node   │  │  Node   │  │  Node   │       │  │
                    │  │  └─────────┘  └─────────┘  └─────────┘       │  │
                    │  └───────────────────────────────────────────────┘  │
                    │                        OR                            │
                    │  ┌───────────────────────────────────────────────┐  │
                    │  │          Serverless Cache (Redis/Valkey)      │  │
                    │  │              Auto-scaling capacity            │  │
                    │  └───────────────────────────────────────────────┘  │
                    │                                                      │
                    │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │
                    │  │   Subnet    │  │  Parameter  │  │  Security   │  │
                    │  │   Group     │  │   Group     │  │   Group     │  │
                    │  └─────────────┘  └─────────────┘  └─────────────┘  │
                    └─────────────────────────────────────────────────────┘
```

## Security Considerations

- **Encryption at Rest**: Enabled by default using AWS managed keys. Optionally provide your own KMS key.
- **Encryption in Transit**: TLS is enabled by default for Redis/Valkey.
- **AUTH Token**: Optionally configure a password for Redis/Valkey. Requires transit encryption.
- **VPC Only**: The cluster is deployed within your VPC with no public access.
- **Security Groups**: Fine-grained access control via security group rules.

## Notes

- For Redis/Valkey cluster mode, use `configuration_endpoint_address` to connect. For non-cluster mode, use `primary_endpoint_address`.
- Automatic failover requires at least one replica (`replicas_per_node_group >= 1`) or cluster mode enabled.
- Multi-AZ requires automatic failover to be enabled.
- Memcached does not support encryption at rest, encryption in transit, or replication.
- Serverless caches automatically scale and do not require node type configuration.
- Parameter group family is auto-detected from engine and version if not specified.
