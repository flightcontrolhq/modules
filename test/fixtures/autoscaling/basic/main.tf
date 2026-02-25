################################################################################
# Auto Scaling Group Basic Fixture
#
# A minimal Auto Scaling Group configuration for Terratest integration testing.
# Creates a VPC, security group, IAM instance profile, and a basic ASG with a
# launch template using the latest Amazon Linux 2023 AMI.
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
# Auto Scaling Group
################################################################################

module "autoscaling" {
  source = "../../../../compute/autoscaling"

  name = var.name

  # Use 0 instances to avoid costs during testing
  min_size         = 0
  max_size         = 2
  desired_capacity = 0

  vpc_zone_identifier = module.vpc.private_subnet_ids

  # Health check configuration
  health_check_type         = "EC2"
  health_check_grace_period = 300

  # Launch template configuration
  create_launch_template = true
  launch_template = {
    image_id                 = data.aws_ami.amazon_linux_2023.id
    instance_type            = "t3.micro"
    iam_instance_profile_arn = module.iam_role.instance_profile_arn
    security_group_ids       = [module.security_group.security_group_id]

    # IMDSv2 required by default in the module
    metadata_options = {
      http_endpoint               = "enabled"
      http_tokens                 = "required"
      http_put_response_hop_limit = 1
    }
  }

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

output "autoscaling_group_desired_capacity" {
  description = "The desired capacity of the Auto Scaling Group."
  value       = module.autoscaling.autoscaling_group_desired_capacity
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
