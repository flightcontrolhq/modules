# Cluster ALB HTTPS listener tests (sprint #1: unify the HTTPS listener so
# toggling use_ravion_managed_domains is an in-place cert swap, not a
# destroy+create). Self-contained: mocks both providers, EC2 disabled
# throughout so these runs are independent of the EC2 capacity-provider tests.
# Run with: tofu test

# Valid ARNs are required: aws_lb_listener validates load_balancer_arn /
# certificate_arn at plan, and the auto-fabricated mock values aren't ARNs.
mock_provider "aws" {
  override_resource {
    target = module.public_alb.aws_lb.this
    values = {
      arn        = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/test-public-alb/1234567890123456"
      arn_suffix = "app/test-public-alb/1234567890123456"
      dns_name   = "test-public-alb-123456789.us-east-1.elb.amazonaws.com"
      zone_id    = "Z35SXDOTRQ7X7K"
    }
  }

  override_resource {
    target = module.public_alb.aws_security_group.this
    values = {
      arn = "arn:aws:ec2:us-east-1:123456789012:security-group/sg-publicalb123456"
      id  = "sg-publicalb123456"
    }
  }

  override_resource {
    target = aws_lb_listener.public_https
    values = {
      arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/test-public-alb/1234567890123456/6543210987654321"
    }
  }

  override_resource {
    target = module.private_alb.aws_lb.this
    values = {
      arn        = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/test-private-alb/1234567890123457"
      arn_suffix = "app/test-private-alb/1234567890123457"
      dns_name   = "test-private-alb-123456789.us-east-1.elb.amazonaws.com"
      zone_id    = "Z35SXDOTRQ7X7K"
    }
  }

  override_resource {
    target = module.private_alb.aws_security_group.this
    values = {
      arn = "arn:aws:ec2:us-east-1:123456789012:security-group/sg-privatealb123456"
      id  = "sg-privatealb123456"
    }
  }

  override_resource {
    target = aws_lb_listener.private_https
    values = {
      arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/test-private-alb/1234567890123457/6543210987654322"
    }
  }
}

# ravion_certificate needs a DomainProvider JWT to configure against the real
# control plane; mock it so tests are hermetic. The cert_arn override is a valid
# ACM ARN so the listener's certificate_arn passes provider validation.
mock_provider "ravion" {
  override_resource {
    target = ravion_certificate.cluster
    values = {
      id       = "cert_test"
      cert_arn = "arn:aws:acm:us-east-1:123456789012:certificate/99999999-9999-9999-9999-999999999999"
      fqdn     = "*.test-cluster-abcd.ravion.app"
      status   = "ISSUED"
    }
  }
}

variables {
  name               = "test-cluster"
  vpc_id             = "vpc-12345678"
  private_subnet_ids = ["subnet-private1", "subnet-private2"]
  public_subnet_ids  = ["subnet-public1", "subnet-public2"]
}

################################################################################
# BYO certificate mode (use_ravion_managed_domains = false, the default)
################################################################################

# A single cert ARN: ecs_cluster owns the HTTPS listener at a stable root
# address, the alb submodule owns none, and there are no SNI certs.
run "byo_public_https_single_cert" {
  command = plan

  variables {
    enable_public_alb           = true
    public_alb_enable_https     = true
    public_alb_certificate_arns = ["arn:aws:acm:us-east-1:111122223333:certificate/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"]
  }

  assert {
    condition     = length(aws_lb_listener.public_https) == 1
    error_message = "ecs_cluster must own the public HTTPS listener"
  }

  assert {
    condition     = module.public_alb[0].https_listener_arn == null
    error_message = "The alb submodule must NOT own the HTTPS listener (its https_listener_arn output is null)"
  }

  assert {
    condition     = aws_lb_listener.public_https[0].certificate_arn == "arn:aws:acm:us-east-1:111122223333:certificate/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    error_message = "BYO mode must use the customer's first cert ARN as the default cert"
  }

  assert {
    condition     = length(aws_lb_listener_certificate.public_sni) == 0
    error_message = "A single cert ARN yields no SNI certificates"
  }
}

