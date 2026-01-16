################################################################################
# Auto Scaling Group with Scaling Policies Fixture
#
# Demonstrates various scaling policy configurations including:
# - Target Tracking Scaling (CPU-based auto-scaling)
# - Step Scaling (graduated response to metric changes)
# - Scheduled Scaling (time-based capacity adjustments)
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

  # Allow all outbound traffic (no inbound for basic test)
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
# Auto Scaling Group with Scaling Policies
################################################################################

module "autoscaling" {
  source = "../../../../compute/autoscaling"

  name = var.name

  # Use 0 instances to avoid costs during testing
  min_size         = 0
  max_size         = 10
  desired_capacity = 0

  vpc_zone_identifier = module.vpc.private_subnet_ids

  # Health check configuration
  health_check_type         = "EC2"
  health_check_grace_period = 300

  # Default instance warmup for scaling policies
  default_instance_warmup = 120

  # Launch template configuration
  create_launch_template = true
  launch_template = {
    image_id                 = data.aws_ami.amazon_linux_2023.id
    instance_type            = "t3.micro"
    iam_instance_profile_arn = module.iam_role.instance_profile_arn
    security_group_ids       = [module.security_group.security_group_id]

    # IMDSv2 required
    metadata_options = {
      http_endpoint               = "enabled"
      http_tokens                 = "required"
      http_put_response_hop_limit = 1
    }
  }

  # Scaling policies configuration
  scaling_policies = [
    # Target Tracking Policy - CPU Utilization
    {
      name                      = "cpu-target-tracking"
      policy_type               = "TargetTrackingScaling"
      estimated_instance_warmup = 120

      target_tracking_configuration = {
        target_value = 70.0

        predefined_metric_specification = {
          predefined_metric_type = "ASGAverageCPUUtilization"
        }
      }
    },

    # Step Scaling Policy - Scale Out
    {
      name                    = "step-scale-out"
      policy_type             = "StepScaling"
      adjustment_type         = "ChangeInCapacity"
      metric_aggregation_type = "Average"

      step_adjustments = [
        {
          # CPU 70-80%: Add 1 instance
          metric_interval_lower_bound = 0
          metric_interval_upper_bound = 10
          scaling_adjustment          = 1
        },
        {
          # CPU 80-90%: Add 2 instances
          metric_interval_lower_bound = 10
          metric_interval_upper_bound = 20
          scaling_adjustment          = 2
        },
        {
          # CPU > 90%: Add 3 instances
          metric_interval_lower_bound = 20
          scaling_adjustment          = 3
        }
      ]
    },

    # Step Scaling Policy - Scale In
    {
      name                    = "step-scale-in"
      policy_type             = "StepScaling"
      adjustment_type         = "ChangeInCapacity"
      metric_aggregation_type = "Average"

      step_adjustments = [
        {
          # CPU 30-40%: Remove 1 instance
          metric_interval_lower_bound = -10
          metric_interval_upper_bound = 0
          scaling_adjustment          = -1
        },
        {
          # CPU < 30%: Remove 2 instances
          metric_interval_upper_bound = -10
          scaling_adjustment          = -2
        }
      ]
    }
  ]

  # Scheduled scaling actions
  schedules = [
    # Scale up on weekday mornings
    {
      name             = "scale-up-weekday-morning"
      min_size         = 2
      max_size         = 10
      desired_capacity = 4
      recurrence       = "0 9 * * MON-FRI"
      time_zone        = "America/New_York"
    },
    # Scale down on weekday evenings
    {
      name             = "scale-down-weekday-evening"
      min_size         = 0
      max_size         = 5
      desired_capacity = 1
      recurrence       = "0 18 * * MON-FRI"
      time_zone        = "America/New_York"
    },
    # Minimal capacity on weekends
    {
      name             = "weekend-minimal"
      min_size         = 0
      max_size         = 2
      desired_capacity = 0
      recurrence       = "0 0 * * SAT"
      time_zone        = "America/New_York"
    }
  ]

  # Enable CloudWatch metrics for scaling
  enabled_metrics = [
    "GroupMinSize",
    "GroupMaxSize",
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupPendingInstances",
    "GroupTerminatingInstances",
    "GroupTotalInstances",
    "GroupInServiceCapacity",
    "GroupPendingCapacity",
    "GroupTerminatingCapacity",
    "GroupTotalCapacity"
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

# Scaling Policy Outputs
output "scaling_policy_arns" {
  description = "Map of scaling policy names to ARNs."
  value       = module.autoscaling.scaling_policy_arns
}

# Scheduled Action Outputs
output "schedule_arns" {
  description = "Map of schedule names to ARNs."
  value       = module.autoscaling.schedule_arns
}
