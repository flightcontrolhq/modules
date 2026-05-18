################################################################################
# General
################################################################################

variable "name" {
  type        = string
  description = "Name prefix for all resources created by this module."

  validation {
    condition     = length(var.name) > 0 && length(var.name) <= 28
    error_message = "The name must be between 1 and 28 characters. This limit ensures ALB names (name + '-pub'/'-priv' suffix) do not exceed the 32 character AWS limit."
  }
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to assign to all resources."
  default     = {}
}

variable "deletion_protection" {
  type        = bool
  description = "If true, the resource cannot be deleted via the AWS API until this is set to false. Applied to all load balancers (public/private ALB and NLB) created by this module. Safe-by-default."
  default     = true
}

################################################################################
# Network
################################################################################

variable "vpc_id" {
  type        = string
  description = "The ID of the VPC where ECS resources will be created."

  validation {
    condition     = can(regex("^vpc-", var.vpc_id))
    error_message = "The vpc_id must be a valid VPC ID starting with 'vpc-'."
  }
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "A list of private subnet IDs for ECS tasks and internal ALB."

  validation {
    condition     = length(var.private_subnet_ids) >= 1
    error_message = "At least 1 private subnet ID is required."
  }

  validation {
    condition     = alltrue([for s in var.private_subnet_ids : can(regex("^subnet-", s))])
    error_message = "All private_subnet_ids must be valid subnet IDs starting with 'subnet-'."
  }

  validation {
    condition     = !var.enable_private_alb || length(var.private_subnet_ids) >= 2
    error_message = "At least 2 private_subnet_ids are required when enable_private_alb is true. ALBs require subnets in at least 2 availability zones for high availability."
  }
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "A list of public subnet IDs for the public ALB/NLB. Required if enable_public_alb or enable_public_nlb is true."
  default     = []

  validation {
    condition     = alltrue([for s in var.public_subnet_ids : can(regex("^subnet-", s))])
    error_message = "All public_subnet_ids must be valid subnet IDs starting with 'subnet-'."
  }

  validation {
    condition     = !var.enable_public_alb || length(var.public_subnet_ids) >= 2
    error_message = "At least 2 public_subnet_ids are required when enable_public_alb is true. ALBs require subnets in at least 2 availability zones for high availability."
  }

  validation {
    condition     = !var.enable_public_nlb || length(var.public_subnet_ids) >= 1
    error_message = "At least 1 public_subnet_id is required when enable_public_nlb is true."
  }
}

################################################################################
# ECS Cluster
################################################################################

variable "enable_container_insights" {
  type        = bool
  description = "Enable CloudWatch Container Insights for the ECS cluster."
  default     = true
}

################################################################################
# Fargate Capacity Provider
################################################################################

variable "enable_fargate" {
  type        = bool
  description = "Enable the Fargate capacity provider."
  default     = true
}

variable "fargate_weight" {
  type        = number
  description = "The relative weight of the Fargate capacity provider in the default strategy."
  default     = 1

  validation {
    condition     = var.fargate_weight >= 0 && var.fargate_weight <= 1000
    error_message = "The fargate_weight must be between 0 and 1000."
  }
}

variable "fargate_base" {
  type        = number
  description = "The base number of tasks to run on Fargate before considering weights."
  default     = 0

  validation {
    condition     = var.fargate_base >= 0 && var.fargate_base <= 100000
    error_message = "The fargate_base must be between 0 and 100000."
  }
}

################################################################################
# Fargate Spot Capacity Provider
################################################################################

variable "enable_fargate_spot" {
  type        = bool
  description = "Enable the Fargate Spot capacity provider."
  default     = false
}

variable "fargate_spot_weight" {
  type        = number
  description = "The relative weight of the Fargate Spot capacity provider in the default strategy."
  default     = 1

  validation {
    condition     = var.fargate_spot_weight >= 0 && var.fargate_spot_weight <= 1000
    error_message = "The fargate_spot_weight must be between 0 and 1000."
  }
}

