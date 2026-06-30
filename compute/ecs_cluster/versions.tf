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
    # NOTE: pointing at the siddharthsuresh.dev dev registry for now; switch to
    # providers.ravion.com when merging to main.
    ravion = {
      source  = "provider-cf.siddharthsuresh.dev/ravion/ravion"
      version = ">= 0.2.0"
    }
  }
}


