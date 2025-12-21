# Basic VPC Module Tests
# Run with: tofu test

# Mock AWS provider with overridden data sources
mock_provider "aws" {
  override_data {
    target = data.aws_availability_zones.available
    values = {
      names = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d", "us-east-1e", "us-east-1f"]
    }
  }

  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "123456789012"
    }
  }

  override_data {
    target = data.aws_region.current
    values = {
      id   = "us-east-1"
      name = "us-east-1"
    }
  }

  # Override resources that need valid ARNs
  override_resource {
    target = aws_cloudwatch_log_group.flow_logs
    values = {
      arn = "arn:aws:logs:us-east-1:123456789012:log-group:/aws/vpc-flow-logs/test-vpc"
    }
  }

  override_resource {
    target = aws_iam_role.flow_logs
    values = {
      arn = "arn:aws:iam::123456789012:role/test-vpc-vpc-flow-logs"
    }
  }

  override_resource {
    target = aws_s3_bucket.flow_logs
    values = {
      arn = "arn:aws:s3:::test-vpc-vpc-flow-logs-123456789012-us-east-1"
    }
  }
}

variables {
  name = "test-vpc"
}

# Test 1: Basic VPC creation with defaults
run "basic_vpc" {
  command = plan

  assert {
    condition     = aws_vpc.this.cidr_block == "10.0.0.0/16"
    error_message = "VPC CIDR block should default to 10.0.0.0/16"
  }

  assert {
    condition     = aws_vpc.this.enable_dns_support == true
    error_message = "DNS support should be enabled by default"
  }

  assert {
    condition     = aws_vpc.this.enable_dns_hostnames == true
    error_message = "DNS hostnames should be enabled by default"
  }

  assert {
    condition     = length(aws_subnet.public) == 3
    error_message = "Should create 3 public subnets by default"
  }

  assert {
    condition     = length(aws_subnet.private) == 3
    error_message = "Should create 3 private subnets by default"
  }
}

# Test 2: Custom VPC CIDR
run "custom_cidr" {
  command = plan

  variables {
    vpc_cidr = "172.16.0.0/16"
  }

  assert {
    condition     = aws_vpc.this.cidr_block == "172.16.0.0/16"
    error_message = "VPC CIDR block should be 172.16.0.0/16"
  }
}

# Test 3: Custom subnet count
run "custom_subnet_count" {
  command = plan

  variables {
    subnet_count = 2
  }

  assert {
    condition     = length(aws_subnet.public) == 2
    error_message = "Should create 2 public subnets"
  }

  assert {
    condition     = length(aws_subnet.private) == 2
    error_message = "Should create 2 private subnets"
  }
}

# Test 4: NAT Gateway enabled (single)
run "nat_gateway_single" {
  command = plan

  variables {
    enable_nat_gateway = true
    single_nat_gateway = true
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 1
    error_message = "Should create 1 NAT Gateway when single_nat_gateway is true"
  }

  assert {
    condition     = length(aws_eip.nat) == 1
    error_message = "Should create 1 EIP for NAT Gateway"
  }
}

# Test 5: NAT Gateway enabled (HA - one per AZ)
run "nat_gateway_ha" {
  command = plan

  variables {
    enable_nat_gateway = true
    single_nat_gateway = false
    subnet_count       = 3
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 3
    error_message = "Should create 3 NAT Gateways when single_nat_gateway is false"
  }

  assert {
    condition     = length(aws_eip.nat) == 3
    error_message = "Should create 3 EIPs for NAT Gateways"
  }
}

# Test 6: NAT Gateway disabled
run "nat_gateway_disabled" {
  command = plan

  variables {
    enable_nat_gateway = false
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 0
    error_message = "Should not create NAT Gateway when disabled"
  }

  assert {
    condition     = length(aws_eip.nat) == 0
    error_message = "Should not create EIP when NAT Gateway disabled"
  }
}

# Test 7: IPv6 enabled
run "ipv6_enabled" {
  command = plan

  variables {
    enable_ipv6 = true
  }

  override_resource {
    target = aws_vpc.this
    values = {
      ipv6_cidr_block = "2600:1f18::/56"
    }
  }

  assert {
    condition     = aws_vpc.this.assign_generated_ipv6_cidr_block == true
    error_message = "VPC should have IPv6 CIDR block assigned"
  }

  assert {
    condition     = length(aws_egress_only_internet_gateway.this) == 1
    error_message = "Should create Egress-Only Internet Gateway for IPv6"
  }
}

