# AWS VPC Module

Creates a production-ready AWS VPC with public and private subnets, optional NAT Gateway, IPv6 support, and VPC Flow Logs.

## Features

- Configurable VPC CIDR block
- Public and private subnets across multiple availability zones
- Automatic or custom subnet CIDR allocation
- Optional NAT Gateway (single or per-AZ for high availability)
- Optional IPv6 support with Amazon-provided CIDR
- Optional VPC Flow Logs to CloudWatch or S3
- DNS support and hostnames enabled by default

## Usage

### Basic Usage

```hcl
module "vpc" {
  source = "git::https://github.com/flightcontrolhq/modules.git//networking/vpc?ref=v1.0.0"

  name     = "my-vpc"
  vpc_cidr = "10.0.0.0/16"
}
```

### With NAT Gateway (Single - Cost Effective)

```hcl
module "vpc" {
  source = "git::https://github.com/flightcontrolhq/modules.git//networking/vpc?ref=v1.0.0"

  name               = "my-vpc"
  vpc_cidr           = "10.0.0.0/16"
  enable_nat_gateway = true
  single_nat_gateway = true  # Default: single NAT for all private subnets
}
```

### With NAT Gateway (High Availability)

```hcl
module "vpc" {
  source = "git::https://github.com/flightcontrolhq/modules.git//networking/vpc?ref=v1.0.0"

  name               = "my-vpc"
  vpc_cidr           = "10.0.0.0/16"
  enable_nat_gateway = true
  single_nat_gateway = false  # One NAT per AZ for high availability
}
```

### With IPv6 Support

```hcl
module "vpc" {
  source = "git::https://github.com/flightcontrolhq/modules.git//networking/vpc?ref=v1.0.0"

  name        = "my-vpc"
  vpc_cidr    = "10.0.0.0/16"
  enable_ipv6 = true
}
```

### With VPC Flow Logs to CloudWatch

```hcl
module "vpc" {
  source = "git::https://github.com/flightcontrolhq/modules.git//networking/vpc?ref=v1.0.0"

  name                     = "my-vpc"
  vpc_cidr                 = "10.0.0.0/16"
  enable_flow_logs         = true
  flow_logs_destination    = "cloudwatch"
  flow_logs_retention_days = 30
}
```

### With VPC Flow Logs to S3 (New Bucket)

```hcl
module "vpc" {
  source = "git::https://github.com/flightcontrolhq/modules.git//networking/vpc?ref=v1.0.0"

  name                  = "my-vpc"
  vpc_cidr              = "10.0.0.0/16"
  enable_flow_logs      = true
  flow_logs_destination = "s3"
  # A new S3 bucket will be created automatically
}
```

### With VPC Flow Logs to S3 (Existing Bucket)

```hcl
module "vpc" {
  source = "git::https://github.com/flightcontrolhq/modules.git//networking/vpc?ref=v1.0.0"

  name                    = "my-vpc"
  vpc_cidr                = "10.0.0.0/16"
  enable_flow_logs        = true
  flow_logs_destination   = "s3"
  flow_logs_s3_bucket_arn = "arn:aws:s3:::my-existing-flow-logs-bucket"
}
```

### Custom Subnet Configuration

```hcl
module "vpc" {
  source = "git::https://github.com/flightcontrolhq/modules.git//networking/vpc?ref=v1.0.0"

  name         = "my-vpc"
  vpc_cidr     = "10.0.0.0/16"
  subnet_count = 3

  # Custom CIDRs (must match subnet_count)
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.20.0/24", "10.0.30.0/24"]

  # Specific availability zones
  availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
}
```

### Full Example

