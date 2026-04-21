# Elastic IP pool module tests — run from module root: tofu test

mock_provider "aws" {
  override_resource {
    target = aws_eip.this
    values = {
      allocation_id = "eipalloc-00000000000000000"
      public_ip     = "203.0.113.1"
      arn           = "arn:aws:ec2:us-east-1:123456789012:elastic-ip/eipalloc-00000000000000000"
    }
  }
}

variables {
  name      = "egress-test"
  eip_count = 3
}

################################################################################
# Basic allocation
################################################################################

run "basic_allocation" {
  command = plan

  assert {
    condition     = length(aws_eip.this) == 3
    error_message = "Should allocate 3 EIPs when eip_count = 3"
  }

  assert {
    condition     = aws_eip.this[0].domain == "vpc"
    error_message = "EIPs must be allocated with domain = vpc"
  }
}

run "larger_count" {
  command = plan

  variables {
    eip_count = 6
  }

  assert {
    condition     = length(aws_eip.this) == 6
    error_message = "Should allocate 6 EIPs when eip_count = 6"
  }
}

################################################################################
# Tagging
################################################################################

run "default_tags" {
  command = plan

  assert {
    condition     = aws_eip.this[0].tags["ManagedBy"] == "terraform"
    error_message = "Default ManagedBy tag must be present"
  }

  assert {
    condition     = aws_eip.this[0].tags["Module"] == "networking/eips"
    error_message = "Default Module tag must be present"
  }
}

run "user_tags_merged" {
  command = plan

  variables {
    tags = {
      Environment = "prod"
      Owner       = "platform"
    }
  }

  assert {
    condition     = aws_eip.this[0].tags["Environment"] == "prod"
    error_message = "User tag 'Environment' must propagate"
  }

  assert {
    condition     = aws_eip.this[0].tags["Owner"] == "platform"
    error_message = "User tag 'Owner' must propagate"
  }

  assert {
    condition     = aws_eip.this[0].tags["ManagedBy"] == "terraform"
    error_message = "Default tags must remain present alongside user tags"
  }
}

run "name_tag_pattern" {
  command = plan

  variables {
    name      = "egress-prod"
    eip_count = 6
  }

  assert {
    condition     = aws_eip.this[0].tags["Name"] == "egress-prod-01"
    error_message = "First EIP Name tag should be <name>-01"
  }

  assert {
    condition     = aws_eip.this[5].tags["Name"] == "egress-prod-06"
    error_message = "Sixth EIP Name tag should be <name>-06"
  }

  assert {
    condition     = length(distinct([for e in aws_eip.this : e.tags["Name"]])) == 6
    error_message = "All EIP Name tags must be unique"
  }
}

################################################################################
# Validation failures
################################################################################

run "eip_count_zero_rejected" {
  command = plan

  variables {
    eip_count = 0
  }

  expect_failures = [
    var.eip_count,
  ]
}

run "eip_count_above_max_rejected" {
  command = plan

  variables {
    eip_count = 21
  }

  expect_failures = [
    var.eip_count,
  ]
}

run "name_too_long_rejected" {
  command = plan

  variables {
    name = "this-name-is-way-too-long-and-exceeds-the-forty-eight-char-limit"
  }

  expect_failures = [
    var.name,
  ]
}
