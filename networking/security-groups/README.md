# AWS Security Groups

Creates an AWS Security Group with configurable ingress and egress rules using the modern `aws_vpc_security_group_ingress_rule` and `aws_vpc_security_group_egress_rule` resources.

This module can be used both standalone (called directly by users) and internally by other modules in this library.

## Features

- **Flexible Rules**: Support for multiple ingress and egress rules with different source/destination types
- **Multiple Source Types**: CIDR blocks (IPv4/IPv6), security group references, prefix lists, and self-referencing
- **Modern Resources**: Uses `aws_vpc_security_group_ingress_rule` and `aws_vpc_security_group_egress_rule` for better state management
- **Lifecycle Management**: `create_before_destroy` for zero-downtime updates
- **Consistent Tagging**: Automatic ManagedBy and Module tags

## Usage

### Basic Security Group with All Egress

```hcl
module "security_group" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//networking/security-groups?ref=v1.0.0"

  name        = "my-app"
  name_suffix = "web"
  description = "Security group for web servers"
  vpc_id      = "vpc-12345678"

  allow_all_egress = true

  ingress_rules = [
    {
      description = "Allow HTTP from anywhere"
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
    },
    {
      description = "Allow HTTPS from anywhere"
      from_port   = 443
      to_port     = 443
      ip_protocol = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
    }
  ]

  tags = {
    Environment = "production"
  }
}
```

### Database Security Group with Restricted Egress

```hcl
module "database_sg" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//networking/security-groups?ref=v1.0.0"

  name        = "my-db"
  name_suffix = "postgres"
  description = "Security group for PostgreSQL database"
  vpc_id      = "vpc-12345678"

  ingress_rules = [
    {
      description                  = "Allow PostgreSQL from app servers"
      from_port                    = 5432
      to_port                      = 5432
      ip_protocol                  = "tcp"
      referenced_security_group_id = "sg-app12345"
    },
    {
      description = "Allow PostgreSQL from VPC"
      from_port   = 5432
      to_port     = 5432
      ip_protocol = "tcp"
      cidr_ipv4   = "10.0.0.0/16"
    }
  ]

  # Restrict egress to VPC only
  egress_rules = [
    {
      description = "Allow outbound to VPC"
      from_port   = 0
      to_port     = 0
      ip_protocol = "-1"
      cidr_ipv4   = "10.0.0.0/16"
    }
  ]

  tags = {
    Environment = "production"
  }
}
```

### Cache Security Group (ElastiCache Pattern)

```hcl
module "cache_sg" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//networking/security-groups?ref=v1.0.0"

  name        = "my-cache"
  name_suffix = "elasticache"
  description = "Security group for ElastiCache Redis cluster"
  vpc_id      = "vpc-12345678"

  ingress_rules = [
    {
      description                  = "Allow Redis from app-1"
      from_port                    = 6379
      to_port                      = 6379
      ip_protocol                  = "tcp"
      referenced_security_group_id = "sg-app1"
    },
    {
      description                  = "Allow Redis from app-2"
      from_port                    = 6379
      to_port                      = 6379
      ip_protocol                  = "tcp"
      referenced_security_group_id = "sg-app2"
    },
    {
      description = "Allow Redis from VPC"
      from_port   = 6379
      to_port     = 6379
      ip_protocol = "tcp"
      cidr_ipv4   = "10.0.0.0/16"
    }
  ]

  egress_rules = [
    {
      description = "Allow outbound to VPC"
      from_port   = 0
      to_port     = 0
      ip_protocol = "-1"
      cidr_ipv4   = "10.0.0.0/16"
    }
  ]

  tags = {
    Environment = "production"
  }
}
```

### Load Balancer Security Group (ALB Pattern)

```hcl
module "alb_sg" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//networking/security-groups?ref=v1.0.0"

  name        = "main"
  name_suffix = "alb"
  description = "Security group for Application Load Balancer"
  vpc_id      = "vpc-12345678"

  allow_all_egress = true

  ingress_rules = [
    # HTTP from anywhere (IPv4)
    {
      description = "Allow HTTP"
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
    },
    # HTTP from anywhere (IPv6)
    {
      description = "Allow HTTP IPv6"
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      cidr_ipv6   = "::/0"
    },
    # HTTPS from anywhere (IPv4)
    {
      description = "Allow HTTPS"
      from_port   = 443
      to_port     = 443
      ip_protocol = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
    },
    # HTTPS from anywhere (IPv6)
    {
      description = "Allow HTTPS IPv6"
      from_port   = 443
      to_port     = 443
      ip_protocol = "tcp"
      cidr_ipv6   = "::/0"
    }
  ]

  tags = {
    Environment = "production"
  }
}
```

