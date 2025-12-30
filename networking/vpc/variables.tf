################################################################################
# General
################################################################################

variable "name" {
  type        = string
  description = "Name prefix for all resources created by this module."

  validation {
    condition     = length(var.name) > 0 && length(var.name) <= 32
    error_message = "The name must be between 1 and 32 characters."
  }
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to assign to all resources."
  default     = {}
}

################################################################################
# VPC
################################################################################

variable "vpc_cidr" {
  type        = string
  description = "The IPv4 CIDR block for the VPC."
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "The vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "enable_dns_support" {
  type        = bool
  description = "Enable DNS support in the VPC."
  default     = true
}

variable "enable_dns_hostnames" {
  type        = bool
  description = "Enable DNS hostnames in the VPC."
  default     = true
}

################################################################################
# Subnets
################################################################################

variable "subnet_count" {
  type        = number
  description = "The number of public and private subnet pairs to create. Each pair is placed in a different availability zone."
  default     = 3

  validation {
    condition     = var.subnet_count >= 1 && var.subnet_count <= 6
    error_message = "The subnet_count must be between 1 and 6."
  }
}

variable "availability_zones" {
  type        = list(string)
  description = "A list of availability zones to use for subnets. If empty, AZs will be automatically selected."
  default     = []

  validation {
    condition     = length(var.availability_zones) == 0 || length(var.availability_zones) >= 1
    error_message = "If specified, availability_zones must contain at least 1 AZ."
  }
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "A list of CIDR blocks for public subnets. If null, CIDRs will be automatically calculated from the VPC CIDR."
  default     = null

  validation {
    condition     = var.public_subnet_cidrs == null || alltrue([for cidr in var.public_subnet_cidrs : can(cidrhost(cidr, 0))])
    error_message = "All public_subnet_cidrs must be valid IPv4 CIDR blocks."
  }

  validation {
    condition     = var.public_subnet_cidrs == null || length(var.public_subnet_cidrs) == var.subnet_count
    error_message = "The number of public_subnet_cidrs must equal subnet_count."
  }
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "A list of CIDR blocks for private subnets. If null, CIDRs will be automatically calculated from the VPC CIDR."
  default     = null

  validation {
    condition     = var.private_subnet_cidrs == null || alltrue([for cidr in var.private_subnet_cidrs : can(cidrhost(cidr, 0))])
    error_message = "All private_subnet_cidrs must be valid IPv4 CIDR blocks."
  }

  validation {
    condition     = var.private_subnet_cidrs == null || length(var.private_subnet_cidrs) == var.subnet_count
    error_message = "The number of private_subnet_cidrs must equal subnet_count."
  }
}

################################################################################
# NAT Gateway
################################################################################

variable "enable_nat_gateway" {
  type        = bool
  description = "Enable NAT Gateway(s) to allow private subnets to access the internet."
  default     = false
}

variable "single_nat_gateway" {
  type        = bool
  description = "Use a single NAT Gateway for all private subnets (cost-effective). Set to false for high availability (one NAT per AZ)."
  default     = true
}

################################################################################
# IPv6
################################################################################

variable "enable_ipv6" {
  type        = bool
  description = "Enable IPv6 support for the VPC. An Amazon-provided IPv6 CIDR block will be assigned."
  default     = false
}

################################################################################
# VPC Flow Logs
################################################################################

variable "enable_flow_logs" {
  type        = bool
  description = "Enable VPC Flow Logs for network traffic monitoring."
  default     = false
}

variable "flow_logs_destination" {
  type        = string
  description = "The destination for VPC Flow Logs. Valid values: 'cloudwatch' or 's3'."
  default     = "cloudwatch"

  validation {
    condition     = contains(["cloudwatch", "s3"], var.flow_logs_destination)
    error_message = "The flow_logs_destination must be either 'cloudwatch' or 's3'."
  }
}

variable "flow_logs_s3_bucket_arn" {
  type        = string
  description = "The ARN of an existing S3 bucket for VPC Flow Logs. If null and destination is 's3', a new bucket will be created."
  default     = null

  validation {
    condition     = var.flow_logs_s3_bucket_arn == null || can(regex("^arn:aws:s3:::", var.flow_logs_s3_bucket_arn))
    error_message = "The flow_logs_s3_bucket_arn must be a valid S3 bucket ARN."
  }
}

variable "flow_logs_retention_days" {
  type        = number
  description = "The number of days to retain VPC Flow Logs in CloudWatch. Only applies when flow_logs_destination is 'cloudwatch'. Set to 0 for indefinite retention."
  default     = 30

  validation {
    condition = contains([
      0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365,
      400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653
    ], var.flow_logs_retention_days)
    error_message = "The flow_logs_retention_days must be a valid CloudWatch Logs retention value."
  }
}

variable "flow_logs_traffic_type" {
  type        = string
  description = "The type of traffic to capture in VPC Flow Logs. Valid values: 'ACCEPT', 'REJECT', or 'ALL'."
  default     = "ALL"

  validation {
    condition     = contains(["ACCEPT", "REJECT", "ALL"], var.flow_logs_traffic_type)
    error_message = "The flow_logs_traffic_type must be 'ACCEPT', 'REJECT', or 'ALL'."
  }
}
