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

  lifecycle {
    precondition {
      condition     = local.subnet_count >= 1
      error_message = "At least one availability zone must be available or specified to create VPC subnets."
    }

    precondition {
      condition     = local.subnet_count <= length(local.selected_availability_zones)
      error_message = "Requested ${local.subnet_count} subnet pairs but only ${length(local.selected_availability_zones)} availability zones are available or specified."
    }

    precondition {
      condition     = var.public_subnet_cidrs == null || length(var.public_subnet_cidrs) == local.subnet_count
      error_message = "The number of public_subnet_cidrs (${var.public_subnet_cidrs != null ? length(var.public_subnet_cidrs) : 0}) must match subnet_count (${local.subnet_count})."
    }

    precondition {
      condition     = var.private_subnet_cidrs == null || length(var.private_subnet_cidrs) == local.subnet_count
      error_message = "The number of private_subnet_cidrs (${var.private_subnet_cidrs != null ? length(var.private_subnet_cidrs) : 0}) must match subnet_count (${local.subnet_count})."
    }

    precondition {
      condition     = local.supplied_nat_eip_allocation_ids == null || !var.nat_gateway_enabled || length(local.supplied_nat_eip_allocation_ids) == local.nat_gateway_count
      error_message = "The number of nat_gateway_eip_allocation_ids must equal 1 for single-NAT mode, or subnet_count (${local.subnet_count}) for HA mode."
    }
  }
}
