################################################################################
# Data Sources
################################################################################

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

################################################################################
# Local Values
################################################################################

locals {
  # Tags
  default_tags = {
    ManagedBy = "terraform"
    Module    = "networking/vpc"
  }
  tags = merge(local.default_tags, var.tags)

  # Availability Zones
  azs = length(var.availability_zones) > 0 ? var.availability_zones : slice(data.aws_availability_zones.available.names, 0, var.subnet_count)

  # Subnet CIDRs - auto-calculate if not provided
  # Public subnets: /24 blocks at offset 1, 2, 3, ... (e.g., 10.0.1.0/24, 10.0.2.0/24, 10.0.3.0/24)
  # Private subnets: /24 blocks at offset 11, 12, 13, ... (e.g., 10.0.11.0/24, 10.0.12.0/24, 10.0.13.0/24)
  public_subnet_cidrs = var.public_subnet_cidrs != null ? var.public_subnet_cidrs : [
    for i in range(var.subnet_count) : cidrsubnet(var.vpc_cidr, 8, i + 1)
  ]
  private_subnet_cidrs = var.private_subnet_cidrs != null ? var.private_subnet_cidrs : [
    for i in range(var.subnet_count) : cidrsubnet(var.vpc_cidr, 8, i + 11)
  ]

  # NAT Gateway count
  nat_gateway_count = var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : var.subnet_count) : 0

  # Flow Logs
  create_flow_log_cloudwatch = var.enable_flow_logs && var.flow_logs_destination == "cloudwatch"
  create_flow_log_s3         = var.enable_flow_logs && var.flow_logs_destination == "s3"
  create_flow_log_s3_bucket  = local.create_flow_log_s3 && var.flow_logs_s3_bucket_arn == null
  flow_log_s3_bucket_arn     = local.create_flow_log_s3_bucket ? aws_s3_bucket.flow_logs[0].arn : var.flow_logs_s3_bucket_arn
}

################################################################################
# VPC
################################################################################

resource "aws_vpc" "this" {
  cidr_block                       = var.vpc_cidr
  enable_dns_support               = var.enable_dns_support
  enable_dns_hostnames             = var.enable_dns_hostnames
  assign_generated_ipv6_cidr_block = var.enable_ipv6

  tags = merge(local.tags, {
    Name = var.name
  })
}

################################################################################
# Internet Gateway
################################################################################

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, {
    Name = "${var.name}-igw"
  })
}

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

################################################################################
# Public Route Table
################################################################################

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, {
    Name = "${var.name}-public"
  })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route" "public_internet_ipv6" {
  count = var.enable_ipv6 ? 1 : 0

  route_table_id              = aws_route_table.public.id
  destination_ipv6_cidr_block = "::/0"
  gateway_id                  = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count = var.subnet_count

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

################################################################################
# Private Route Tables
################################################################################

# When using a single NAT gateway, we only need one private route table
# When using multiple NAT gateways (one per AZ), we need one route table per AZ
resource "aws_route_table" "private" {
  count = var.single_nat_gateway ? 1 : var.subnet_count

  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, {
    Name = var.single_nat_gateway ? "${var.name}-private" : "${var.name}-private-${local.azs[count.index]}"
  })
}

resource "aws_route_table_association" "private" {
  count = var.subnet_count

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = var.single_nat_gateway ? aws_route_table.private[0].id : aws_route_table.private[count.index].id
}

################################################################################
# NAT Gateway
################################################################################

resource "aws_eip" "nat" {
  count = local.nat_gateway_count

  domain = "vpc"

  tags = merge(local.tags, {
    Name = var.single_nat_gateway ? "${var.name}-nat" : "${var.name}-nat-${local.azs[count.index]}"
  })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  count = local.nat_gateway_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(local.tags, {
    Name = var.single_nat_gateway ? "${var.name}-nat" : "${var.name}-nat-${local.azs[count.index]}"
  })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route" "private_nat" {
  count = local.nat_gateway_count

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[count.index].id
}

################################################################################
# IPv6 Egress-Only Internet Gateway
################################################################################

resource "aws_egress_only_internet_gateway" "this" {
  count = var.enable_ipv6 ? 1 : 0

  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, {
    Name = "${var.name}-eigw"
  })
}

