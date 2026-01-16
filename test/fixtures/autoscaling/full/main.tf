################################################################################
# Auto Scaling Group Full Features Fixture
#
# Comprehensive demonstration of all Auto Scaling Group module features:
# - Mixed instances policy with Spot instances
# - Warm pool for fast scaling
# - Multiple scaling policies (Target Tracking, Step)
# - Scheduled scaling actions
# - Lifecycle hooks
# - Instance refresh configuration
# - Instance maintenance policy
# - CloudWatch metrics
#
# Note: Uses min_size=0 and desired_capacity=0 to avoid launching actual
# instances during testing, reducing costs while still validating the module.
################################################################################

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "name" {
  type        = string
  description = "Name prefix for all resources."
}

variable "region" {
  type        = string
  description = "AWS region to deploy resources."
  default     = "us-east-1"
}

variable "tags" {
  type        = map(string)
  description = "Additional tags for all resources."
  default     = {}
}

locals {
  common_tags = merge(
    {
      Environment = "terratest"
      ManagedBy   = "terratest"
    },
    var.tags
  )
}

################################################################################
# Data Sources
################################################################################

# Get the latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

################################################################################
# VPC
################################################################################

module "vpc" {
  source = "../../../../networking/vpc"

  name         = var.name
  vpc_cidr     = "10.0.0.0/16"
  subnet_count = 2

  tags = local.common_tags
}

################################################################################
# Security Group
################################################################################

module "security_group" {
  source = "../../../../networking/security-groups"

  name        = var.name
  name_suffix = "asg"
  description = "Security group for Auto Scaling Group instances"
  vpc_id      = module.vpc.vpc_id

  # Allow all outbound traffic
  allow_all_egress = true

  tags = local.common_tags
}

################################################################################
# IAM Role with Instance Profile
################################################################################

module "iam_role" {
  source = "../../../../security/iam"

  name        = var.name
  description = "IAM role for Auto Scaling Group instances"
  path        = "/test/"

  # Trust EC2 service to assume this role
  trusted_services = ["ec2.amazonaws.com"]

  # Create an instance profile for EC2 instances
  create_instance_profile = true

  # Attach SSM managed policy for Session Manager access
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  ]

  tags = local.common_tags
}

################################################################################
# Auto Scaling Group - Full Configuration
################################################################################

module "autoscaling" {
  source = "../../../../compute/autoscaling"

  name = var.name

  # Core configuration
  min_size         = 0
  max_size         = 10
  desired_capacity = 0

  vpc_zone_identifier = module.vpc.private_subnet_ids

  # Timing and cooldown
  default_cooldown        = 300
  default_instance_warmup = 120

  # Health check configuration
  health_check_type         = "EC2"
  health_check_grace_period = 300

  # Capacity and scaling behavior
  capacity_rebalance   = true
  termination_policies = ["AllocationStrategy", "OldestLaunchTemplate", "OldestInstance"]

  # Launch template configuration (base template)
  create_launch_template = true
  launch_template = {
    image_id                 = data.aws_ami.amazon_linux_2023.id
    iam_instance_profile_arn = module.iam_role.instance_profile_arn
    security_group_ids       = [module.security_group.security_group_id]
    monitoring_enabled       = true

    # IMDSv2 required
    metadata_options = {
      http_endpoint               = "enabled"
      http_tokens                 = "required"
      http_put_response_hop_limit = 1
    }

    # Root volume configuration
    block_device_mappings = [
      {
        device_name = "/dev/xvda"
        ebs = {
          volume_size           = 30
          volume_type           = "gp3"
          iops                  = 3000
          throughput            = 125
          encrypted             = true
          delete_on_termination = true
        }
      }
    ]

    # T3 credit specification
    credit_specification = {
      cpu_credits = "standard"
    }

    # Tag specifications for launched instances
    tag_specifications = [
      {
        resource_type = "instance"
        tags = {
          Name = "${var.name}-instance"
        }
      },
      {
        resource_type = "volume"
        tags = {
          Name = "${var.name}-volume"
        }
      }
    ]
  }

