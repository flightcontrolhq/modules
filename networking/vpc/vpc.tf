################################################################################
# VPC
################################################################################

resource "aws_vpc" "this" {
  cidr_block                       = var.vpc_cidr
  enable_dns_support               = var.dns_support_enabled
  enable_dns_hostnames             = var.dns_hostnames_enabled
  assign_generated_ipv6_cidr_block = var.ipv6_enabled

  tags = merge(local.tags, {
    Name = var.name
  })
}