### Self-Referencing Security Group (Cluster Pattern)

```hcl
module "cluster_sg" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//networking/security-groups?ref=v1.0.0"

  name        = "my-cluster"
  name_suffix = "internal"
  description = "Security group for cluster internal communication"
  vpc_id      = "vpc-12345678"

  allow_all_egress = true

  ingress_rules = [
    {
      description = "Allow all traffic from cluster members"
      from_port   = 0
      to_port     = 0
      ip_protocol = "-1"
      self        = true
    }
  ]

  tags = {
    Environment = "production"
  }
}
```

### ECS Service Security Group

```hcl
module "ecs_service_sg" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//networking/security-groups?ref=v1.0.0"

  name        = "my-service"
  name_suffix = "ecs-service"
  description = "Security group for ECS service"
  vpc_id      = "vpc-12345678"

  allow_all_egress = true

  ingress_rules = [
    {
      description                  = "Allow traffic from ALB"
      from_port                    = 8080
      to_port                      = 8080
      ip_protocol                  = "tcp"
      referenced_security_group_id = module.alb_sg.security_group_id
    }
  ]

  tags = {
    Environment = "production"
  }
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
| name | Name prefix for the security group. | `string` | n/a | yes |
| vpc_id | The ID of the VPC where the security group will be created. | `string` | n/a | yes |
| name_suffix | Suffix to append to the security group name. | `string` | `"sg"` | no |
| description | Description of the security group. | `string` | `"Managed by Terraform"` | no |
| tags | A map of tags to assign to all resources. | `map(string)` | `{}` | no |
| ingress_rules | List of ingress rules. Each rule specifies port range, protocol, and source. | `list(object)` | `[]` | no |
| egress_rules | List of egress rules. Each rule specifies port range, protocol, and destination. | `list(object)` | `[]` | no |
| allow_all_egress | Create default egress rules allowing all outbound traffic. | `bool` | `false` | no |
| allow_all_egress_ipv4_only | Only create IPv4 egress rule when allow_all_egress is true. | `bool` | `false` | no |

### Ingress/Egress Rule Object

| Attribute | Description | Type | Required |
|-----------|-------------|------|----------|
| from_port | Start of port range (0 for all ports with protocol -1) | `number` | yes |
| to_port | End of port range (0 for all ports with protocol -1) | `number` | yes |
| ip_protocol | Protocol: tcp, udp, icmp, icmpv6, or -1 for all | `string` | no (default: tcp) |
| description | Rule description | `string` | no |
| cidr_ipv4 | IPv4 CIDR block | `string` | One source/dest required |
| cidr_ipv6 | IPv6 CIDR block | `string` | One source/dest required |
| referenced_security_group_id | Security group ID | `string` | One source/dest required |
| prefix_list_id | Managed prefix list ID | `string` | One source/dest required |
| self | Reference this security group | `bool` | One source/dest required |

## Outputs

| Name | Description |
|------|-------------|
| security_group_id | The ID of the security group. |
| security_group_arn | The ARN of the security group. |
| security_group_name | The name of the security group. |
| security_group_vpc_id | The VPC ID of the security group. |
| security_group_owner_id | The owner ID (AWS account ID) of the security group. |
| ingress_rule_ids | Map of ingress rule keys to their IDs. |
| ingress_rule_arns | Map of ingress rule keys to their ARNs. |
| egress_rule_ids | Map of egress rule keys to their IDs. |
| egress_rule_arns | Map of egress rule keys to their ARNs. |

## Notes

- The security group uses `create_before_destroy` lifecycle to enable zero-downtime updates.
- Each rule must specify exactly one source (ingress) or destination (egress) type.
- When using `ip_protocol = "-1"` (all protocols), set `from_port = 0` and `to_port = 0`.
- The `self` attribute creates a self-referencing rule that allows traffic from/to members of the same security group.
