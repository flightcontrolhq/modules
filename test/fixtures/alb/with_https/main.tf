################################################################################
# ALB with HTTPS Fixture
#
# An ALB configuration with HTTPS listener for Terratest integration testing.
# Creates a VPC, self-signed ACM certificate, and ALB with both HTTP and HTTPS
# listeners. HTTP traffic is redirected to HTTPS.
################################################################################

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "name" {
  type        = string
  description = "Name prefix for all resources."
}

variable "region" {
  type        = string
  description = "AWS region to deploy resources."
  default     = "us-east-1"
}

variable "tags" {
  type        = map(string)
  description = "Additional tags for all resources."
  default     = {}
}

locals {
  common_tags = merge(
    {
      Environment = "terratest"
      ManagedBy   = "terratest"
    },
    var.tags
  )
  # Domain for the self-signed certificate
  domain_name = "${var.name}.terratest.local"
}

################################################################################
# VPC
################################################################################

module "vpc" {
  source = "../../../../networking/vpc"

  name         = var.name
  vpc_cidr     = "10.0.0.0/16"
  subnet_count = 2

  tags = local.common_tags
}

################################################################################
# Self-Signed TLS Certificate
################################################################################

resource "tls_private_key" "this" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "this" {
  private_key_pem = tls_private_key.this.private_key_pem

  subject {
    common_name  = local.domain_name
    organization = "Terratest"
  }

  validity_period_hours = 24

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]

  dns_names = [local.domain_name]
}

################################################################################
# ACM Certificate (imported from self-signed)
################################################################################

resource "aws_acm_certificate" "this" {
  private_key      = tls_private_key.this.private_key_pem
  certificate_body = tls_self_signed_cert.this.cert_pem

  tags = merge(local.common_tags, {
    Name = "${var.name}-cert"
  })

  lifecycle {
    create_before_destroy = true
  }
}

################################################################################
# ALB
################################################################################

module "alb" {
  source = "../../../../networking/alb"

  name       = var.name
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnet_ids

  # Enable both HTTP and HTTPS listeners
  enable_http_listener  = true
  enable_https_listener = true

  # Certificate for HTTPS
  certificate_arn = aws_acm_certificate.this.arn

  # Enable HTTP to HTTPS redirect
  http_to_https_redirect = true

  # Disable deletion protection for test cleanup
  enable_deletion_protection = false

  tags = local.common_tags
}

################################################################################
# Outputs
################################################################################

output "vpc_id" {
  description = "The ID of the VPC."
  value       = module.vpc.vpc_id
}

output "alb_arn" {
  description = "The ARN of the Application Load Balancer."
  value       = module.alb.alb_arn
}

output "alb_dns_name" {
  description = "The DNS name of the Application Load Balancer."
  value       = module.alb.alb_dns_name
}

output "security_group_id" {
  description = "The ID of the ALB security group."
  value       = module.alb.security_group_id
}

output "http_listener_arn" {
  description = "The ARN of the HTTP listener."
  value       = module.alb.http_listener_arn
}

output "https_listener_arn" {
  description = "The ARN of the HTTPS listener."
  value       = module.alb.https_listener_arn
}

output "certificate_arn" {
  description = "The ARN of the ACM certificate."
  value       = aws_acm_certificate.this.arn
}
