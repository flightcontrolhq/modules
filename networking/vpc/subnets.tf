################################################################################
# Public Subnets
################################################################################

resource "aws_subnet" "public" {
  count = var.subnet_count

  vpc_id                          = aws_vpc.this.id
  cidr_block                      = local.public_subnet_cidrs[count.index]
  availability_zone               = local.azs[count.index]
  map_public_ip_on_launch         = true
  assign_ipv6_address_on_creation = var.enable_ipv6
  ipv6_cidr_block                 = var.enable_ipv6 ? cidrsubnet(aws_vpc.this.ipv6_cidr_block, 8, count.index) : null

  tags = merge(local.tags, {
    Name = "${var.name}-public-${local.azs[count.index]}"
    Tier = "public"
  })

  lifecycle {
    precondition {
      condition     = var.subnet_count <= length(data.aws_availability_zones.available.names)
      error_message = "Requested ${var.subnet_count} subnets but only ${length(data.aws_availability_zones.available.names)} availability zones are available in this region."
    }

    precondition {
      condition     = var.public_subnet_cidrs == null || length(var.public_subnet_cidrs) == var.subnet_count
      error_message = "The number of public_subnet_cidrs (${var.public_subnet_cidrs != null ? length(var.public_subnet_cidrs) : 0}) must match subnet_count (${var.subnet_count})."
    }
  }
}

################################################################################
# Private Subnets
################################################################################

resource "aws_subnet" "private" {
  count = var.subnet_count

  vpc_id                          = aws_vpc.this.id
  cidr_block                      = local.private_subnet_cidrs[count.index]
  availability_zone               = local.azs[count.index]
  map_public_ip_on_launch         = false
  assign_ipv6_address_on_creation = var.enable_ipv6
  ipv6_cidr_block                 = var.enable_ipv6 ? cidrsubnet(aws_vpc.this.ipv6_cidr_block, 8, count.index + 10) : null

  tags = merge(local.tags, {
    Name = "${var.name}-private-${local.azs[count.index]}"
    Tier = "private"
  })

  lifecycle {
    precondition {
      condition     = var.private_subnet_cidrs == null || length(var.private_subnet_cidrs) == var.subnet_count
      error_message = "The number of private_subnet_cidrs (${var.private_subnet_cidrs != null ? length(var.private_subnet_cidrs) : 0}) must match subnet_count (${var.subnet_count})."
    }
  }
}


