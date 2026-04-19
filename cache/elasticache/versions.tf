terraform {
  # Secrets Manager submodule uses write-only arguments — requires
  # Terraform 1.11+ / OpenTofu 1.11+ and AWS provider 5.83+.
  required_version = ">= 1.11.0"

  cloud {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.83"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
    }
  }
}
