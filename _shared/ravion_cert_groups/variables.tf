################################################################################
# Inputs for the shared cert-groups child module.
#
# Parent modules (compute/ecs_cluster, compute/ecs_service, future
# hosting/static_site) instantiate this with their own var.cert_groups
# and a routing-target description. The shared module owns ALL the
# allocation / cert / DNS-record / listener-rule resources.
################################################################################

variable "name" {
  type        = string
  description = "Stable prefix used in tags and listener-rule priority hashing. Pass the parent module's `var.name` so two parents in the same cluster don't collide."
}

variable "cert_groups" {
  type = list(object({
    name                  = string
    kind                  = string
    dns_provider_id       = optional(string)
    dns_provider_given_id = optional(string)
    domains               = list(string)
  }))
  description = "Operator-facing cert-group rows. Kind dispatch: `ravion_auto` nests under a cluster wildcard (no own cert); `customer` issues its own ACM cert under the row's DnsProvider."
  default     = []
}

variable "module_instance_given_id" {
  type        = string
  description = "Parent module-instance given_id. Used by `ravion_auto` groups with empty `domains` as the slug for the zero-typing auto-allocation."
  default     = null
}

variable "ravion_parent_domain_allocation_id" {
  type        = string
  description = "Cluster's parent DomainAllocation id. `ravion_auto` groups nest their allocations under this. Null = ravion_auto disabled."
  default     = null
}

variable "ravion_dns_provider_id" {
  type        = string
  description = "Cluster's DnsProvider id. Used by `ravion_auto` group allocations. Null = ravion_auto disabled (precondition fires)."
  default     = null
}

variable "routing_target_dns_name" {
  type        = string
  description = "Routing-target DNS name for customer-group routing records. ALB DNS for ECS, distribution domain for CloudFront."
  default     = null
}

variable "routing_target_zone_id" {
  type        = string
  description = "Routing-target hosted-zone id (ELBv2-provided for ALB, empty for CloudFront). Used by Route53 ALIAS routing records."
  default     = null
}

variable "listener_arn" {
  type        = string
  description = "HTTPS listener ARN to attach customer-group SNI certs to + write host-header rules on. Null when the parent has no listener (e.g. cluster-only usage with no rules)."
  default     = null
}

variable "target_group_arn" {
  type        = string
  description = "Target group ARN that host-header rules forward to. Null when there is no service to route to (e.g. cluster-level cert-only usage)."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "Extra tags merged onto every taggable resource the module creates."
  default     = {}
}
