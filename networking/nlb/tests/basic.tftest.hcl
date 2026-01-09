# Basic NLB Module Tests
# Run with: tofu test
#
# Note: This module creates only the NLB infrastructure.
# Target groups and listeners are created by service modules.

# Mock AWS provider with overridden data sources
mock_provider "aws" {
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
    target = aws_lb.this
    values = {
      arn        = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/net/test-nlb/1234567890123456"
      arn_suffix = "net/test-nlb/1234567890123456"
      dns_name   = "test-nlb-123456789.elb.us-east-1.amazonaws.com"
      zone_id    = "Z26RNL4JYFTOTI"
    }
  }

  override_resource {
    target = aws_s3_bucket.access_logs
    values = {
      arn = "arn:aws:s3:::test-nlb-access-logs-123456789012-us-east-1"
      id  = "test-nlb-access-logs-123456789012-us-east-1"
    }
  }
}

variables {
  name       = "test-nlb"
  vpc_id     = "vpc-12345678"
  subnet_ids = ["subnet-12345678", "subnet-87654321"]
}

# Test 1: Basic NLB creation
run "basic_nlb" {
  command = plan

  assert {
    condition     = aws_lb.this.internal == false
    error_message = "NLB should be internet-facing by default"
  }

  assert {
    condition     = aws_lb.this.load_balancer_type == "network"
    error_message = "NLB should be of type network"
  }

  assert {
    condition     = aws_lb.this.name == "test-nlb"
    error_message = "NLB should have the correct name"
  }
}

# Test 2: Internal NLB
run "internal_nlb" {
  command = plan

  variables {
    internal = true
  }

  assert {
    condition     = aws_lb.this.internal == true
    error_message = "NLB should be internal when internal = true"
  }
}

# Test 3: Access logs with new bucket
run "access_logs_new_bucket" {
  command = plan

  variables {
    enable_access_logs         = true
    access_logs_retention_days = 90
  }

  assert {
    condition     = length(aws_s3_bucket.access_logs) == 1
    error_message = "S3 bucket should be created for access logs"
  }

  assert {
    condition     = length(aws_s3_bucket_public_access_block.access_logs) == 1
    error_message = "S3 bucket should block public access"
  }

  assert {
    condition     = length(aws_s3_bucket_server_side_encryption_configuration.access_logs) == 1
    error_message = "S3 bucket should have encryption configured"
  }

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.access_logs) == 1
    error_message = "S3 bucket should have lifecycle configuration"
  }
}

# Test 4: Access logs with existing bucket
run "access_logs_existing_bucket" {
  command = plan

  variables {
    enable_access_logs     = true
    access_logs_bucket_arn = "arn:aws:s3:::my-existing-bucket"
  }

  assert {
    condition     = length(aws_s3_bucket.access_logs) == 0
    error_message = "S3 bucket should not be created when existing ARN provided"
  }
}

# Test 5: Access logs disabled
run "access_logs_disabled" {
  command = plan

  variables {
    enable_access_logs = false
  }

  assert {
    condition     = length(aws_s3_bucket.access_logs) == 0
    error_message = "S3 bucket should not be created when access logs disabled"
  }
}

# Test 6: Cross-zone load balancing enabled
run "cross_zone_enabled" {
  command = plan

  variables {
    enable_cross_zone_load_balancing = true
  }

  assert {
    condition     = aws_lb.this.enable_cross_zone_load_balancing == true
    error_message = "NLB should have cross-zone load balancing enabled"
  }
}

# Test 7: Cross-zone load balancing disabled (default)
run "cross_zone_disabled" {
  command = plan

  assert {
    condition     = aws_lb.this.enable_cross_zone_load_balancing == false
    error_message = "NLB should have cross-zone load balancing disabled by default"
  }
}

# Test 8: Deletion protection
run "deletion_protection" {
  command = plan

  variables {
    enable_deletion_protection = true
  }

  assert {
    condition     = aws_lb.this.enable_deletion_protection == true
    error_message = "NLB should have deletion protection enabled"
  }
}

# Test 9: Resource tagging
run "resource_tagging" {
  command = plan

  variables {
    tags = {
      Environment = "test"
      Project     = "myproject"
    }
  }

  assert {
    condition     = aws_lb.this.tags["Environment"] == "test"
    error_message = "NLB should have Environment tag"
  }

  assert {
    condition     = aws_lb.this.tags["ManagedBy"] == "terraform"
    error_message = "NLB should have default ManagedBy tag"
  }
}

# Test 10: DNS routing policy
run "dns_routing_policy" {
  command = plan

  variables {
    dns_record_client_routing_policy = "availability_zone_affinity"
  }

  assert {
    condition     = aws_lb.this.dns_record_client_routing_policy == "availability_zone_affinity"
    error_message = "NLB should have the specified DNS routing policy"
  }
}

# Test 11: Security groups
run "security_groups" {
  command = plan

  variables {
    security_group_ids = ["sg-12345678", "sg-87654321"]
  }

  assert {
    condition     = length(aws_lb.this.security_groups) == 2
    error_message = "NLB should have 2 security groups attached"
  }
}