resource "aws_route" "private_ipv6_egress" {
  count = var.enable_ipv6 ? (var.single_nat_gateway ? 1 : var.subnet_count) : 0

  route_table_id              = aws_route_table.private[count.index].id
  destination_ipv6_cidr_block = "::/0"
  egress_only_gateway_id      = aws_egress_only_internet_gateway.this[0].id
}

################################################################################
# VPC Flow Logs - CloudWatch
################################################################################

resource "aws_cloudwatch_log_group" "flow_logs" {
  count = local.create_flow_log_cloudwatch ? 1 : 0

  name              = "/aws/vpc-flow-logs/${var.name}"
  retention_in_days = var.flow_logs_retention_days == 0 ? null : var.flow_logs_retention_days

  tags = merge(local.tags, {
    Name = "${var.name}-flow-logs"
  })
}

resource "aws_iam_role" "flow_logs" {
  count = local.create_flow_log_cloudwatch ? 1 : 0

  name = "${var.name}-vpc-flow-logs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.tags, {
    Name = "${var.name}-vpc-flow-logs"
  })
}

resource "aws_iam_role_policy" "flow_logs" {
  count = local.create_flow_log_cloudwatch ? 1 : 0

  name = "${var.name}-vpc-flow-logs"
  role = aws_iam_role.flow_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Effect   = "Allow"
        Resource = "${aws_cloudwatch_log_group.flow_logs[0].arn}:*"
      }
    ]
  })
}

resource "aws_flow_log" "cloudwatch" {
  count = local.create_flow_log_cloudwatch ? 1 : 0

  vpc_id                   = aws_vpc.this.id
  traffic_type             = var.flow_logs_traffic_type
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.flow_logs[0].arn
  iam_role_arn             = aws_iam_role.flow_logs[0].arn
  max_aggregation_interval = 60

  tags = merge(local.tags, {
    Name = "${var.name}-flow-log"
  })
}

################################################################################
# VPC Flow Logs - S3
################################################################################

resource "aws_s3_bucket" "flow_logs" {
  count = local.create_flow_log_s3_bucket ? 1 : 0

  bucket = "${var.name}-vpc-flow-logs-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.id}"

  tags = merge(local.tags, {
    Name = "${var.name}-vpc-flow-logs"
  })
}

resource "aws_s3_bucket_public_access_block" "flow_logs" {
  count = local.create_flow_log_s3_bucket ? 1 : 0

  bucket = aws_s3_bucket.flow_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "flow_logs" {
  count = local.create_flow_log_s3_bucket ? 1 : 0

  bucket = aws_s3_bucket.flow_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "flow_logs" {
  count = local.create_flow_log_s3_bucket ? 1 : 0

  bucket = aws_s3_bucket.flow_logs[0].id

  rule {
    id     = "flow-logs-retention"
    status = "Enabled"

    expiration {
      days = var.flow_logs_retention_days == 0 ? 365 : var.flow_logs_retention_days
    }
  }
}

resource "aws_s3_bucket_policy" "flow_logs" {
  count = local.create_flow_log_s3_bucket ? 1 : 0

  bucket = aws_s3_bucket.flow_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSLogDeliveryAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.flow_logs[0].arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
          ArnLike = {
            "aws:SourceArn" = "arn:aws:logs:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:*"
          }
        }
      },
      {
        Sid    = "AWSLogDeliveryWrite"
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.flow_logs[0].arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"      = "bucket-owner-full-control"
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
          ArnLike = {
            "aws:SourceArn" = "arn:aws:logs:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:*"
          }
        }
      }
    ]
  })
}

resource "aws_flow_log" "s3" {
  count = local.create_flow_log_s3 ? 1 : 0

  vpc_id                   = aws_vpc.this.id
  traffic_type             = var.flow_logs_traffic_type
  log_destination_type     = "s3"
  log_destination          = local.flow_log_s3_bucket_arn
  max_aggregation_interval = 60

  tags = merge(local.tags, {
    Name = "${var.name}-flow-log"
  })

  depends_on = [aws_s3_bucket_policy.flow_logs]
}