# Test 8: IPv6 disabled
run "ipv6_disabled" {
  command = plan

  variables {
    enable_ipv6 = false
  }

  assert {
    condition     = aws_vpc.this.assign_generated_ipv6_cidr_block == false
    error_message = "VPC should not have IPv6 CIDR block assigned"
  }

  assert {
    condition     = length(aws_egress_only_internet_gateway.this) == 0
    error_message = "Should not create Egress-Only Internet Gateway"
  }
}

# Test 9: Flow Logs to CloudWatch - resource counts
run "flow_logs_cloudwatch" {
  command = plan

  variables {
    enable_flow_logs         = true
    flow_logs_destination    = "cloudwatch"
    flow_logs_retention_days = 30
  }

  assert {
    condition     = length(aws_flow_log.cloudwatch) == 1
    error_message = "Should create CloudWatch Flow Log"
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.flow_logs) == 1
    error_message = "Should create CloudWatch Log Group"
  }

  assert {
    condition     = length(aws_iam_role.flow_logs) == 1
    error_message = "Should create IAM Role for Flow Logs"
  }

  assert {
    condition     = length(aws_flow_log.s3) == 0
    error_message = "Should not create S3 Flow Log"
  }
}

# Test 10: Flow Logs to S3 (new bucket)
run "flow_logs_s3_new_bucket" {
  command = plan

  variables {
    enable_flow_logs      = true
    flow_logs_destination = "s3"
  }

  assert {
    condition     = length(aws_flow_log.s3) == 1
    error_message = "Should create S3 Flow Log"
  }

  assert {
    condition     = length(aws_s3_bucket.flow_logs) == 1
    error_message = "Should create S3 bucket for Flow Logs"
  }

  assert {
    condition     = length(aws_flow_log.cloudwatch) == 0
    error_message = "Should not create CloudWatch Flow Log"
  }
}

# Test 11: Flow Logs to S3 (existing bucket)
run "flow_logs_s3_existing_bucket" {
  command = plan

  variables {
    enable_flow_logs        = true
    flow_logs_destination   = "s3"
    flow_logs_s3_bucket_arn = "arn:aws:s3:::my-existing-bucket"
  }

  assert {
    condition     = length(aws_flow_log.s3) == 1
    error_message = "Should create S3 Flow Log"
  }

  assert {
    condition     = length(aws_s3_bucket.flow_logs) == 0
    error_message = "Should not create S3 bucket when existing ARN provided"
  }
}

# Test 12: Flow Logs disabled
run "flow_logs_disabled" {
  command = plan

  variables {
    enable_flow_logs = false
  }

  assert {
    condition     = length(aws_flow_log.cloudwatch) == 0
    error_message = "Should not create CloudWatch Flow Log"
  }

  assert {
    condition     = length(aws_flow_log.s3) == 0
    error_message = "Should not create S3 Flow Log"
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.flow_logs) == 0
    error_message = "Should not create CloudWatch Log Group"
  }

  assert {
    condition     = length(aws_s3_bucket.flow_logs) == 0
    error_message = "Should not create S3 bucket"
  }
}

# Test 13: Custom subnet CIDRs
run "custom_subnet_cidrs" {
  command = plan

  variables {
    subnet_count         = 2
    public_subnet_cidrs  = ["10.0.100.0/24", "10.0.101.0/24"]
    private_subnet_cidrs = ["10.0.200.0/24", "10.0.201.0/24"]
  }

  assert {
    condition     = aws_subnet.public[0].cidr_block == "10.0.100.0/24"
    error_message = "First public subnet should use custom CIDR"
  }

  assert {
    condition     = aws_subnet.private[0].cidr_block == "10.0.200.0/24"
    error_message = "First private subnet should use custom CIDR"
  }
}

# Test 14: Resource tagging
run "resource_tagging" {
  command = plan

  variables {
    tags = {
      Environment = "test"
      Project     = "myproject"
    }
  }

  assert {
    condition     = aws_vpc.this.tags["Environment"] == "test"
    error_message = "VPC should have Environment tag"
  }

  assert {
    condition     = aws_vpc.this.tags["ManagedBy"] == "terraform"
    error_message = "VPC should have default ManagedBy tag"
  }
}

