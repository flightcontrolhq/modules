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
    # Ravion provider: provisions the SNS topic a CloudWatch metric alarm
    # publishes to and records the notification routing (template + channel).
    ravion = {
      source  = "providers.ravion.com/ravion/ravion"
      version = ">= 0.1.0"
    }
  }
}


