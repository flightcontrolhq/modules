################################################################################
# General
################################################################################

variable "name" {
  type        = string
  description = "Name for the target group, listener rule, and related resources."

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{0,254}$", var.name))
    error_message = "The name must be 1-255 characters: start with alphanumeric, then alphanumerics, hyphens, or underscores."
  }
}

variable "region" {
  type        = string
  description = "AWS region. When null, the provider's configured region is used."
  default     = null
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
  description = "ID of the VPC the EKS cluster runs in. The target group must live in the same VPC as the pods it registers."

  validation {
    condition     = can(regex("^vpc-", var.vpc_id))
    error_message = "The vpc_id must be a valid VPC ID starting with 'vpc-'."
  }
}

################################################################################
# Target Group
################################################################################

variable "container_port" {
  type        = number
  description = "Port the application container listens on. The chart's Service targets this port and the AWS Load Balancer Controller registers pod IPs against it."
  default     = 8080

  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535
    error_message = "The container_port must be between 1 and 65535."
  }
}

variable "target_group_protocol" {
  type        = string
  description = "Protocol the load balancer uses to reach pods."
  default     = "HTTP"

  validation {
    condition     = contains(["HTTP", "HTTPS"], var.target_group_protocol)
    error_message = "The target_group_protocol must be HTTP or HTTPS."
  }
}

variable "target_group_deregistration_delay" {
  type        = number
  description = "Seconds the load balancer waits before deregistering a target, letting in-flight requests drain."
  default     = 300

  validation {
    condition     = var.target_group_deregistration_delay >= 0 && var.target_group_deregistration_delay <= 3600
    error_message = "The target_group_deregistration_delay must be between 0 and 3600."
  }
}

variable "target_group_slow_start" {
  type        = number
  description = "Seconds over which the load balancer ramps traffic to newly registered targets. Use 0 to disable."
  default     = 0

  validation {
    condition     = var.target_group_slow_start == 0 || (var.target_group_slow_start >= 30 && var.target_group_slow_start <= 900)
    error_message = "The target_group_slow_start must be 0 (disabled) or between 30 and 900."
  }
}

variable "health_check" {
  type = object({
    enabled             = optional(bool, true)
    path                = optional(string, "/")
    port                = optional(string, "traffic-port")
    protocol            = optional(string, null)
    matcher             = optional(string, "200-399")
    interval            = optional(number, 15)
    timeout             = optional(number, 5)
    healthy_threshold   = optional(number, 2)
    unhealthy_threshold = optional(number, 2)
  })
  description = "Load balancer health check applied to the target group. Independent of the chart's Kubernetes readiness probe: this one decides whether the load balancer sends traffic to a pod."
  default     = {}

  validation {
    condition     = var.health_check.protocol == null || contains(["HTTP", "HTTPS"], coalesce(var.health_check.protocol, "HTTP"))
    error_message = "The health_check.protocol must be HTTP or HTTPS when set."
  }

  validation {
    condition     = var.health_check.timeout < var.health_check.interval
    error_message = "The health_check.timeout must be lower than health_check.interval."
  }
}

variable "stickiness" {
  type = object({
    enabled         = optional(bool, false)
    type            = optional(string, "lb_cookie")
    cookie_duration = optional(number, 86400)
    cookie_name     = optional(string, null)
  })
  description = "Target group cookie stickiness, keeping repeat requests on the same pod when possible."
  default     = {}

  validation {
    condition     = contains(["lb_cookie", "app_cookie"], var.stickiness.type)
    error_message = "The stickiness.type must be lb_cookie or app_cookie."
  }

  validation {
    condition     = !(var.stickiness.enabled && var.stickiness.type == "app_cookie") || try(length(var.stickiness.cookie_name), 0) > 0
    error_message = "The stickiness.cookie_name is required when stickiness.type is app_cookie."
  }
}

################################################################################
# Listener Rule
################################################################################

variable "listener_arn" {
  type        = string
  description = "ARN of the shared load balancer listener the rule is attached to. Comes from the EKS Add-ons module's public or private ALB."

  validation {
    condition     = can(regex("^arn:aws[a-zA-Z-]*:elasticloadbalancing:", var.listener_arn))
    error_message = "The listener_arn must be an elasticloadbalancing ARN."
  }
}

variable "listener_rule_priority" {
  type        = number
  description = "Listener rule priority. When null, AWS assigns the next available priority."
  default     = null

  validation {
    condition     = var.listener_rule_priority == null || try(var.listener_rule_priority >= 1 && var.listener_rule_priority <= 50000, false)
    error_message = "The listener_rule_priority must be between 1 and 50000."
  }
}

variable "listener_rule_conditions" {
  type = list(object({
    type   = string
    values = list(string)
  }))
  description = "Conditions that route requests to this service. Supported types: host-header, path-pattern, http-header, http-request-method, query-string, source-ip. Defaults to a catch-all /* path rule."
  default = [{
    type   = "path-pattern"
    values = ["/*"]
  }]

  validation {
    condition     = length(var.listener_rule_conditions) > 0
    error_message = "At least one listener rule condition is required."
  }

  validation {
    condition = alltrue([
      for condition in var.listener_rule_conditions :
      contains(["host-header", "path-pattern", "http-header", "http-request-method", "query-string", "source-ip"], condition.type)
    ])
    error_message = "Each listener rule condition type must be one of: host-header, path-pattern, http-header, http-request-method, query-string, source-ip."
  }

  validation {
    condition = alltrue([
      for condition in var.listener_rule_conditions : length(condition.values) > 0
    ])
    error_message = "Each listener rule condition must have at least one value."
  }
}