  # Mixed instances policy for Spot + On-Demand
  mixed_instances_policy = {
    instances_distribution = {
      on_demand_allocation_strategy            = "prioritized"
      on_demand_base_capacity                  = 1
      on_demand_percentage_above_base_capacity = 25
      spot_allocation_strategy                 = "capacity-optimized"
    }

    launch_template_overrides = [
      {
        instance_type     = "t3.micro"
        weighted_capacity = 1
      },
      {
        instance_type     = "t3.small"
        weighted_capacity = 2
      },
      {
        instance_type     = "t3a.micro"
        weighted_capacity = 1
      },
      {
        instance_type     = "t3a.small"
        weighted_capacity = 2
      }
    ]
  }

  # Instance refresh configuration
  instance_refresh = {
    strategy = "Rolling"
    triggers = ["tag"]

    preferences = {
      min_healthy_percentage       = 90
      max_healthy_percentage       = 110
      instance_warmup              = 120
      skip_matching                = true
      auto_rollback                = false
      scale_in_protected_instances = "Ignore"
      standby_instances            = "Ignore"
    }
  }

  # Warm pool configuration
  warm_pool = {
    pool_state                  = "Stopped"
    min_size                    = 1
    max_group_prepared_capacity = 3

    instance_reuse_policy = {
      reuse_on_scale_in = true
    }
  }

  # Lifecycle hooks
  lifecycle_hooks = [
    {
      name                 = "launch-hook"
      lifecycle_transition = "autoscaling:EC2_INSTANCE_LAUNCHING"
      default_result       = "CONTINUE"
      heartbeat_timeout    = 300
      notification_metadata = jsonencode({
        action = "launch"
        source = "autoscaling"
      })
    },
    {
      name                 = "terminate-hook"
      lifecycle_transition = "autoscaling:EC2_INSTANCE_TERMINATING"
      default_result       = "CONTINUE"
      heartbeat_timeout    = 300
      notification_metadata = jsonencode({
        action = "terminate"
        source = "autoscaling"
      })
    }
  ]

  # Scaling policies
  scaling_policies = [
    # Target Tracking - CPU Utilization
    {
      name                      = "cpu-target-tracking"
      policy_type               = "TargetTrackingScaling"
      estimated_instance_warmup = 120

      target_tracking_configuration = {
        target_value     = 70.0
        disable_scale_in = false

        predefined_metric_specification = {
          predefined_metric_type = "ASGAverageCPUUtilization"
        }
      }
    },

    # Step Scaling - Scale Out
    {
      name                    = "memory-scale-out"
      policy_type             = "StepScaling"
      adjustment_type         = "ChangeInCapacity"
      metric_aggregation_type = "Average"

      step_adjustments = [
        {
          metric_interval_lower_bound = 0
          metric_interval_upper_bound = 10
          scaling_adjustment          = 1
        },
        {
          metric_interval_lower_bound = 10
          scaling_adjustment          = 2
        }
      ]
    }
  ]

  # Scheduled scaling
  schedules = [
    {
      name             = "workday-scale-up"
      min_size         = 2
      max_size         = 10
      desired_capacity = 4
      recurrence       = "0 8 * * MON-FRI"
      time_zone        = "America/New_York"
    },
    {
      name             = "workday-scale-down"
      min_size         = 0
      max_size         = 5
      desired_capacity = 1
      recurrence       = "0 20 * * MON-FRI"
      time_zone        = "America/New_York"
    }
  ]

  # Instance maintenance policy
  instance_maintenance_policy = {
    min_healthy_percentage = 90
    max_healthy_percentage = 120
  }

