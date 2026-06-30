################################################################################
# OpenTofu/Terraform and Provider Requirements
################################################################################

terraform {
  required_version = ">= 1.10.0"

  cloud {}

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # 6.21 adds linear_configuration / canary_configuration on the
      # aws_ecs_service deployment_configuration block.
      version = ">= 6.21"
    }
    # Ravion provider: provisions the SNS topic a CloudWatch metric alarm
    # publishes to and records the notification routing (template + channel).
    ravion = {
      source  = "providers.ravion.com/ravion/ravion"
      version = ">= 0.1.0"
    }
  }
}