variable "fargate_spot_base" {
  type        = number
  description = "The base number of tasks to run on Fargate Spot before considering weights."
  default     = 0

  validation {
    condition     = var.fargate_spot_base >= 0 && var.fargate_spot_base <= 100000
    error_message = "The fargate_spot_base must be between 0 and 100000."
  }
}

################################################################################
# EC2 Capacity Provider
################################################################################

variable "ec2_instance_type" {
  type        = string
  description = "The EC2 instance type for the ECS cluster. Set to null to disable EC2 capacity provider."
  default     = null
}

variable "ec2_ami_id" {
  type        = string
  description = "The AMI ID for EC2 instances. If null, the latest ECS-optimized AMI will be used."
  default     = null

  validation {
    condition     = try(var.ec2_ami_id == null || can(regex("^ami-", var.ec2_ami_id)), true)
    error_message = "The ec2_ami_id must be a valid AMI ID starting with 'ami-'."
  }
}

variable "ec2_key_name" {
  type        = string
  description = "The name of the EC2 key pair for SSH access to instances."
  default     = null
}

variable "ec2_min_size" {
  type        = number
  description = "The minimum number of EC2 instances in the Auto Scaling Group."
  default     = 0

  validation {
    condition     = var.ec2_min_size >= 0
    error_message = "The ec2_min_size must be 0 or greater."
  }
}

variable "ec2_max_size" {
  type        = number
  description = "The maximum number of EC2 instances in the Auto Scaling Group."
  default     = 10

  validation {
    condition     = var.ec2_max_size >= 1
    error_message = "The ec2_max_size must be at least 1."
  }
}

variable "ec2_desired_capacity" {
  type        = number
  description = "The desired number of EC2 instances in the Auto Scaling Group."
  default     = 1

  validation {
    condition     = var.ec2_desired_capacity >= 0
    error_message = "The ec2_desired_capacity must be 0 or greater."
  }
}

variable "ec2_enable_spot" {
  type        = bool
  description = "Enable Spot instances in the EC2 Auto Scaling Group using mixed instances policy."
  default     = false
}

variable "ec2_spot_instance_types" {
  type        = list(string)
  description = "Additional instance types for Spot instances. Used when ec2_enable_spot is true."
  default     = []
}

variable "ec2_on_demand_base_capacity" {
  type        = number
  description = "The minimum number of On-Demand instances in the ASG. Used when ec2_enable_spot is true."
  default     = 0

  validation {
    condition     = var.ec2_on_demand_base_capacity >= 0
    error_message = "The ec2_on_demand_base_capacity must be 0 or greater."
  }
}

variable "ec2_on_demand_percentage_above_base" {
  type        = number
  description = "Percentage of On-Demand instances above base capacity. Used when ec2_enable_spot is true."
  default     = 0

  validation {
    condition     = var.ec2_on_demand_percentage_above_base >= 0 && var.ec2_on_demand_percentage_above_base <= 100
    error_message = "The ec2_on_demand_percentage_above_base must be between 0 and 100."
  }
}

variable "ec2_root_volume_size" {
  type        = number
  description = "The size of the root EBS volume in GB for EC2 instances."
  default     = 30

  validation {
    condition     = var.ec2_root_volume_size >= 8 && var.ec2_root_volume_size <= 16384
    error_message = "The ec2_root_volume_size must be between 8 and 16384 GB."
  }
}

variable "ec2_root_volume_type" {
  type        = string
  description = "The type of the root EBS volume for EC2 instances."
  default     = "gp3"

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2"], var.ec2_root_volume_type)
    error_message = "The ec2_root_volume_type must be 'gp2', 'gp3', 'io1', or 'io2'."
  }
}

variable "ec2_user_data" {
  type        = string
  description = "Additional user data script to run on EC2 instances (appended after ECS config)."
  default     = ""
}

variable "ec2_enable_imdsv2" {
  type        = bool
  description = "Require IMDSv2 for EC2 instance metadata. Recommended for security."
  default     = true
}

variable "ec2_weight" {
  type        = number
  description = "The relative weight of the EC2 capacity provider in the default strategy."
  default     = 1

  validation {
    condition     = var.ec2_weight >= 0 && var.ec2_weight <= 1000
    error_message = "The ec2_weight must be between 0 and 1000."
  }
}

