################################################################################
# General
################################################################################

variable "name" {
  type        = string
  description = "Name prefix for all Elastic IPs created by this module. Used as the base of the per-address Name tag (e.g. <name>-01, <name>-02, ...)."

  validation {
    condition     = length(var.name) > 0 && length(var.name) <= 48
    error_message = "The name must be between 1 and 48 characters."
  }
}

variable "eip_count" {
  type        = number
  description = "Number of Elastic IPs to allocate. AWS's default EIP quota per region is 5; values above that typically require a prior quota increase."

  validation {
    condition     = var.eip_count >= 1 && var.eip_count <= 20
    error_message = "The eip_count must be between 1 and 20. AWS's default EIP quota is 5 per region; values above that require a quota increase."
  }
}

variable "region" {
  type        = string
  description = "AWS region in which to allocate the Elastic IPs. Defaults to the region configured on the `aws` provider. Requires AWS provider v6.0 or later when set explicitly."
  default     = null

  validation {
    condition     = var.region == null || can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]+$", coalesce(var.region, "us-east-1")))
    error_message = "The region must be a valid AWS region identifier (e.g. us-east-1, eu-west-2, us-gov-west-1)."
  }
}

variable "network_border_group" {
  type        = string
  description = "The location from which the EIP is advertised. Defaults to the region's default network border group. Typically only set for regions with multiple border groups (Local Zones / Wavelength)."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "A map of additional tags to assign to every Elastic IP."
  default     = {}
}
