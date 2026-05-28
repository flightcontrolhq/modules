terraform {
  required_version = ">= 1.10.0"

  cloud {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    ravion = {
      source  = "provider-cf.siddharthsuresh.dev/ravion/ravion"
      version = ">= 0.1.0"
    }
  }
}