variable "ec2_base" {
  type        = number
  description = "The base number of tasks to run on EC2 before considering weights."
  default     = 0

  validation {
    condition     = var.ec2_base >= 0 && var.ec2_base <= 100000
    error_message = "The ec2_base must be between 0 and 100000."
  }
}

variable "ec2_managed_termination_protection" {
  type        = string
  description = "Managed termination protection for the EC2 capacity provider."
  default     = "ENABLED"

  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.ec2_managed_termination_protection)
    error_message = "The ec2_managed_termination_protection must be 'ENABLED' or 'DISABLED'."
  }
}

variable "ec2_managed_scaling_status" {
  type        = string
  description = "Enable or disable managed scaling for the EC2 capacity provider."
  default     = "ENABLED"

  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.ec2_managed_scaling_status)
    error_message = "The ec2_managed_scaling_status must be 'ENABLED' or 'DISABLED'."
  }
}

variable "ec2_managed_scaling_target_capacity" {
  type        = number
  description = "Target capacity percentage for managed scaling (1-100)."
  default     = 100

  validation {
    condition     = var.ec2_managed_scaling_target_capacity >= 1 && var.ec2_managed_scaling_target_capacity <= 100
    error_message = "The ec2_managed_scaling_target_capacity must be between 1 and 100."
  }
}

variable "ec2_security_group_ids" {
  type        = list(string)
  description = "Additional security group IDs to attach to EC2 instances."
  default     = []

  validation {
    condition     = alltrue([for sg in var.ec2_security_group_ids : can(regex("^sg-", sg))])
    error_message = "All ec2_security_group_ids must be valid security group IDs starting with 'sg-'."
  }
}

################################################################################
# Public ALB
################################################################################

variable "enable_public_alb" {
  type        = bool
  description = "Enable a public (internet-facing) Application Load Balancer."
  default     = false
}

variable "public_alb_enable_https" {
  type        = bool
  description = "Enable HTTPS listener on the public ALB."
  default     = false
}

variable "public_alb_certificate_arns" {
  type        = list(string)
  description = "ACM certificate ARNs for the public ALB HTTPS listener. The first ARN is used as the default certificate; the rest are attached for SNI."
  default     = []

  validation {
    condition     = alltrue([for arn in var.public_alb_certificate_arns : can(regex("^arn:aws:acm:", arn))])
    error_message = "All public_alb_certificate_arns must be valid ACM certificate ARNs."
  }
}

