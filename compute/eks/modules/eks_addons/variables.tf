################################################################################
# General
################################################################################

variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster to install add-ons on."

  validation {
    condition     = can(regex("^[0-9A-Za-z][A-Za-z0-9-_]{0,99}$", var.cluster_name))
    error_message = "The cluster_name must be 1-100 characters: start with alphanumeric, then alphanumerics, hyphens, or underscores (EKS cluster name constraints)."
  }
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to assign to all resources."
  default     = {}
}

variable "partition" {
  type        = string
  description = "AWS partition (e.g. 'aws', 'aws-us-gov') used to build managed policy ARNs. Pass this from the calling module when this module is instantiated with depends_on, so policy ARNs are known at plan time; when null, it is resolved via a data source."
  default     = null

  validation {
    condition     = var.partition == null || can(regex("^aws", var.partition))
    error_message = "The partition must be a valid AWS partition name (e.g. 'aws', 'aws-us-gov', 'aws-cn')."
  }
}

################################################################################
# Add-ons
################################################################################

variable "coredns_addon_version" {
  type        = string
  description = "Pinned version for the coredns add-on. When null, AWS resolves the most recent compatible version."
  default     = null
}

variable "coredns_addon_configuration_values" {
  type        = string
  description = "JSON string of add-on configuration overrides for coredns."
  default     = null
}

variable "ebs_csi_driver_enabled" {
  type        = bool
  description = "Install the aws-ebs-csi-driver add-on and create its Pod Identity role."
  default     = false
}

variable "ebs_csi_addon_version" {
  type        = string
  description = "Pinned version for the aws-ebs-csi-driver add-on. When null, AWS resolves the most recent compatible version."
  default     = null
}

variable "ebs_csi_addon_configuration_values" {
  type        = string
  description = "JSON string of add-on configuration overrides for aws-ebs-csi-driver."
  default     = null
}
