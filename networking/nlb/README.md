# AWS Network Load Balancer

Creates a Network Load Balancer (NLB) infrastructure with access logging and static IP support.

Network Load Balancers operate at Layer 4 (Transport Layer) and are designed for high-performance TCP/UDP traffic. They support millions of requests per second with ultra-low latencies.

> **Note:** This module creates only the NLB infrastructure. Target groups and listeners are created by service modules (e.g., `ecs_service`) that use the NLB.

## Usage

### Basic NLB

```hcl
module "nlb" {
  source = "git::https://github.com/flightcontrolhq/modules.git//networking/nlb?ref=v1.0.0"

  name       = "main"
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnet_ids

  tags = {
    Environment = "production"
  }
}

# Service modules create their own listeners and target groups
module "api_service" {
  source = "git::https://github.com/flightcontrolhq/modules.git//compute/ecs_service?ref=v1.0.0"

  # ... service configuration ...

  load_balancer_attachment = {
    nlb_arn = module.nlb.nlb_arn
    nlb_listener = {
      port     = 443
      protocol = "TLS"
      # ... listener configuration ...
    }
    target_group = {
      port     = 8080
      protocol = "TCP"
    }
  }
}
```

### Internal NLB

```hcl
module "nlb" {
  source = "git::https://github.com/flightcontrolhq/modules.git//networking/nlb?ref=v1.0.0"

  name       = "internal"
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids
  internal   = true
}
```

### NLB with Static IPs (Elastic IPs)

For scenarios requiring static IP addresses (e.g., firewall rules):

```hcl
resource "aws_eip" "nlb" {
  count  = 2
  domain = "vpc"

  tags = {
    Name = "nlb-${count.index + 1}"
  }
}

module "nlb" {
  source = "git::https://github.com/flightcontrolhq/modules.git//networking/nlb?ref=v1.0.0"

  name       = "static-ip"
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnet_ids

  enable_elastic_ips        = true
  elastic_ip_allocation_ids = aws_eip.nlb[*].allocation_id
}
```

### NLB with Access Logs

```hcl
module "nlb" {
  source = "git::https://github.com/flightcontrolhq/modules.git//networking/nlb?ref=v1.0.0"

  name       = "logged"
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnet_ids

  # Access Logs - creates S3 bucket automatically
  enable_access_logs         = true
  access_logs_retention_days = 365
}
```

### Cross-Zone Load Balancing

Enable cross-zone load balancing to distribute traffic evenly across all targets:

```hcl
module "nlb" {
  source = "git::https://github.com/flightcontrolhq/modules.git//networking/nlb?ref=v1.0.0"

  name       = "cross-zone"
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnet_ids

  enable_cross_zone_load_balancing = true
}
```

## Requirements

| Name               | Version   |
| ------------------ | --------- |
| opentofu/terraform | >= 1.10.0 |
| aws                | >= 5.0    |

## Inputs

### General

| Name       | Description                                           | Type           | Default | Required |
| ---------- | ----------------------------------------------------- | -------------- | ------- | -------- |
| name       | Name prefix for all resources created by this module. | `string`       | n/a     | yes      |
| vpc_id     | The ID of the VPC where the NLB will be created.      | `string`       | n/a     | yes      |
| subnet_ids | A list of subnet IDs for the NLB.                     | `list(string)` | n/a     | yes      |
| tags       | A map of tags to assign to all resources.             | `map(string)`  | `{}`    | no       |

### NLB Settings

| Name                                                       | Description                                                   | Type           | Default | Required |
| ---------------------------------------------------------- | ------------------------------------------------------------- | -------------- | ------- | -------- |
| internal                                                   | If true, the NLB will be internal (not internet-facing).      | `bool`         | `false` | no       |
| security_group_ids                                         | A list of security group IDs to attach to the NLB.            | `list(string)` | `[]`    | no       |
| enable_deletion_protection                                 | Enable deletion protection on the NLB.                        | `bool`         | `false` | no       |
| enable_cross_zone_load_balancing                           | Enable cross-zone load balancing.                             | `bool`         | `false` | no       |
| dns_record_client_routing_policy                           | How traffic is distributed among NLB AZs.                     | `string`       | `null`  | no       |
| enforce_security_group_inbound_rules_on_private_link_traffic | Whether inbound SG rules are enforced for PrivateLink traffic. | `string`       | `null`  | no       |

### Elastic IPs

| Name                      | Description                                          | Type           | Default | Required |
| ------------------------- | ---------------------------------------------------- | -------------- | ------- | -------- |
| enable_elastic_ips        | Enable static IP addresses using Elastic IPs.        | `bool`         | `false` | no       |
| elastic_ip_allocation_ids | A list of Elastic IP allocation IDs, one per subnet. | `list(string)` | `[]`    | no       |

### Access Logs

