# ACM certificate module tests — run from module root: tofu test

mock_provider "aws" {
  override_resource {
    target = aws_acm_certificate.this
    values = {
      arn    = "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
      status = "PENDING_VALIDATION"
      domain_validation_options = [
        {
          domain_name           = "api.example.com"
          resource_record_name  = "_acme-challenge.api.example.com."
          resource_record_type  = "CNAME"
          resource_record_value = "_validate.acm-validations.aws."
        }
      ]
    }
  }

  override_resource {
    target = aws_route53_record.validation
    values = {
      fqdn = "_acme-challenge.api.example.com"
    }
  }

  override_resource {
    target = aws_acm_certificate_validation.this
    values = {
      id = "00000000-0000-0000-0000-000000000000"
    }
  }
}

variables {
  name    = "test-cert"
  domains = ["api.example.com"]
}

################################################################################
# Default: certificate only, CNAME outputs — no Route53, no validation wait
################################################################################

run "defaults_no_route53_no_wait" {
  command = plan

  assert {
    condition     = length(aws_route53_record.validation) == 0
    error_message = "Route53 validation records should not be created by default"
  }

  assert {
    condition     = length(aws_acm_certificate_validation.this) == 0
    error_message = "aws_acm_certificate_validation should not be created when certificate_validation_wait_enabled is false"
  }

  assert {
    condition     = aws_acm_certificate.this.validation_method == "DNS"
    error_message = "Certificate should use DNS validation"
  }
}

################################################################################
# Wait for validation only (external DNS) — validation resource present
################################################################################

run "wait_for_validation_only" {
  command = plan

  variables {
    certificate_validation_wait_enabled = true
  }

  assert {
    condition     = length(aws_acm_certificate_validation.this) == 1
    error_message = "aws_acm_certificate_validation should be created when certificate_validation_wait_enabled is true"
  }

  assert {
    condition     = length(aws_route53_record.validation) == 0
    error_message = "Route53 records should not be created when route53_validation_records_creation_enabled is false"
  }
}

################################################################################
# Route53 records + wait — both optional paths enabled
################################################################################

run "route53_and_wait" {
  command = plan

  variables {
    route53_validation_records_creation_enabled = true
    route53_zone_id                             = "Z1234567890ABC"
    certificate_validation_wait_enabled         = true
  }

  assert {
    condition     = length(aws_route53_record.validation) == 1
    error_message = "Route53 validation record should be created for the domain"
  }

  assert {
    condition     = length(aws_acm_certificate_validation.this) == 1
    error_message = "aws_acm_certificate_validation should be created when certificate_validation_wait_enabled is true"
  }
}

################################################################################
# Ordered domains (still one validation block per domain in mock)
################################################################################

run "with_multiple_domains" {
  command = plan

  variables {
    domains = ["app.example.com", "www.example.com", "*.example.com"]
  }

  assert {
    condition     = aws_acm_certificate.this.domain_name == "app.example.com"
    error_message = "The first domain should be the certificate's primary domain"
  }

  assert {
    condition = (
      length(aws_acm_certificate.this.subject_alternative_names) == 2 &&
      contains(aws_acm_certificate.this.subject_alternative_names, "www.example.com") &&
      contains(aws_acm_certificate.this.subject_alternative_names, "*.example.com")
    )
    error_message = "Domains after the first should be passed as subject alternative names"
  }
}