# Test 15: Public subnets have correct settings
run "public_subnet_settings" {
  command = plan

  assert {
    condition     = aws_subnet.public[0].map_public_ip_on_launch == true
    error_message = "Public subnets should auto-assign public IPs"
  }

  assert {
    condition     = aws_subnet.public[0].tags["Tier"] == "public"
    error_message = "Public subnets should have Tier=public tag"
  }
}

# Test 16: Private subnets have correct settings
run "private_subnet_settings" {
  command = plan

  assert {
    condition     = aws_subnet.private[0].map_public_ip_on_launch == false
    error_message = "Private subnets should not auto-assign public IPs"
  }

  assert {
    condition     = aws_subnet.private[0].tags["Tier"] == "private"
    error_message = "Private subnets should have Tier=private tag"
  }
}

# Test 17: Route tables created correctly
run "route_tables" {
  command = plan

  variables {
    single_nat_gateway = true
  }

  assert {
    condition     = length(aws_route_table.private) == 1
    error_message = "Should create 1 private route table when single_nat_gateway is true"
  }
}

# Test 18: Multiple private route tables for HA NAT
run "route_tables_ha" {
  command = plan

  variables {
    single_nat_gateway = false
    subnet_count       = 3
  }

  assert {
    condition     = length(aws_route_table.private) == 3
    error_message = "Should create 3 private route tables when single_nat_gateway is false"
  }
}

# Test 19: DNS settings can be disabled
run "dns_disabled" {
  command = plan

  variables {
    enable_dns_support   = false
    enable_dns_hostnames = false
  }

  assert {
    condition     = aws_vpc.this.enable_dns_support == false
    error_message = "DNS support should be disabled"
  }

  assert {
    condition     = aws_vpc.this.enable_dns_hostnames == false
    error_message = "DNS hostnames should be disabled"
  }
}

# Test 20: Internet Gateway is always created
run "internet_gateway" {
  command = plan

  assert {
    condition     = aws_internet_gateway.this.vpc_id == aws_vpc.this.id
    error_message = "Internet Gateway should be attached to VPC"
  }
}

# Test 21: Public route has internet gateway
run "public_route" {
  command = plan

  assert {
    condition     = aws_route.public_internet.destination_cidr_block == "0.0.0.0/0"
    error_message = "Public route should have 0.0.0.0/0 destination"
  }

  assert {
    condition     = aws_route.public_internet.gateway_id == aws_internet_gateway.this.id
    error_message = "Public route should use Internet Gateway"
  }
}

# Test 22: Subnet count of 1
run "single_subnet" {
  command = plan

  variables {
    subnet_count = 1
  }

  assert {
    condition     = length(aws_subnet.public) == 1
    error_message = "Should create 1 public subnet"
  }

  assert {
    condition     = length(aws_subnet.private) == 1
    error_message = "Should create 1 private subnet"
  }
}

# Test 23: Maximum subnet count of 6
run "max_subnets" {
  command = plan

  variables {
    subnet_count = 6
  }

  assert {
    condition     = length(aws_subnet.public) == 6
    error_message = "Should create 6 public subnets"
  }

  assert {
    condition     = length(aws_subnet.private) == 6
    error_message = "Should create 6 private subnets"
  }
}

# Test 24: CloudWatch log retention is set correctly
run "cloudwatch_retention" {
  command = plan

  variables {
    enable_flow_logs         = true
    flow_logs_destination    = "cloudwatch"
    flow_logs_retention_days = 90
  }

  assert {
    condition     = aws_cloudwatch_log_group.flow_logs[0].retention_in_days == 90
    error_message = "CloudWatch log retention should be 90 days"
  }
}

# Test 25: S3 bucket security configurations
run "s3_security" {
  command = plan

  variables {
    enable_flow_logs      = true
    flow_logs_destination = "s3"
  }

  assert {
    condition     = length(aws_s3_bucket_server_side_encryption_configuration.flow_logs) == 1
    error_message = "S3 bucket should have encryption configuration"
  }

  assert {
    condition     = length(aws_s3_bucket_public_access_block.flow_logs) == 1
    error_message = "S3 bucket should block public access"
  }

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.flow_logs) == 1
    error_message = "S3 bucket should have lifecycle configuration"
  }
}
