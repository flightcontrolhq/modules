terraform {
  required_version = ">= 1.10.0"

  cloud {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    # Ravion provider — only used when var.use_ravion_managed_domains = true.
    # Source resolution requires the runner's terraform mirror to be configured
    # (Ravion's pipeline runner injects the mirror via ~/.terraformrc).
    domains = {
      source  = "ravion.com/ravion/domains"
      version = "~> 0.1"
    }
  }
}
