# ECS Cluster Module

This module creates an Amazon ECS cluster with configurable capacity providers (Fargate, Fargate Spot, EC2) and optional Application Load Balancers and Network Load Balancers.

## Features

- ECS cluster with optional CloudWatch Container Insights
- Fargate capacity provider (enabled by default)
- Fargate Spot capacity provider
- EC2 capacity provider with Auto Scaling Group and managed scaling
- Optional public (internet-facing) Application Load Balancer
- Optional private (internal) Application Load Balancer
- Optional public (internet-facing) Network Load Balancer
- Optional private (internal) Network Load Balancer
- Full launch template support for EC2 instances
- IMDSv2 enforcement for enhanced security
- Mixed instances policy with Spot support

## Usage

### Basic Fargate Cluster

```hcl
module "ecs" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//compute/ecs_cluster?ref=v1.0.0"

  name   = "my-app"
  vpc_id = "vpc-12345678"

  private_subnet_ids = ["subnet-1a2b3c4d", "subnet-5e6f7g8h"]
}
```

### Fargate with Public ALB

```hcl
module "ecs" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//compute/ecs_cluster?ref=v1.0.0"

  name   = "my-app"
  vpc_id = "vpc-12345678"

  private_subnet_ids = ["subnet-private-1", "subnet-private-2"]
  public_subnet_ids  = ["subnet-public-1", "subnet-public-2"]

  # Enable Fargate Spot for cost savings
  enable_fargate_spot = true
  fargate_weight      = 1
  fargate_spot_weight = 3

  # Public ALB with HTTPS
  enable_public_alb          = true
  public_alb_enable_https    = true
  public_alb_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abc123"
}
```

### EC2 Capacity Provider

```hcl
module "ecs" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//compute/ecs_cluster?ref=v1.0.0"

  name   = "my-app"
  vpc_id = "vpc-12345678"

  private_subnet_ids = ["subnet-private-1", "subnet-private-2"]
  public_subnet_ids  = ["subnet-public-1", "subnet-public-2"]

  # Disable Fargate, use EC2 only
  enable_fargate = false

  # EC2 capacity provider
  ec2_instance_type    = "t3.medium"
  ec2_min_size         = 1
  ec2_max_size         = 10
  ec2_desired_capacity = 2

  # Enable Spot instances
  ec2_enable_spot             = true
  ec2_spot_instance_types     = ["t3.large", "t3a.medium", "t3a.large"]
  ec2_on_demand_base_capacity = 1
  ec2_on_demand_percentage_above_base = 25

  # Public ALB
  enable_public_alb = true
}
```

### Mixed Capacity Providers

```hcl
module "ecs" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//compute/ecs_cluster?ref=v1.0.0"

  name   = "my-app"
  vpc_id = "vpc-12345678"

  private_subnet_ids = ["subnet-private-1", "subnet-private-2"]
  public_subnet_ids  = ["subnet-public-1", "subnet-public-2"]

  # Enable all capacity providers
  enable_fargate      = true
  enable_fargate_spot = true
  fargate_weight      = 1
  fargate_spot_weight = 2

  # EC2 for baseline capacity
  ec2_instance_type    = "t3.large"
  ec2_min_size         = 2
  ec2_max_size         = 20
  ec2_desired_capacity = 2
  ec2_weight           = 1
  ec2_base             = 2  # Always run 2 tasks on EC2

  # Both ALBs
  enable_public_alb           = true
  public_alb_enable_https     = true
  public_alb_certificate_arn  = "arn:aws:acm:us-east-1:123456789012:certificate/abc123"

  enable_private_alb          = true
  private_alb_enable_https    = true
  private_alb_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/xyz789"

  tags = {
    Environment = "production"
    Team        = "platform"
  }
}
```

### With Network Load Balancer

```hcl
module "ecs" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//compute/ecs_cluster?ref=v1.0.0"

  name   = "my-app"
  vpc_id = "vpc-12345678"

  private_subnet_ids = ["subnet-private-1", "subnet-private-2"]
  public_subnet_ids  = ["subnet-public-1", "subnet-public-2"]

  # Public NLB (listeners and target groups created by service modules)
  enable_public_nlb = true
}
```

### With NLB and Cross-Zone Load Balancing

