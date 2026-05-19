################################################################################
# OpenTofu/Terraform and Provider Requirements
################################################################################

terraform {
  required_version = ">= 1.10.0"

  cloud {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    # Ravion domains provider. Only evaluated when var.cluster_parent_domain_id
    # is set — see ravion_domains.tf.
    ravion = {
      source  = "ravion.com/ravion/domains"
      version = "= 0.5.1"
    }
  }
}