```hcl
module "vpc" {
  source = "git::https://github.com/flightcontrolhq/modules.git//networking/vpc?ref=v1.0.0"

  name                 = "production"
  vpc_cidr             = "10.0.0.0/16"
  subnet_count         = 3
  enable_dns_support   = true
  enable_dns_hostnames = true

  # NAT Gateway
  enable_nat_gateway = true
  single_nat_gateway = false  # HA: one NAT per AZ

  # IPv6
  enable_ipv6 = true

  # Flow Logs
  enable_flow_logs         = true
  flow_logs_destination    = "cloudwatch"
  flow_logs_retention_days = 90
  flow_logs_traffic_type   = "ALL"

  tags = {
    Environment = "production"
    Project     = "my-project"
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| opentofu/terraform | >= 1.10.0 |
| aws | >= 5.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name | Name prefix for all resources created by this module. | `string` | n/a | yes |
| vpc_cidr | The IPv4 CIDR block for the VPC. | `string` | `"10.0.0.0/16"` | no |
| subnet_count | The number of public and private subnet pairs to create. | `number` | `3` | no |
| availability_zones | A list of availability zones to use for subnets. If empty, AZs will be automatically selected. | `list(string)` | `[]` | no |
| public_subnet_cidrs | A list of CIDR blocks for public subnets. If null, CIDRs will be automatically calculated. | `list(string)` | `null` | no |
| private_subnet_cidrs | A list of CIDR blocks for private subnets. If null, CIDRs will be automatically calculated. | `list(string)` | `null` | no |
| enable_dns_support | Enable DNS support in the VPC. | `bool` | `true` | no |
| enable_dns_hostnames | Enable DNS hostnames in the VPC. | `bool` | `true` | no |
| enable_nat_gateway | Enable NAT Gateway(s) to allow private subnets to access the internet. | `bool` | `false` | no |
| single_nat_gateway | Use a single NAT Gateway for all private subnets (cost-effective). Set to false for high availability. | `bool` | `true` | no |
| enable_ipv6 | Enable IPv6 support for the VPC. An Amazon-provided IPv6 CIDR block will be assigned. | `bool` | `false` | no |
| enable_flow_logs | Enable VPC Flow Logs for network traffic monitoring. | `bool` | `false` | no |
| flow_logs_destination | The destination for VPC Flow Logs. Valid values: 'cloudwatch' or 's3'. | `string` | `"cloudwatch"` | no |
| flow_logs_s3_bucket_arn | The ARN of an existing S3 bucket for VPC Flow Logs. If null and destination is 's3', a new bucket will be created. | `string` | `null` | no |
| flow_logs_retention_days | The number of days to retain VPC Flow Logs in CloudWatch. Set to 0 for indefinite retention. | `number` | `30` | no |
| flow_logs_traffic_type | The type of traffic to capture in VPC Flow Logs. Valid values: 'ACCEPT', 'REJECT', or 'ALL'. | `string` | `"ALL"` | no |
| tags | A map of tags to assign to all resources. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| vpc_id | The ID of the VPC. |
| vpc_arn | The ARN of the VPC. |
| vpc_cidr_block | The IPv4 CIDR block of the VPC. |
| vpc_ipv6_cidr_block | The IPv6 CIDR block of the VPC (if IPv6 is enabled). |
| public_subnet_ids | List of IDs of public subnets. |
| private_subnet_ids | List of IDs of private subnets. |
| public_subnet_cidrs | List of IPv4 CIDR blocks of public subnets. |
| private_subnet_cidrs | List of IPv4 CIDR blocks of private subnets. |
| public_subnet_ipv6_cidrs | List of IPv6 CIDR blocks of public subnets (if IPv6 is enabled). |
| private_subnet_ipv6_cidrs | List of IPv6 CIDR blocks of private subnets (if IPv6 is enabled). |
| public_subnet_arns | List of ARNs of public subnets. |
| private_subnet_arns | List of ARNs of private subnets. |
| availability_zones | List of availability zones used for subnets. |
| internet_gateway_id | The ID of the Internet Gateway. |
| internet_gateway_arn | The ARN of the Internet Gateway. |
| nat_gateway_ids | List of NAT Gateway IDs (if NAT Gateway is enabled). |
| nat_gateway_public_ips | List of public IP addresses of NAT Gateways (if NAT Gateway is enabled). |
| nat_gateway_allocation_ids | List of Elastic IP allocation IDs for NAT Gateways (if NAT Gateway is enabled). |
| public_route_table_id | The ID of the public route table. |
| private_route_table_ids | List of IDs of private route tables. |
| egress_only_internet_gateway_id | The ID of the Egress-Only Internet Gateway (if IPv6 is enabled). |
| flow_log_id | The ID of the VPC Flow Log (if flow logs are enabled). |
| flow_log_cloudwatch_log_group_name | The name of the CloudWatch Log Group for VPC Flow Logs (if destination is cloudwatch). |
| flow_log_cloudwatch_log_group_arn | The ARN of the CloudWatch Log Group for VPC Flow Logs (if destination is cloudwatch). |
| flow_log_cloudwatch_iam_role_arn | The ARN of the IAM Role for VPC Flow Logs to CloudWatch (if destination is cloudwatch). |
| flow_log_s3_bucket_arn | The ARN of the S3 bucket for VPC Flow Logs (if destination is s3). |

## Architecture

```
VPC (vpc_cidr)
├── Internet Gateway
├── Public Subnets (subnet_count)
│   ├── Route Table → Internet Gateway (0.0.0.0/0)
│   └── IPv6 Route → Internet Gateway (::/0) [if enable_ipv6]
├── Private Subnets (subnet_count)
│   ├── Route Table(s) → NAT Gateway [if enable_nat_gateway]
│   │   └── 1 table if single_nat_gateway, else 1 per AZ
│   └── IPv6 Route → Egress-Only IGW (::/0) [if enable_ipv6]
├── NAT Gateway(s) [if enable_nat_gateway]
│   └── 1 if single_nat_gateway, else 1 per AZ
├── Egress-Only Internet Gateway [if enable_ipv6]
└── Flow Logs [if enable_flow_logs]
    ├── CloudWatch Log Group + IAM Role [if destination = cloudwatch]
    └── S3 Bucket (existing or new) [if destination = s3]
```

## Subnet CIDR Allocation

When `public_subnet_cidrs` or `private_subnet_cidrs` are not provided, CIDRs are automatically calculated:

| VPC CIDR | Public Subnets | Private Subnets |
|----------|----------------|-----------------|
| 10.0.0.0/16 | 10.0.1.0/24, 10.0.2.0/24, 10.0.3.0/24 | 10.0.11.0/24, 10.0.12.0/24, 10.0.13.0/24 |

The formula used:
- Public subnets: `cidrsubnet(vpc_cidr, 8, i + 1)` where i = 0, 1, 2...
- Private subnets: `cidrsubnet(vpc_cidr, 8, i + 11)` where i = 0, 1, 2...

## NAT Gateway Strategies

| Strategy | Description | Cost | Availability |
|----------|-------------|------|--------------|
| `single_nat_gateway = true` | One NAT Gateway shared by all private subnets | Lower | Single point of failure |
| `single_nat_gateway = false` | One NAT Gateway per AZ | Higher | High availability |

## License

This module is part of the Ravion Modules library and is licensed under the AGPL-3.0 license.
