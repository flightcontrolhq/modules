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