variable "public_alb_ssl_policy" {
  type        = string
  description = "The SSL policy for the public ALB HTTPS listener."
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "public_alb_idle_timeout" {
  type        = number
  description = "The idle timeout for the public ALB in seconds."
  default     = 60

  validation {
    condition     = var.public_alb_idle_timeout >= 1 && var.public_alb_idle_timeout <= 4000
    error_message = "The public_alb_idle_timeout must be between 1 and 4000 seconds."
  }
}

variable "public_alb_ingress_cidr_blocks" {
  type        = list(string)
  description = "IPv4 CIDR blocks allowed to access the public ALB."
  default     = ["0.0.0.0/0"]

  validation {
    condition     = alltrue([for cidr in var.public_alb_ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "All public_alb_ingress_cidr_blocks must be valid IPv4 CIDR blocks."
  }
}

variable "public_alb_enable_access_logs" {
  type        = bool
  description = "Enable access logging for the public ALB."
  default     = false
}

variable "public_alb_access_logs_bucket_arn" {
  type        = string
  description = "The ARN of an existing S3 bucket for public ALB access logs."
  default     = null

  validation {
    condition     = try(var.public_alb_access_logs_bucket_arn == null || can(regex("^arn:aws:s3:::", var.public_alb_access_logs_bucket_arn)), true)
    error_message = "The public_alb_access_logs_bucket_arn must be a valid S3 bucket ARN."
  }
}

variable "public_alb_web_acl_arn" {
  type        = string
  description = "The ARN of a WAFv2 Web ACL to associate with the public ALB."
  default     = null

  validation {
    condition     = try(var.public_alb_web_acl_arn == null || can(regex("^arn:aws:wafv2:", var.public_alb_web_acl_arn)), true)
    error_message = "The public_alb_web_acl_arn must be a valid WAFv2 Web ACL ARN."
  }
}

################################################################################
# Private ALB
################################################################################

variable "enable_private_alb" {
  type        = bool
  description = "Enable a private (internal) Application Load Balancer."
  default     = false
}

variable "private_alb_enable_https" {
  type        = bool
  description = "Enable HTTPS listener on the private ALB."
  default     = false
}

variable "private_alb_certificate_arns" {
  type        = list(string)
  description = "ACM certificate ARNs for the private ALB HTTPS listener. The first ARN is used as the default certificate; the rest are attached for SNI."
  default     = []

  validation {
    condition     = alltrue([for arn in var.private_alb_certificate_arns : can(regex("^arn:aws:acm:", arn))])
    error_message = "All private_alb_certificate_arns must be valid ACM certificate ARNs."
  }
}

variable "private_alb_ssl_policy" {
  type        = string
  description = "The SSL policy for the private ALB HTTPS listener."
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "private_alb_idle_timeout" {
  type        = number
  description = "The idle timeout for the private ALB in seconds."
  default     = 60

  validation {
    condition     = var.private_alb_idle_timeout >= 1 && var.private_alb_idle_timeout <= 4000
    error_message = "The private_alb_idle_timeout must be between 1 and 4000 seconds."
  }
}

variable "private_alb_ingress_cidr_blocks" {
  type        = list(string)
  description = "IPv4 CIDR blocks allowed to access the private ALB."
  default     = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]

  validation {
    condition     = alltrue([for cidr in var.private_alb_ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "All private_alb_ingress_cidr_blocks must be valid IPv4 CIDR blocks."
  }
}

variable "private_alb_enable_access_logs" {
  type        = bool
  description = "Enable access logging for the private ALB."
  default     = false
}

variable "private_alb_access_logs_bucket_arn" {
  type        = string
  description = "The ARN of an existing S3 bucket for private ALB access logs."
  default     = null

  validation {
    condition     = try(var.private_alb_access_logs_bucket_arn == null || can(regex("^arn:aws:s3:::", var.private_alb_access_logs_bucket_arn)), true)
    error_message = "The private_alb_access_logs_bucket_arn must be a valid S3 bucket ARN."
  }
}

################################################################################
# Public NLB
################################################################################

variable "enable_public_nlb" {
  type        = bool
  description = "Enable a public (internet-facing) Network Load Balancer."
  default     = false
}

variable "public_nlb_enable_cross_zone_load_balancing" {
  type        = bool
  description = "Enable cross-zone load balancing for the public NLB."
  default     = false
}

variable "public_nlb_security_group_ids" {
  type        = list(string)
  description = "A list of security group IDs to attach to the public NLB."
  default     = []

  validation {
    condition     = alltrue([for sg in var.public_nlb_security_group_ids : can(regex("^sg-", sg))])
    error_message = "All public_nlb_security_group_ids must be valid security group IDs starting with 'sg-'."
  }
}

variable "public_nlb_enable_access_logs" {
  type        = bool
  description = "Enable access logging for the public NLB."
  default     = false
}

variable "public_nlb_access_logs_bucket_arn" {
  type        = string
  description = "The ARN of an existing S3 bucket for public NLB access logs."
  default     = null

  validation {
    condition     = try(var.public_nlb_access_logs_bucket_arn == null || can(regex("^arn:aws:s3:::", var.public_nlb_access_logs_bucket_arn)), true)
    error_message = "The public_nlb_access_logs_bucket_arn must be a valid S3 bucket ARN."
  }
}

variable "public_nlb_enable_elastic_ips" {
  type        = bool
  description = "Enable static IP addresses for the public NLB using Elastic IPs."
  default     = false
}

variable "public_nlb_elastic_ip_allocation_ids" {
  type        = list(string)
  description = "A list of Elastic IP allocation IDs for the public NLB, one per subnet."
  default     = []

  validation {
    condition     = alltrue([for eip in var.public_nlb_elastic_ip_allocation_ids : can(regex("^eipalloc-", eip))])
    error_message = "All public_nlb_elastic_ip_allocation_ids must be valid Elastic IP allocation IDs starting with 'eipalloc-'."
  }
}

################################################################################
# Private NLB
################################################################################

variable "enable_private_nlb" {
  type        = bool
  description = "Enable a private (internal) Network Load Balancer."
  default     = false
}

variable "private_nlb_enable_cross_zone_load_balancing" {
  type        = bool
  description = "Enable cross-zone load balancing for the private NLB."
  default     = false
}

variable "private_nlb_security_group_ids" {
  type        = list(string)
  description = "A list of security group IDs to attach to the private NLB."
  default     = []

  validation {
    condition     = alltrue([for sg in var.private_nlb_security_group_ids : can(regex("^sg-", sg))])
    error_message = "All private_nlb_security_group_ids must be valid security group IDs starting with 'sg-'."
  }
}

variable "private_nlb_enable_access_logs" {
  type        = bool
  description = "Enable access logging for the private NLB."
  default     = false
}

variable "private_nlb_access_logs_bucket_arn" {
  type        = string
  description = "The ARN of an existing S3 bucket for private NLB access logs."
  default     = null

  validation {
    condition     = try(var.private_nlb_access_logs_bucket_arn == null || can(regex("^arn:aws:s3:::", var.private_nlb_access_logs_bucket_arn)), true)
    error_message = "The private_nlb_access_logs_bucket_arn must be a valid S3 bucket ARN."
  }
}

variable "private_nlb_enable_elastic_ips" {
  type        = bool
  description = "Enable static IP addresses for the private NLB using Elastic IPs."
  default     = false
}

variable "private_nlb_elastic_ip_allocation_ids" {
  type        = list(string)
  description = "A list of Elastic IP allocation IDs for the private NLB, one per subnet."
  default     = []

  validation {
    condition     = alltrue([for eip in var.private_nlb_elastic_ip_allocation_ids : can(regex("^eipalloc-", eip))])
    error_message = "All private_nlb_elastic_ip_allocation_ids must be valid Elastic IP allocation IDs starting with 'eipalloc-'."
  }
}

variable "region" {
  type        = string
  description = "AWS region. When null, the provider's configured region is used."
  default     = null
}

################################################################################
# Ravion-managed domains (optional)
################################################################################
# Single toggle that flips both the public and private ALBs into Ravion-managed
# HTTPS mode. When on:
#   - public/private ALB modules get use_ravion_managed_domains = true
#   - their HTTPS listeners use a Ravion-issued cluster wildcard cert as default
#   - HTTP-to-HTTPS redirect is forced on
#   - public_alb_certificate_arns / private_alb_certificate_arns index 0 are
#     ignored (additional ARNs still attach as SNI)
# Per-service domains are wired separately via the ECS service module's
# `domains` input — those certs attach as SNI on top of the cluster cert.

variable "use_ravion_managed_domains" {
  type        = bool
  description = "Toggle Ravion-managed default cert + auto-domain on the public AND private ALBs created by this module."
  default     = false
}

variable "ravion_aws_account_id" {
  type        = string
  description = "Ravion AwsAccount id (aws_xxx) that owns the cluster cert + Route53 records. Required when use_ravion_managed_domains is true."
  default     = null

  validation {
    condition     = try(var.ravion_aws_account_id == null || can(regex("^aws_[a-z0-9]+$", var.ravion_aws_account_id)), true)
    error_message = "The ravion_aws_account_id must be a Ravion AWS account id (e.g. aws_abc123)."
  }
}

variable "ravion_aws_region" {
  type        = string
  description = "AWS region the Ravion provider should use. Defaults to var.region when null."
  default     = null
}

variable "ravion_custom_domains" {
  type        = list(string)
  description = "Optional cluster-level custom domains issued at apply time. Per-service custom domains belong on the ECS service module's `domains` input instead — that path is non-blocking on customer DNS."
  default     = []
}
