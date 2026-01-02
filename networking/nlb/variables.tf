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
# Network
################################################################################

variable "vpc_id" {
  type        = string
  description = "The ID of the VPC where the NLB will be created."

  validation {
    condition     = can(regex("^vpc-", var.vpc_id))
    error_message = "The vpc_id must be a valid VPC ID starting with 'vpc-'."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "A list of subnet IDs for the NLB. Use public subnets for internet-facing NLBs."

  validation {
    condition     = length(var.subnet_ids) >= 1
    error_message = "At least 1 subnet ID is required."
  }

  validation {
    condition     = alltrue([for s in var.subnet_ids : can(regex("^subnet-", s))])
    error_message = "All subnet_ids must be valid subnet IDs starting with 'subnet-'."
  }
}

variable "security_group_ids" {
  type        = list(string)
  description = "A list of security group IDs to attach to the NLB. Only valid for NLBs in a VPC."
  default     = []

  validation {
    condition     = alltrue([for sg in var.security_group_ids : can(regex("^sg-", sg))])
    error_message = "All security_group_ids must be valid security group IDs starting with 'sg-'."
  }
}

################################################################################
# NLB Settings
################################################################################

variable "internal" {
  type        = bool
  description = "If true, the NLB will be internal (not internet-facing)."
  default     = false
}

variable "enable_deletion_protection" {
  type        = bool
  description = "Enable deletion protection on the NLB."
  default     = false
}

variable "enable_cross_zone_load_balancing" {
  type        = bool
  description = "Enable cross-zone load balancing. Distributes traffic evenly across all targets in all enabled Availability Zones."
  default     = false
}

variable "dns_record_client_routing_policy" {
  type        = string
  description = "How traffic is distributed among NLB AZs. Use 'any_availability_zone' to route to any healthy AZ, or 'availability_zone_affinity' to prefer the client's AZ."
  default     = null

  validation {
    condition     = var.dns_record_client_routing_policy == null || contains(["any_availability_zone", "availability_zone_affinity", "partial_availability_zone_affinity"], var.dns_record_client_routing_policy)
    error_message = "The dns_record_client_routing_policy must be 'any_availability_zone', 'availability_zone_affinity', or 'partial_availability_zone_affinity'."
  }
}

variable "enforce_security_group_inbound_rules_on_private_link_traffic" {
  type        = string
  description = "Whether inbound security group rules are enforced for traffic from PrivateLink."
  default     = null

  validation {
    condition     = var.enforce_security_group_inbound_rules_on_private_link_traffic == null || contains(["on", "off"], var.enforce_security_group_inbound_rules_on_private_link_traffic)
    error_message = "The enforce_security_group_inbound_rules_on_private_link_traffic must be 'on' or 'off'."
  }
}

################################################################################
# Elastic IPs (Static IPs)
################################################################################

variable "enable_elastic_ips" {
  type        = bool
  description = "Enable static IP addresses for the NLB using Elastic IPs. When enabled, elastic_ip_allocation_ids must be provided."
  default     = false
}

variable "elastic_ip_allocation_ids" {
  type        = list(string)
  description = "A list of Elastic IP allocation IDs for the NLB, one per subnet. Required if enable_elastic_ips is true."
  default     = []

  validation {
    condition     = alltrue([for eip in var.elastic_ip_allocation_ids : can(regex("^eipalloc-", eip))])
    error_message = "All elastic_ip_allocation_ids must be valid Elastic IP allocation IDs starting with 'eipalloc-'."
  }
}

################################################################################
# Target Groups
################################################################################

variable "target_groups" {
  type = map(object({
    port                   = number
    protocol               = optional(string, "TCP") # TCP, TLS, UDP, TCP_UDP
    target_type            = optional(string, "ip")  # ip, instance, alb
    deregistration_delay   = optional(number, 300)
    preserve_client_ip     = optional(bool, true)
    proxy_protocol_v2      = optional(bool, false)
    connection_termination = optional(bool, false)
    health_check = optional(object({
      enabled             = optional(bool, true)
      protocol            = optional(string, "TCP") # TCP, HTTP, HTTPS
      port                = optional(string, "traffic-port")
      path                = optional(string, null)
      matcher             = optional(string, null)
      healthy_threshold   = optional(number, 3)
      unhealthy_threshold = optional(number, 3)
      interval            = optional(number, 30)
      timeout             = optional(number, null)
    }), {})
  }))
  description = "Map of target groups to create. Each key becomes the target group name suffix."
  default = {
    default = {
      port     = 80
      protocol = "TCP"
    }
  }

  validation {
    condition = alltrue([
      for k, v in var.target_groups : contains(["TCP", "TLS", "UDP", "TCP_UDP"], v.protocol)
    ])
    error_message = "Target group protocol must be one of: TCP, TLS, UDP, TCP_UDP."
  }

  validation {
    condition = alltrue([
      for k, v in var.target_groups : contains(["ip", "instance", "alb"], v.target_type)
    ])
    error_message = "Target group target_type must be one of: ip, instance, alb."
  }

  validation {
    condition = alltrue([
      for k, v in var.target_groups : v.port >= 1 && v.port <= 65535
    ])
    error_message = "Target group port must be between 1 and 65535."
  }
}

################################################################################
# Listeners
################################################################################

variable "listeners" {
  type = map(object({
    port             = number
    protocol         = string # Required: TCP, TLS, UDP, TCP_UDP (explicit, no default)
    target_group_key = string # References key in target_groups
    # TLS-specific (only used when protocol = "TLS")
    certificate_arn             = optional(string, null)
    ssl_policy                  = optional(string, "ELBSecurityPolicy-TLS13-1-2-2021-06")
    alpn_policy                 = optional(string, null)
    additional_certificate_arns = optional(list(string), [])
  }))
  description = "Map of listeners to create. Each references a target group by key. Protocol is required and must be explicit."
  default     = {}

  validation {
    condition = alltrue([
      for k, v in var.listeners : contains(["TCP", "TLS", "UDP", "TCP_UDP"], v.protocol)
    ])
    error_message = "Listener protocol must be one of: TCP, TLS, UDP, TCP_UDP."
  }

  validation {
    condition = alltrue([
      for k, v in var.listeners : v.protocol != "TLS" || v.certificate_arn != null
    ])
    error_message = "certificate_arn is required for TLS protocol listeners."
  }

  validation {
    condition = alltrue([
      for k, v in var.listeners : v.port >= 1 && v.port <= 65535
    ])
    error_message = "Listener port must be between 1 and 65535."
  }

  validation {
    condition = alltrue([
      for k, v in var.listeners :
      v.certificate_arn == null || can(regex("^arn:aws:acm:", v.certificate_arn))
    ])
    error_message = "certificate_arn must be a valid ACM certificate ARN."
  }

  validation {
    condition = alltrue([
      for k, v in var.listeners :
      v.alpn_policy == null || contains(["HTTP1Only", "HTTP2Only", "HTTP2Optional", "HTTP2Preferred", "None"], v.alpn_policy)
    ])
    error_message = "alpn_policy must be one of: HTTP1Only, HTTP2Only, HTTP2Optional, HTTP2Preferred, None."
  }

  validation {
    condition = alltrue([
      for k, v in var.listeners :
      alltrue([for arn in v.additional_certificate_arns : can(regex("^arn:aws:acm:", arn))])
    ])
    error_message = "All additional_certificate_arns must be valid ACM certificate ARNs."
  }
}

################################################################################
# Access Logs
################################################################################

variable "enable_access_logs" {
  type        = bool
  description = "Enable access logging for the NLB."
  default     = false
}

variable "access_logs_bucket_arn" {
  type        = string
  description = "The ARN of an existing S3 bucket for access logs. If null and access logs are enabled, a new bucket will be created."
  default     = null

  validation {
    condition     = var.access_logs_bucket_arn == null || can(regex("^arn:aws:s3:::", var.access_logs_bucket_arn))
    error_message = "The access_logs_bucket_arn must be a valid S3 bucket ARN."
  }
}

variable "access_logs_prefix" {
  type        = string
  description = "The S3 prefix for access logs."
  default     = ""
}

variable "access_logs_retention_days" {
  type        = number
  description = "The number of days to retain access logs in S3."
  default     = 90

  validation {
    condition     = var.access_logs_retention_days >= 1
    error_message = "The access_logs_retention_days must be at least 1."
  }
}

variable "access_logs_kms_key_id" {
  type        = string
  description = "KMS key ID for S3 bucket encryption. If null, uses AES256 (SSE-S3)."
  default     = null

  validation {
    condition     = var.access_logs_kms_key_id == null || can(regex("^(arn:aws:kms:|alias/)", var.access_logs_kms_key_id))
    error_message = "The access_logs_kms_key_id must be a valid KMS key ARN or alias."
  }
}

variable "access_logs_versioning_enabled" {
  type        = bool
  description = "Enable versioning for the access logs S3 bucket."
  default     = false
}