```hcl
module "ecs" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//compute/ecs_cluster?ref=v1.0.0"

  name   = "my-app"
  vpc_id = "vpc-12345678"

  private_subnet_ids = ["subnet-private-1", "subnet-private-2"]
  public_subnet_ids  = ["subnet-public-1", "subnet-public-2"]

  # Public NLB (listeners and target groups created by service modules)
  enable_public_nlb = true
  public_nlb_enable_cross_zone_load_balancing = true
}

# Service modules create their own listeners and target groups
module "api_service" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//compute/ecs_service?ref=v1.0.0"

  # ... service configuration ...

  load_balancer_attachment = {
    nlb_arn = module.ecs.public_nlb_arn
    nlb_listener = {
      port            = 443
      protocol        = "TLS"
      certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abc123"
    }
    target_group = {
      port     = 8080
      protocol = "TCP"
    }
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| opentofu/terraform | >= 1.10.0 |
| aws | >= 5.0 |

## Inputs

### General

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Name prefix for all resources | `string` | n/a | yes |
| tags | Map of tags to assign to resources | `map(string)` | `{}` | no |
| vpc_id | VPC ID for ECS resources | `string` | n/a | yes |
| private_subnet_ids | Private subnet IDs for ECS tasks | `list(string)` | n/a | yes |
| public_subnet_ids | Public subnet IDs for public ALB | `list(string)` | `[]` | no |

### ECS Cluster

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| enable_container_insights | Enable CloudWatch Container Insights | `bool` | `true` | no |

### Fargate Capacity Provider

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| enable_fargate | Enable Fargate capacity provider | `bool` | `true` | no |
| fargate_weight | Fargate weight in default strategy | `number` | `1` | no |
| fargate_base | Base tasks on Fargate | `number` | `0` | no |

### Fargate Spot Capacity Provider

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| enable_fargate_spot | Enable Fargate Spot capacity provider | `bool` | `false` | no |
| fargate_spot_weight | Fargate Spot weight in default strategy | `number` | `1` | no |
| fargate_spot_base | Base tasks on Fargate Spot | `number` | `0` | no |

### EC2 Capacity Provider

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| ec2_instance_type | EC2 instance type (null to disable) | `string` | `null` | no |
| ec2_ami_id | AMI ID (null for latest ECS-optimized) | `string` | `null` | no |
| ec2_key_name | EC2 key pair name for SSH | `string` | `null` | no |
| ec2_min_size | ASG minimum size | `number` | `0` | no |
| ec2_max_size | ASG maximum size | `number` | `10` | no |
| ec2_desired_capacity | ASG desired capacity | `number` | `1` | no |
| ec2_enable_spot | Enable Spot instances | `bool` | `false` | no |
| ec2_spot_instance_types | Additional instance types for Spot | `list(string)` | `[]` | no |
| ec2_on_demand_base_capacity | On-Demand base capacity | `number` | `0` | no |
| ec2_on_demand_percentage_above_base | On-Demand percentage above base | `number` | `0` | no |
| ec2_root_volume_size | Root volume size in GB | `number` | `30` | no |
| ec2_root_volume_type | Root volume type | `string` | `"gp3"` | no |
| ec2_user_data | Additional user data script | `string` | `""` | no |
| ec2_enable_imdsv2 | Require IMDSv2 | `bool` | `true` | no |
| ec2_weight | EC2 weight in default strategy | `number` | `1` | no |
| ec2_base | Base tasks on EC2 | `number` | `0` | no |
| ec2_managed_termination_protection | Managed termination protection | `string` | `"ENABLED"` | no |
| ec2_managed_scaling_status | Enable managed scaling | `string` | `"ENABLED"` | no |
| ec2_managed_scaling_target_capacity | Target capacity percentage | `number` | `100` | no |
| ec2_security_group_ids | Additional security groups for EC2 | `list(string)` | `[]` | no |

### Public ALB

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| enable_public_alb | Enable public ALB | `bool` | `false` | no |
| public_alb_enable_https | Enable HTTPS listener | `bool` | `false` | no |
| public_alb_certificate_arn | ACM certificate ARN for HTTPS | `string` | `null` | no |
| public_alb_ssl_policy | SSL policy for HTTPS | `string` | `"ELBSecurityPolicy-TLS13-1-2-2021-06"` | no |
| public_alb_idle_timeout | Idle timeout in seconds | `number` | `60` | no |
| public_alb_enable_deletion_protection | Enable deletion protection | `bool` | `false` | no |
| public_alb_ingress_cidr_blocks | Allowed IPv4 CIDR blocks | `list(string)` | `["0.0.0.0/0"]` | no |
| public_alb_enable_access_logs | Enable access logs | `bool` | `false` | no |
| public_alb_access_logs_bucket_arn | S3 bucket ARN for access logs | `string` | `null` | no |
| public_alb_web_acl_arn | WAFv2 Web ACL ARN | `string` | `null` | no |

### Private ALB

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| enable_private_alb | Enable private ALB | `bool` | `false` | no |
| private_alb_enable_https | Enable HTTPS listener | `bool` | `false` | no |
| private_alb_certificate_arn | ACM certificate ARN for HTTPS | `string` | `null` | no |
| private_alb_ssl_policy | SSL policy for HTTPS | `string` | `"ELBSecurityPolicy-TLS13-1-2-2021-06"` | no |
| private_alb_idle_timeout | Idle timeout in seconds | `number` | `60` | no |
| private_alb_enable_deletion_protection | Enable deletion protection | `bool` | `false` | no |
| private_alb_ingress_cidr_blocks | Allowed IPv4 CIDR blocks | `list(string)` | `["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]` | no |
| private_alb_enable_access_logs | Enable access logs | `bool` | `false` | no |
| private_alb_access_logs_bucket_arn | S3 bucket ARN for access logs | `string` | `null` | no |

### Public NLB

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| enable_public_nlb | Enable public NLB | `bool` | `false` | no |
| public_nlb_enable_deletion_protection | Enable deletion protection | `bool` | `false` | no |
| public_nlb_enable_cross_zone_load_balancing | Enable cross-zone load balancing | `bool` | `false` | no |
| public_nlb_security_group_ids | Security groups to attach | `list(string)` | `[]` | no |
| public_nlb_enable_access_logs | Enable access logs | `bool` | `false` | no |
| public_nlb_access_logs_bucket_arn | S3 bucket ARN for access logs | `string` | `null` | no |
| public_nlb_enable_elastic_ips | Enable static IPs | `bool` | `false` | no |
| public_nlb_elastic_ip_allocation_ids | Elastic IP allocation IDs | `list(string)` | `[]` | no |

### Private NLB

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| enable_private_nlb | Enable private NLB | `bool` | `false` | no |
| private_nlb_enable_deletion_protection | Enable deletion protection | `bool` | `false` | no |
| private_nlb_enable_cross_zone_load_balancing | Enable cross-zone load balancing | `bool` | `false` | no |
| private_nlb_security_group_ids | Security groups to attach | `list(string)` | `[]` | no |
| private_nlb_enable_access_logs | Enable access logs | `bool` | `false` | no |
| private_nlb_access_logs_bucket_arn | S3 bucket ARN for access logs | `string` | `null` | no |
| private_nlb_enable_elastic_ips | Enable static IPs | `bool` | `false` | no |
| private_nlb_elastic_ip_allocation_ids | Elastic IP allocation IDs | `list(string)` | `[]` | no |

## Outputs

### ECS Cluster

| Name | Description |
|------|-------------|
| cluster_id | The ID of the ECS cluster |
| cluster_arn | The ARN of the ECS cluster |
| cluster_name | The name of the ECS cluster |

### Capacity Providers

| Name | Description |
|------|-------------|
| fargate_capacity_provider_name | Fargate capacity provider name |
| fargate_spot_capacity_provider_name | Fargate Spot capacity provider name |
| ec2_capacity_provider_name | EC2 capacity provider name |
| ec2_capacity_provider_arn | EC2 capacity provider ARN |

### EC2 Infrastructure

| Name | Description |
|------|-------------|
| launch_template_id | EC2 launch template ID |
| launch_template_arn | EC2 launch template ARN |
| autoscaling_group_arn | Auto Scaling Group ARN |
| autoscaling_group_name | Auto Scaling Group name |
| ecs_instance_role_arn | IAM role ARN for EC2 instances |
| ecs_instance_role_name | IAM role name for EC2 instances |
| ecs_instance_security_group_id | Security group ID for EC2 instances |

### Public ALB

| Name | Description |
|------|-------------|
| public_alb_arn | Public ALB ARN |
| public_alb_id | Public ALB ID |
| public_alb_dns_name | Public ALB DNS name |
| public_alb_zone_id | Public ALB hosted zone ID |
| public_alb_arn_suffix | Public ALB ARN suffix |
| public_alb_security_group_id | Public ALB security group ID |
| public_alb_http_listener_arn | Public ALB HTTP listener ARN |
| public_alb_https_listener_arn | Public ALB HTTPS listener ARN |

### Private ALB

| Name | Description |
|------|-------------|
| private_alb_arn | Private ALB ARN |
| private_alb_id | Private ALB ID |
| private_alb_dns_name | Private ALB DNS name |
| private_alb_zone_id | Private ALB hosted zone ID |
| private_alb_arn_suffix | Private ALB ARN suffix |
| private_alb_security_group_id | Private ALB security group ID |
| private_alb_http_listener_arn | Private ALB HTTP listener ARN |
| private_alb_https_listener_arn | Private ALB HTTPS listener ARN |

### Public NLB

| Name | Description |
|------|-------------|
| public_nlb_arn | Public NLB ARN |
| public_nlb_id | Public NLB ID |
| public_nlb_dns_name | Public NLB DNS name |
| public_nlb_zone_id | Public NLB hosted zone ID |
| public_nlb_arn_suffix | Public NLB ARN suffix |
| public_nlb_target_group_arns | Map of target group ARNs |
| public_nlb_listener_arns | Map of listener ARNs |

### Private NLB

| Name | Description |
|------|-------------|
| private_nlb_arn | Private NLB ARN |
| private_nlb_id | Private NLB ID |
| private_nlb_dns_name | Private NLB DNS name |
| private_nlb_zone_id | Private NLB hosted zone ID |
| private_nlb_arn_suffix | Private NLB ARN suffix |
| private_nlb_target_group_arns | Map of target group ARNs |
| private_nlb_listener_arns | Map of listener ARNs |

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              ECS Cluster                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                     Capacity Providers                               │    │
│  │                                                                      │    │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────────┐  │    │
│  │  │   Fargate    │  │ Fargate Spot │  │    EC2 Capacity Provider │  │    │
│  │  │  (Optional)  │  │  (Optional)  │  │       (Optional)         │  │    │
│  │  └──────────────┘  └──────────────┘  └────────────┬─────────────┘  │    │
│  │                                                    │                │    │
│  └────────────────────────────────────────────────────│────────────────┘    │
│                                                       │                      │
│  ┌────────────────────────────────────────────────────▼────────────────────┐│
│  │                         EC2 Infrastructure                               ││
│  │                                                                          ││
│  │  ┌──────────────┐  ┌──────────────────┐  ┌────────────────────────────┐ ││
│  │  │   Launch     │  │   Auto Scaling   │  │    IAM Role & Instance     │ ││
│  │  │   Template   │──│      Group       │──│        Profile             │ ││
│  │  └──────────────┘  └──────────────────┘  └────────────────────────────┘ ││
│  └──────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────────┐│
│  │                       Load Balancers (Optional)                          ││
│  │                                                                          ││
│  │  ┌──────────────────────────────┐  ┌──────────────────────────────────┐ ││
│  │  │        Public ALB            │  │          Private ALB             │ ││
│  │  │    (Internet-facing)         │  │         (Internal)               │ ││
│  │  └──────────────────────────────┘  └──────────────────────────────────┘ ││
│  │                                                                          ││
│  │  ┌──────────────────────────────┐  ┌──────────────────────────────────┐ ││
│  │  │        Public NLB            │  │          Private NLB             │ ││
│  │  │    (Internet-facing)         │  │         (Internal)               │ ││
│  │  └──────────────────────────────┘  └──────────────────────────────────┘ ││
│  └──────────────────────────────────────────────────────────────────────────┘│
└──────────────────────────────────────────────────────────────────────────────┘
```

## Notes

- The EC2 capacity provider is only created when `ec2_instance_type` is specified
- By default, uses the latest ECS-optimized Amazon Linux 2023 AMI
- EC2 instances automatically register with the ECS cluster via user data
- IMDSv2 is enforced by default for enhanced security
- The EC2 security group automatically allows traffic from enabled ALBs
- NLBs require explicit target group and listener configuration (passthrough to the NLB module)
- NLB target groups support TCP, TLS, UDP, and TCP_UDP protocols

