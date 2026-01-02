# Basic NLB Module Tests
# Run with: tofu test

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
    target = aws_lb_listener.this
    values = {
      arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/net/test-nlb/1234567890123456/1234567890123456"
      id  = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/net/test-nlb/1234567890123456/1234567890123456"
    }
  }

  override_resource {
    target = aws_lb_target_group.this
    values = {
      arn        = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/test-nlb-tg/1234567890123456"
      arn_suffix = "targetgroup/test-nlb-tg/1234567890123456"
      name       = "test-nlb-tg"
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

  target_groups = {
    web = {
      port     = 80
      protocol = "TCP"
    }
  }

  listeners = {
    http = {
      port             = 80
      protocol         = "TCP"
      target_group_key = "web"
    }
  }
}

# Test 1: Basic NLB with TCP listener
run "basic_nlb_tcp" {
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
    condition     = length(aws_lb_listener.this) == 1
    error_message = "One listener should be created"
  }

  assert {
    condition     = length(aws_lb_target_group.this) == 1
    error_message = "One target group should be created"
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

# Test 3: TLS listener with certificate
run "tls_listener" {
  command = plan

  variables {
    target_groups = {
      web = {
        port     = 8080
        protocol = "TCP"
      }
    }
    listeners = {
      https = {
        port             = 443
        protocol         = "TLS"
        target_group_key = "web"
        certificate_arn  = "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
      }
    }
  }

  assert {
    condition     = length(aws_lb_listener.this) == 1
    error_message = "TLS listener should be created"
  }

  assert {
    condition     = aws_lb_listener.this["https"].port == 443
    error_message = "TLS listener should use port 443"
  }

  assert {
    condition     = aws_lb_listener.this["https"].protocol == "TLS"
    error_message = "TLS listener should use TLS protocol"
  }
}

# Test 4: UDP listener
run "udp_listener" {
  command = plan

  variables {
    target_groups = {
      dns = {
        port     = 53
        protocol = "UDP"
      }
    }
    listeners = {
      dns = {
        port             = 53
        protocol         = "UDP"
        target_group_key = "dns"
      }
    }
  }

  assert {
    condition     = aws_lb_listener.this["dns"].port == 53
    error_message = "UDP listener should use port 53"
  }

  assert {
    condition     = aws_lb_listener.this["dns"].protocol == "UDP"
    error_message = "UDP listener should use UDP protocol"
  }

  assert {
    condition     = aws_lb_target_group.this["dns"].protocol == "UDP"
    error_message = "Target group should use UDP protocol"
  }
}

# Test 5: Multiple listeners sharing same target group
run "shared_target_group" {
  command = plan

  variables {
    target_groups = {
      web = {
        port     = 8080
        protocol = "TCP"
      }
    }
    listeners = {
      http = {
        port             = 80
        protocol         = "TCP"
        target_group_key = "web"
      }
      https = {
        port             = 443
        protocol         = "TLS"
        target_group_key = "web"
        certificate_arn  = "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
      }
      legacy = {
        port             = 8080
        protocol         = "TCP"
        target_group_key = "web"
      }
    }
  }

  assert {
    condition     = length(aws_lb_listener.this) == 3
    error_message = "Three listeners should be created"
  }

  assert {
    condition     = length(aws_lb_target_group.this) == 1
    error_message = "Only one target group should be created (shared)"
  }
}

# Test 6: Multiple target groups with separate listeners
run "multiple_target_groups" {
  command = plan

  variables {
    target_groups = {
      web = {
        port     = 8080
        protocol = "TCP"
      }
      api = {
        port     = 3000
        protocol = "TCP"
      }
    }
    listeners = {
      web = {
        port             = 80
        protocol         = "TCP"
        target_group_key = "web"
      }
      api = {
        port             = 3000
        protocol         = "TCP"
        target_group_key = "api"
      }
    }
  }

  assert {
    condition     = length(aws_lb_target_group.this) == 2
    error_message = "Two target groups should be created"
  }

  assert {
    condition     = length(aws_lb_listener.this) == 2
    error_message = "Two listeners should be created"
  }
}

# Test 7: Custom target group settings
run "custom_target_group" {
  command = plan

  variables {
    target_groups = {
      web = {
        port                   = 8080
        protocol               = "TCP"
        target_type            = "instance"
        deregistration_delay   = 60
        proxy_protocol_v2      = true
        connection_termination = true
      }
    }
    listeners = {
      http = {
        port             = 80
        protocol         = "TCP"
        target_group_key = "web"
      }
    }
  }

  assert {
    condition     = aws_lb_target_group.this["web"].target_type == "instance"
    error_message = "Target group should use instance target type"
  }

  assert {
    condition     = aws_lb_target_group.this["web"].deregistration_delay == "60"
    error_message = "Target group should have custom deregistration delay"
  }

  assert {
    condition     = aws_lb_target_group.this["web"].proxy_protocol_v2 == true
    error_message = "Target group should have Proxy Protocol v2 enabled"
  }

  assert {
    condition     = aws_lb_target_group.this["web"].connection_termination == true
    error_message = "Target group should have connection termination enabled"
  }
}

# Test 8: Health check with HTTP protocol
run "http_health_check" {
  command = plan

  variables {
    target_groups = {
      web = {
        port     = 8080
        protocol = "TCP"
        health_check = {
          protocol = "HTTP"
          path     = "/health"
          port     = "8080"
        }
      }
    }
    listeners = {
      http = {
        port             = 80
        protocol         = "TCP"
        target_group_key = "web"
      }
    }
  }

  assert {
    condition     = aws_lb_target_group.this["web"].health_check[0].protocol == "HTTP"
    error_message = "Health check should use HTTP protocol"
  }

  assert {
    condition     = aws_lb_target_group.this["web"].health_check[0].path == "/health"
    error_message = "Health check should use /health path"
  }
}

# Test 9: TLS listener with custom SSL policy
run "custom_ssl_policy" {
  command = plan

  variables {
    target_groups = {
      web = {
        port     = 8080
        protocol = "TCP"
      }
    }
    listeners = {
      https = {
        port             = 443
        protocol         = "TLS"
        target_group_key = "web"
        certificate_arn  = "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
        ssl_policy       = "ELBSecurityPolicy-TLS-1-2-2017-01"
      }
    }
  }

  assert {
    condition     = aws_lb_listener.this["https"].ssl_policy == "ELBSecurityPolicy-TLS-1-2-2017-01"
    error_message = "TLS listener should use custom SSL policy"
  }
}

# Test 10: TLS listener with additional certificates (SNI)
run "additional_certificates" {
  command = plan

  variables {
    target_groups = {
      web = {
        port     = 8080
        protocol = "TCP"
      }
    }
    listeners = {
      https = {
        port             = 443
        protocol         = "TLS"
        target_group_key = "web"
        certificate_arn  = "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
        additional_certificate_arns = [
          "arn:aws:acm:us-east-1:123456789012:certificate/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
          "arn:aws:acm:us-east-1:123456789012:certificate/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
        ]
      }
    }
  }

  assert {
    condition     = length(aws_lb_listener_certificate.additional) == 2
    error_message = "Should create 2 additional listener certificates"
  }
}

# Test 11: No listeners (empty map)
run "no_listeners" {
  command = plan

  variables {
    target_groups = {
      web = {
        port     = 8080
        protocol = "TCP"
      }
    }
    listeners = {}
  }

  assert {
    condition     = length(aws_lb_listener.this) == 0
    error_message = "No listeners should be created with empty map"
  }

  assert {
    condition     = length(aws_lb_target_group.this) == 1
    error_message = "Target group should still be created"
  }
}

# Test 12: Access logs with new bucket
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

# Test 13: Access logs with existing bucket
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

# Test 14: Access logs disabled
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

# Test 15: Cross-zone load balancing enabled
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

# Test 16: Cross-zone load balancing disabled (default)
run "cross_zone_disabled" {
  command = plan

  assert {
    condition     = aws_lb.this.enable_cross_zone_load_balancing == false
    error_message = "NLB should have cross-zone load balancing disabled by default"
  }
}

# Test 17: Deletion protection
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

# Test 18: Resource tagging
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

# Test 19: All protocols (TCP, TLS, UDP)
run "all_protocols" {
  command = plan

  variables {
    target_groups = {
      tcp_tg = {
        port     = 8080
        protocol = "TCP"
      }
      udp_tg = {
        port     = 53
        protocol = "UDP"
      }
    }
    listeners = {
      tcp = {
        port             = 80
        protocol         = "TCP"
        target_group_key = "tcp_tg"
      }
      tls = {
        port             = 443
        protocol         = "TLS"
        target_group_key = "tcp_tg"
        certificate_arn  = "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
      }
      udp = {
        port             = 53
        protocol         = "UDP"
        target_group_key = "udp_tg"
      }
    }
  }

  assert {
    condition     = length(aws_lb_listener.this) == 3
    error_message = "Three listeners should be created (TCP, TLS, UDP)"
  }

  assert {
    condition     = aws_lb_listener.this["tcp"].protocol == "TCP"
    error_message = "TCP listener should have TCP protocol"
  }

  assert {
    condition     = aws_lb_listener.this["tls"].protocol == "TLS"
    error_message = "TLS listener should have TLS protocol"
  }

  assert {
    condition     = aws_lb_listener.this["udp"].protocol == "UDP"
    error_message = "UDP listener should have UDP protocol"
  }
}

# Test 20: Default target groups and listeners
run "defaults" {
  command = plan

  variables {
    target_groups = {}
    listeners     = {}
  }

  assert {
    condition     = length(aws_lb_target_group.this) == 0
    error_message = "No target groups should be created with empty map"
  }

  assert {
    condition     = length(aws_lb_listener.this) == 0
    error_message = "No listeners should be created with empty map"
  }
}
