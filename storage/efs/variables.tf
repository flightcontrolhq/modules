################################################################################
# General
################################################################################

variable "name" {
  type        = string
  description = "Name prefix for all EFS resources. Also used as the file system creation token."

  validation {
    condition     = can(regex("^[a-zA-Z0-9]([a-zA-Z0-9_-]{0,62}[a-zA-Z0-9])?$", var.name))
    error_message = "The name must be 1-64 characters, contain only letters, numbers, hyphens, and underscores, and start and end with a letter or number."
  }
}

variable "region" {
  type        = string
  description = "The AWS region where resources are created. If null, the provider's default region is used."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "Additional tags to apply to all resources."
  default     = {}
}

################################################################################
# Networking
################################################################################

variable "vpc_id" {
  type        = string
  description = "The ID of the VPC where the mount targets and security groups are created."

  validation {
    condition     = can(regex("^vpc-", var.vpc_id))
    error_message = "The vpc_id must start with vpc-."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs where mount targets are created, one per subnet. Use private subnets in distinct availability zones."

  validation {
    condition     = length(var.subnet_ids) > 0
    error_message = "At least one subnet ID is required."
  }
}

################################################################################
# File System
################################################################################

variable "encrypted" {
  type        = bool
  description = "Enable encryption at rest for the file system."
  default     = true
}

variable "kms_key_id" {
  type        = string
  description = "KMS key ARN for encryption at rest. If null, the AWS managed key for EFS is used."
  default     = null
}

variable "performance_mode" {
  type        = string
  description = "File system performance mode. generalPurpose fits most workloads; maxIO trades latency for higher aggregate throughput and cannot be changed later."
  default     = "generalPurpose"

  validation {
    condition     = contains(["generalPurpose", "maxIO"], var.performance_mode)
    error_message = "The performance_mode must be generalPurpose or maxIO."
  }
}

variable "throughput_mode" {
  type        = string
  description = "File system throughput mode: bursting, elastic, or provisioned."
  default     = "bursting"

  validation {
    condition     = contains(["bursting", "elastic", "provisioned"], var.throughput_mode)
    error_message = "The throughput_mode must be bursting, elastic, or provisioned."
  }
}

variable "provisioned_throughput_in_mibps" {
  type        = number
  description = "Provisioned throughput in MiB/s. Required when throughput_mode is provisioned."
  default     = null

  validation {
    condition     = var.throughput_mode != "provisioned" || (var.provisioned_throughput_in_mibps != null && var.provisioned_throughput_in_mibps > 0)
    error_message = "The provisioned_throughput_in_mibps must be a positive number when throughput_mode is provisioned."
  }
}

################################################################################
# Lifecycle Management
################################################################################

variable "transition_to_ia" {
  type        = string
  description = "Lifecycle policy that moves files not accessed for the given period to the Infrequent Access storage class. If null, files stay in Standard storage."
  default     = null

  validation {
    condition     = var.transition_to_ia == null || contains(["AFTER_1_DAY", "AFTER_7_DAYS", "AFTER_14_DAYS", "AFTER_30_DAYS", "AFTER_60_DAYS", "AFTER_90_DAYS", "AFTER_180_DAYS", "AFTER_270_DAYS", "AFTER_365_DAYS"], var.transition_to_ia)
    error_message = "The transition_to_ia must be one of AFTER_1_DAY, AFTER_7_DAYS, AFTER_14_DAYS, AFTER_30_DAYS, AFTER_60_DAYS, AFTER_90_DAYS, AFTER_180_DAYS, AFTER_270_DAYS, or AFTER_365_DAYS."
  }
}

variable "transition_to_archive" {
  type        = string
  description = "Lifecycle policy that moves files not accessed for the given period to the Archive storage class. Requires the Infrequent Access transition to also be set."
  default     = null

  validation {
    condition     = var.transition_to_archive == null || contains(["AFTER_1_DAY", "AFTER_7_DAYS", "AFTER_14_DAYS", "AFTER_30_DAYS", "AFTER_60_DAYS", "AFTER_90_DAYS", "AFTER_180_DAYS", "AFTER_270_DAYS", "AFTER_365_DAYS"], var.transition_to_archive)
    error_message = "The transition_to_archive must be one of AFTER_1_DAY, AFTER_7_DAYS, AFTER_14_DAYS, AFTER_30_DAYS, AFTER_60_DAYS, AFTER_90_DAYS, AFTER_180_DAYS, AFTER_270_DAYS, or AFTER_365_DAYS."
  }

  validation {
    condition     = var.transition_to_archive == null || var.transition_to_ia != null
    error_message = "The transition_to_archive requires transition_to_ia to also be set."
  }
}

variable "transition_to_primary_storage_class" {
  type        = string
  description = "Lifecycle policy that moves files back to Standard storage on first access. Only AFTER_1_ACCESS is supported by AWS."
  default     = null

  validation {
    condition     = var.transition_to_primary_storage_class == null || var.transition_to_primary_storage_class == "AFTER_1_ACCESS"
    error_message = "The transition_to_primary_storage_class must be AFTER_1_ACCESS."
  }
}

################################################################################
# Backup
################################################################################

variable "backup_enabled" {
  type        = bool
  description = "Enable automatic backups through AWS Backup."
  default     = true
}

################################################################################
# Access Point
################################################################################

variable "access_point_enabled" {
  type        = bool
  description = "Create an EFS access point that scopes clients to a directory with fixed POSIX ownership."
  default     = false
}

variable "access_point_root_directory_path" {
  type        = string
  description = "Root directory path exposed through the access point. EFS creates the directory on first use when the path is not /."
  default     = "/data"

  validation {
    condition     = can(regex("^/", var.access_point_root_directory_path))
    error_message = "The access_point_root_directory_path must be an absolute path."
  }
}

variable "access_point_posix_uid" {
  type        = number
  description = "POSIX user ID applied to all file system requests through the access point, and owner of the created root directory."
  default     = 1000
}

variable "access_point_posix_gid" {
  type        = number
  description = "POSIX group ID applied to all file system requests through the access point, and owner of the created root directory."
  default     = 1000
}

variable "access_point_permissions" {
  type        = string
  description = "POSIX permissions applied to the access point root directory when EFS creates it, as an octal string."
  default     = "755"

  validation {
    condition     = can(regex("^[0-7]{3,4}$", var.access_point_permissions))
    error_message = "The access_point_permissions must be a 3- or 4-digit octal string such as 755."
  }
}

################################################################################
# Security
################################################################################

variable "allowed_security_group_ids" {
  type        = list(string)
  description = "Additional security groups allowed to reach the mount targets over NFS, beyond the managed client security group."
  default     = []

  validation {
    condition     = alltrue([for sg_id in var.allowed_security_group_ids : can(regex("^sg-", sg_id))])
    error_message = "All allowed_security_group_ids must start with sg-."
  }
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "IPv4 CIDR blocks allowed to reach the mount targets over NFS."
  default     = []
}

variable "allowed_ipv6_cidr_blocks" {
  type        = list(string)
  description = "IPv6 CIDR blocks allowed to reach the mount targets over NFS."
  default     = []
}