| Name                           | Description                                                | Type     | Default | Required |
| ------------------------------ | ---------------------------------------------------------- | -------- | ------- | -------- |
| enable_access_logs             | Enable access logging for the NLB.                         | `bool`   | `false` | no       |
| access_logs_bucket_arn         | ARN of an existing S3 bucket for access logs.              | `string` | `null`  | no       |
| access_logs_prefix             | The S3 prefix for access logs.                             | `string` | `""`    | no       |
| access_logs_retention_days     | Days to retain access logs in S3.                          | `number` | `90`    | no       |
| access_logs_kms_key_id         | KMS key ID for S3 bucket encryption. If null, uses AES256. | `string` | `null`  | no       |
| access_logs_versioning_enabled | Enable versioning for the access logs S3 bucket.           | `bool`   | `false` | no       |

## Outputs

| Name                    | Description                                                          |
| ----------------------- | -------------------------------------------------------------------- |
| nlb_id                  | The ID of the Network Load Balancer.                                 |
| nlb_arn                 | The ARN of the Network Load Balancer.                                |
| nlb_arn_suffix          | The ARN suffix of the NLB for use with CloudWatch Metrics.           |
| nlb_dns_name            | The DNS name of the Network Load Balancer.                           |
| nlb_zone_id             | The canonical hosted zone ID of the NLB (for Route53 alias records). |
| access_logs_bucket_name | The name of the S3 bucket for access logs.                           |
| access_logs_bucket_arn  | The ARN of the S3 bucket for access logs.                            |

## Architecture

```
                    ┌─────────────────────────────────────────┐
                    │             NLB Module                  │
                    │                                         │
                    │  ┌─────────────┐                        │
Internet ─────────▶ │  │     NLB     │                        │
(TCP/UDP/TLS)       │  │  (Layer 4)  │                        │
                    │  └─────────────┘                        │
                    │         │                               │
                    │         │ nlb_arn                       │
                    └─────────┼───────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────────────────────────────┐
                    │         Service Modules                 │
                    │  (ecs_service, etc.)                    │
                    │                                         │
                    │  ┌─────────────────────────────────┐    │
                    │  │     Listeners (per service)     │    │
                    │  │  ┌─────┐ ┌─────┐ ┌─────┐       │    │
                    │  │  │:443 │ │:8080│ │:53  │  ...  │    │
                    │  │  │TLS  │ │TCP  │ │UDP  │       │    │
                    │  │  └──┬──┘ └──┬──┘ └──┬──┘       │    │
                    │  └─────┼──────┼──────┼───────────┘    │
                    │        │      │      │                 │
                    │        ▼      ▼      ▼                 │
                    │  ┌─────────────────────────────────┐   │
                    │  │   Target Groups (per service)   │   │
                    │  │  ┌─────┐ ┌─────┐ ┌─────┐       │   │
                    │  │  │ api │ │ web │ │ dns │  ...  │   │
                    │  │  └─────┘ └─────┘ └─────┘       │   │
                    │  └─────────────────────────────────┘   │
                    └─────────────────────────────────────────┘
```

## ALB vs NLB Comparison

| Feature            | ALB                  | NLB                               |
| ------------------ | -------------------- | --------------------------------- |
| OSI Layer          | Layer 7 (HTTP/HTTPS) | Layer 4 (TCP/UDP/TLS)             |
| Protocols          | HTTP, HTTPS          | TCP, UDP, TLS, TCP_UDP            |
| Latency            | Low (~ms)            | Ultra-low (~µs)                   |
| Static IPs         | No                   | Yes (via Elastic IPs)             |
| Security Groups    | Yes (required)       | Optional                          |
| Path-based routing | Yes                  | No                                |
| Host-based routing | Yes                  | No                                |
| WebSocket          | Yes                  | Yes (TCP)                         |
| WAF Integration    | Yes                  | No                                |
| Use Case           | Web applications     | High-performance TCP/UDP services |

## When to Use NLB

- **High-performance requirements**: Millions of requests per second with microsecond latencies
- **TCP/UDP protocols**: Non-HTTP services (databases, gaming, IoT, gRPC, etc.)
- **Static IPs required**: Clients need to whitelist specific IP addresses
- **Pass-through TLS**: When TLS termination should happen at the backend
- **Preserve client IP**: When client IP address must be preserved without X-Forwarded-For
- **UDP traffic**: DNS, gaming, streaming, VoIP, etc.

## Security Considerations

- **Security Groups**: While optional, you can attach security groups to control traffic.
- **Client IP Preservation**: NLB preserves the client's source IP by default (for non-TLS targets).
- **Access Logs**: Enable access logging for audit trails and troubleshooting.

## Notes

- At least 1 subnet is required (2+ recommended for high availability).
- Cross-zone load balancing is disabled by default (AWS charges for cross-zone data transfer).
- Static IPs via Elastic IPs are only supported for internet-facing NLBs.
- Target groups and listeners are created by service modules that reference this NLB via `nlb_arn`.