# Multiple cert ARNs: the 2nd+ are attached for SNI.
run "byo_public_https_sni" {
  command = plan

  variables {
    enable_public_alb       = true
    public_alb_enable_https = true
    public_alb_certificate_arns = [
      "arn:aws:acm:us-east-1:111122223333:certificate/11111111-1111-1111-1111-111111111111",
      "arn:aws:acm:us-east-1:111122223333:certificate/22222222-2222-2222-2222-222222222222",
      "arn:aws:acm:us-east-1:111122223333:certificate/33333333-3333-3333-3333-333333333333",
    ]
  }

  assert {
    condition     = length(aws_lb_listener_certificate.public_sni) == 2
    error_message = "The 2nd+ cert ARNs must be attached as SNI certificates"
  }
}

# HTTPS enabled in BYO mode with no cert ARN must fail the precondition (the
# clean error, not a cryptic index-out-of-range).
run "byo_public_https_requires_cert" {
  command = plan

  variables {
    enable_public_alb       = true
    public_alb_enable_https = true
    # no public_alb_certificate_arns; use_ravion_managed_domains defaults false
  }

  expect_failures = [aws_lb_listener.public_https]
}

# Private ALB BYO parity.
run "byo_private_https_single_cert" {
  command = plan

  variables {
    enable_private_alb           = true
    private_alb_enable_https     = true
    private_alb_certificate_arns = ["arn:aws:acm:us-east-1:111122223333:certificate/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"]
  }

  assert {
    condition     = length(aws_lb_listener.private_https) == 1
    error_message = "ecs_cluster must own the private HTTPS listener"
  }

  assert {
    condition     = module.private_alb[0].https_listener_arn == null
    error_message = "The alb submodule must NOT own the private HTTPS listener (its https_listener_arn output is null)"
  }
}

# Private multi-cert: the 2nd+ are attached for SNI.
run "byo_private_https_sni" {
  command = plan

  variables {
    enable_private_alb       = true
    private_alb_enable_https = true
    private_alb_certificate_arns = [
      "arn:aws:acm:us-east-1:111122223333:certificate/44444444-4444-4444-4444-444444444444",
      "arn:aws:acm:us-east-1:111122223333:certificate/55555555-5555-5555-5555-555555555555",
    ]
  }

  assert {
    condition     = length(aws_lb_listener_certificate.private_sni) == 1
    error_message = "The 2nd+ private cert ARNs must be attached as SNI certificates"
  }
}

# Private HTTPS in BYO mode with no cert ARN must fail the precondition.
run "byo_private_https_requires_cert" {
  command = plan

  variables {
    enable_private_alb       = true
    private_alb_enable_https = true
    # no private_alb_certificate_arns; use_ravion_managed_domains defaults false
  }

  expect_failures = [aws_lb_listener.private_https]
}

################################################################################
# Ravion-managed mode (use_ravion_managed_domains = true)
################################################################################

# The wildcard cert is issued and becomes the listener default; no SNI certs,
# no customer cert ARN required. Same listener address as BYO mode (the
# toggle is an in-place cert swap, not a destroy+create).
run "ravion_managed_public_https" {
  command = plan

  variables {
    enable_public_alb          = true
    public_alb_enable_https    = true
    use_ravion_managed_domains = true
    ravion_aws_account_id      = "aws_testaccount"
  }

  assert {
    condition     = length(ravion_certificate.cluster) == 1
    error_message = "Ravion wildcard cert must be created in managed mode"
  }

  assert {
    condition     = length(aws_lb_listener.public_https) == 1
    error_message = "The HTTPS listener exists at the same address in managed mode"
  }

  assert {
    condition     = length(aws_lb_listener_certificate.public_sni) == 0
    error_message = "Managed mode attaches no customer SNI certs"
  }
}

################################################################################
# HTTP-only: no HTTPS listener, and the SNI slice is never evaluated
################################################################################

# Regression guard for the slice([], 1, 0) crash: with HTTPS off and no certs,
# the SNI for_each must short-circuit to an empty set rather than evaluating
# the slice.
run "public_alb_http_only_no_sni_eval" {
  command = plan

  variables {
    enable_public_alb       = true
    public_alb_enable_https = false
  }

  assert {
    condition     = length(aws_lb_listener.public_https) == 0
    error_message = "No HTTPS listener when public_alb_enable_https = false"
  }

  assert {
    condition     = length(aws_lb_listener_certificate.public_sni) == 0
    error_message = "SNI set must be empty (slice not evaluated) when HTTPS is off"
  }
}
