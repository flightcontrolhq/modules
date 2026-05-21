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

variable "mode" {
  type        = string
  description = "Dispatch mode. `leaf` (default) = per-FQDN allocations under a parent (used by ecs_service). `parent` = ONE wildcard cert + parent allocation per group (used by ecs_cluster) for services to nest under."
  default     = "leaf"

  validation {
    condition     = contains(["leaf", "parent"], var.mode)
    error_message = "mode must be `leaf` or `parent`."
  }
}

variable "cert_groups" {
  type = list(object({
    name                  = string
    kind                  = string
    dns_provider_id       = optional(string)
    dns_provider_given_id = optional(string)
    domains               = list(string)
    wildcard_fqdn         = optional(string)
    parent_group_name    = optional(string)
  }))
  description = "Operator-facing cert-group rows. Field semantics depend on `var.mode`. Leaf mode kinds: `inherit` (leaf labels nested under a chosen cluster parent group), `customer` (per-FQDN cert under row's DnsProvider). Parent mode kinds: `ravion_auto` (auto-derived wildcard under platform apex), `customer` (wildcard at row's wildcard_fqdn)."
  default     = []
}

variable "cluster_groups" {
  type = map(object({
    parent_allocation_id = string
    managed_domain_id    = string
    wildcard_fqdn        = string
    cert_arn             = string
    dns_provider_id      = string
  }))
  description = "Upstream cluster's parent-mode output (`module.ravion_cert_groups.parent_groups` from the cluster). Leaf-mode `inherit` cert groups look up their parent here via parent_group_name. Empty for cluster-only callers."
  default     = {}
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

variable "platform_apex_provider_given_id" {
  type        = string
  description = "DnsProvider given_id of the Ravion-managed platform apex. Used by parent mode + `ravion_auto` kind to look up the apex zone the cluster wildcard is allocated under."
  default     = "ravion-platform-apex"
}

variable "module_instance_id" {
  type        = string
  description = "Parent module-instance id. Used in parent mode to derive a stable random suffix for the auto-generated wildcard FQDN slug."
  default     = null
}
