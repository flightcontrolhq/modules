################################################################################
# General
################################################################################

variable "name" {
  type        = string
  description = "Name prefix for the security group. The full name will be '{name}-{name_suffix}'."

  validation {
    condition     = length(var.name) > 0 && length(var.name) <= 200
    error_message = "The name must be between 1 and 200 characters."
  }
}

variable "name_suffix" {
  type        = string
  description = "Suffix to append to the security group name (e.g., 'elasticache', 'alb', 'ecs-service')."
  default     = "sg"

  validation {
    condition     = length(var.name_suffix) > 0 && length(var.name_suffix) <= 50
    error_message = "The name_suffix must be between 1 and 50 characters."
  }
}

variable "description" {
  type        = string
  description = "Description of the security group."
  default     = "Managed by Terraform"

  validation {
    condition     = length(var.description) <= 255
    error_message = "The description must be 255 characters or less."
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
  description = "The ID of the VPC where the security group will be created."

  validation {
    condition     = can(regex("^vpc-", var.vpc_id))
    error_message = "The vpc_id must be a valid VPC ID starting with 'vpc-'."
  }
}

################################################################################
# Ingress Rules
################################################################################

variable "ingress_rules" {
  type = list(object({
    description = optional(string, "Managed by Terraform")
    from_port   = number
    to_port     = number
    ip_protocol = optional(string, "tcp")

    # Source - exactly one of these should be specified
    cidr_ipv4                    = optional(string, null)
    cidr_ipv6                    = optional(string, null)
    referenced_security_group_id = optional(string, null)
    prefix_list_id               = optional(string, null)
    self                         = optional(bool, false)
  }))
  description = <<-EOF
    List of ingress rules. Each rule must specify exactly one source type:
    - cidr_ipv4: IPv4 CIDR block (e.g., "10.0.0.0/8")
    - cidr_ipv6: IPv6 CIDR block (e.g., "::/0")
    - referenced_security_group_id: Security group ID to allow traffic from
    - prefix_list_id: Managed prefix list ID
    - self: Set to true to allow traffic from the same security group

    For ip_protocol, use "tcp", "udp", "icmp", "icmpv6", or "-1" for all protocols.
    When ip_protocol is "-1", from_port and to_port must be -1.
  EOF
  default     = []

  validation {
    condition = alltrue([
      for rule in var.ingress_rules :
      rule.from_port >= -1 && rule.from_port <= 65535
    ])
    error_message = "All from_port values must be between -1 and 65535."
  }

  validation {
    condition = alltrue([
      for rule in var.ingress_rules :
      rule.to_port >= -1 && rule.to_port <= 65535
    ])
    error_message = "All to_port values must be between -1 and 65535."
  }

  validation {
    condition = alltrue([
      for rule in var.ingress_rules :
      contains(["tcp", "udp", "icmp", "icmpv6", "-1", "all"], lower(coalesce(rule.ip_protocol, "tcp")))
    ])
    error_message = "The ip_protocol must be one of: tcp, udp, icmp, icmpv6, -1, or all."
  }

  validation {
    condition = alltrue([
      for rule in var.ingress_rules :
      rule.cidr_ipv4 == null || can(cidrhost(rule.cidr_ipv4, 0))
    ])
    error_message = "All cidr_ipv4 values must be valid IPv4 CIDR blocks."
  }

  validation {
    condition = alltrue([
      for rule in var.ingress_rules :
      rule.cidr_ipv6 == null || can(cidrhost(rule.cidr_ipv6, 0))
    ])
    error_message = "All cidr_ipv6 values must be valid IPv6 CIDR blocks."
  }

  validation {
    condition = alltrue([
      for rule in var.ingress_rules :
      rule.referenced_security_group_id == null || can(regex("^sg-", rule.referenced_security_group_id))
    ])
    error_message = "All referenced_security_group_id values must be valid security group IDs starting with 'sg-'."
  }

  validation {
    condition = alltrue([
      for rule in var.ingress_rules :
      rule.prefix_list_id == null || can(regex("^pl-", rule.prefix_list_id))
    ])
    error_message = "All prefix_list_id values must be valid prefix list IDs starting with 'pl-'."
  }

  # Ensure exactly one source type is specified
  validation {
    condition = alltrue([
      for rule in var.ingress_rules :
      (
        (rule.cidr_ipv4 != null ? 1 : 0) +
        (rule.cidr_ipv6 != null ? 1 : 0) +
        (rule.referenced_security_group_id != null ? 1 : 0) +
        (rule.prefix_list_id != null ? 1 : 0) +
        (rule.self == true ? 1 : 0)
      ) == 1
    ])
    error_message = "Each ingress rule must specify exactly one source type: cidr_ipv4, cidr_ipv6, referenced_security_group_id, prefix_list_id, or self."
  }
}

################################################################################
# Egress Rules
################################################################################

variable "egress_rules" {
  type = list(object({
    description = optional(string, "Managed by Terraform")
    from_port   = number
    to_port     = number
    ip_protocol = optional(string, "tcp")

    # Destination - exactly one of these should be specified
    cidr_ipv4                    = optional(string, null)
    cidr_ipv6                    = optional(string, null)
    referenced_security_group_id = optional(string, null)
    prefix_list_id               = optional(string, null)
    self                         = optional(bool, false)
  }))
  description = <<-EOF
    List of egress rules. Each rule must specify exactly one destination type:
    - cidr_ipv4: IPv4 CIDR block (e.g., "0.0.0.0/0")
    - cidr_ipv6: IPv6 CIDR block (e.g., "::/0")
    - referenced_security_group_id: Security group ID to allow traffic to
    - prefix_list_id: Managed prefix list ID
    - self: Set to true to allow traffic to the same security group

    For ip_protocol, use "tcp", "udp", "icmp", "icmpv6", or "-1" for all protocols.
    When ip_protocol is "-1", from_port and to_port must be -1.
  EOF
  default     = []

  validation {
    condition = alltrue([
      for rule in var.egress_rules :
      rule.from_port >= -1 && rule.from_port <= 65535
    ])
    error_message = "All from_port values must be between -1 and 65535."
  }

  validation {
    condition = alltrue([
      for rule in var.egress_rules :
      rule.to_port >= -1 && rule.to_port <= 65535
    ])
    error_message = "All to_port values must be between -1 and 65535."
  }

  validation {
    condition = alltrue([
      for rule in var.egress_rules :
      contains(["tcp", "udp", "icmp", "icmpv6", "-1", "all"], lower(coalesce(rule.ip_protocol, "tcp")))
    ])
    error_message = "The ip_protocol must be one of: tcp, udp, icmp, icmpv6, -1, or all."
  }

  validation {
    condition = alltrue([
      for rule in var.egress_rules :
      rule.cidr_ipv4 == null || can(cidrhost(rule.cidr_ipv4, 0))
    ])
    error_message = "All cidr_ipv4 values must be valid IPv4 CIDR blocks."
  }

  validation {
    condition = alltrue([
      for rule in var.egress_rules :
      rule.cidr_ipv6 == null || can(cidrhost(rule.cidr_ipv6, 0))
    ])
    error_message = "All cidr_ipv6 values must be valid IPv6 CIDR blocks."
  }

  validation {
    condition = alltrue([
      for rule in var.egress_rules :
      rule.referenced_security_group_id == null || can(regex("^sg-", rule.referenced_security_group_id))
    ])
    error_message = "All referenced_security_group_id values must be valid security group IDs starting with 'sg-'."
  }

  validation {
    condition = alltrue([
      for rule in var.egress_rules :
      rule.prefix_list_id == null || can(regex("^pl-", rule.prefix_list_id))
    ])
    error_message = "All prefix_list_id values must be valid prefix list IDs starting with 'pl-'."
  }

  # Ensure exactly one destination type is specified
  validation {
    condition = alltrue([
      for rule in var.egress_rules :
      (
        (rule.cidr_ipv4 != null ? 1 : 0) +
        (rule.cidr_ipv6 != null ? 1 : 0) +
        (rule.referenced_security_group_id != null ? 1 : 0) +
        (rule.prefix_list_id != null ? 1 : 0) +
        (rule.self == true ? 1 : 0)
      ) == 1
    ])
    error_message = "Each egress rule must specify exactly one destination type: cidr_ipv4, cidr_ipv6, referenced_security_group_id, prefix_list_id, or self."
  }
}

################################################################################
# Default Egress
################################################################################

variable "allow_all_egress" {
  type        = bool
  description = "If true, creates a default egress rule allowing all outbound traffic to 0.0.0.0/0 and ::/0. Set to false if you want to define custom egress rules only."
  default     = false
}

variable "allow_all_egress_ipv4_only" {
  type        = bool
  description = "If true and allow_all_egress is true, only creates the IPv4 egress rule (0.0.0.0/0). Useful for VPCs without IPv6."
  default     = false
}
