terraform {
  required_version = ">= 1.10.0"

  cloud {}

  required_providers {
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}