  # CloudWatch metrics - enable all
  enabled_metrics = [
    "GroupMinSize",
    "GroupMaxSize",
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupPendingInstances",
    "GroupStandbyInstances",
    "GroupTerminatingInstances",
    "GroupTotalInstances",
    "GroupInServiceCapacity",
    "GroupPendingCapacity",
    "GroupStandbyCapacity",
    "GroupTerminatingCapacity",
    "GroupTotalCapacity",
    "WarmPoolDesiredCapacity",
    "WarmPoolWarmedCapacity",
    "WarmPoolPendingCapacity",
    "WarmPoolTerminatingCapacity",
    "WarmPoolTotalCapacity",
    "GroupAndWarmPoolDesiredCapacity",
    "GroupAndWarmPoolTotalCapacity"
  ]

  tags = local.common_tags
}

################################################################################
# Outputs
################################################################################

# VPC Outputs
output "vpc_id" {
  description = "The ID of the VPC."
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "The IDs of the private subnets."
  value       = module.vpc.private_subnet_ids
}

# Security Group Outputs
output "security_group_id" {
  description = "The ID of the security group."
  value       = module.security_group.security_group_id
}

# IAM Outputs
output "instance_profile_arn" {
  description = "The ARN of the instance profile."
  value       = module.iam_role.instance_profile_arn
}

# Auto Scaling Group Outputs
output "autoscaling_group_id" {
  description = "The ID of the Auto Scaling Group."
  value       = module.autoscaling.autoscaling_group_id
}

output "autoscaling_group_arn" {
  description = "The ARN of the Auto Scaling Group."
  value       = module.autoscaling.autoscaling_group_arn
}

output "autoscaling_group_name" {
  description = "The name of the Auto Scaling Group."
  value       = module.autoscaling.autoscaling_group_name
}

output "autoscaling_group_min_size" {
  description = "The minimum size of the Auto Scaling Group."
  value       = module.autoscaling.autoscaling_group_min_size
}

output "autoscaling_group_max_size" {
  description = "The maximum size of the Auto Scaling Group."
  value       = module.autoscaling.autoscaling_group_max_size
}

output "autoscaling_group_availability_zones" {
  description = "The availability zones of the Auto Scaling Group."
  value       = module.autoscaling.autoscaling_group_availability_zones
}

output "autoscaling_group_default_cooldown" {
  description = "The default cooldown of the Auto Scaling Group."
  value       = module.autoscaling.autoscaling_group_default_cooldown
}

output "autoscaling_group_health_check_type" {
  description = "The health check type of the Auto Scaling Group."
  value       = module.autoscaling.autoscaling_group_health_check_type
}

# Launch Template Outputs
output "launch_template_id" {
  description = "The ID of the launch template."
  value       = module.autoscaling.launch_template_id
}

output "launch_template_arn" {
  description = "The ARN of the launch template."
  value       = module.autoscaling.launch_template_arn
}

output "launch_template_name" {
  description = "The name of the launch template."
  value       = module.autoscaling.launch_template_name
}

output "launch_template_latest_version" {
  description = "The latest version of the launch template."
  value       = module.autoscaling.launch_template_latest_version
}

# Warm Pool Outputs
output "warm_pool_state" {
  description = "The state of instances in the warm pool."
  value       = module.autoscaling.warm_pool_state
}

# Scaling Policy Outputs
output "scaling_policy_arns" {
  description = "Map of scaling policy names to ARNs."
  value       = module.autoscaling.scaling_policy_arns
}

# Lifecycle Hook Outputs
output "lifecycle_hook_names" {
  description = "List of lifecycle hook names."
  value       = module.autoscaling.lifecycle_hook_names
}

# Scheduled Action Outputs
output "schedule_arns" {
  description = "Map of schedule names to ARNs."
  value       = module.autoscaling.schedule_arns
}

# ECS Integration Output
output "ecs_capacity_provider_config" {
  description = "Configuration for ECS capacity provider integration."
  value       = module.autoscaling.ecs_capacity_provider_config
}
