# Route53 module tests — run from module root: tofu test

mock_provider "aws" {
  override_resource {
    target = aws_route53_zone.public
    values = {
      zone_id             = "Z1PUBLIC0000000000"
      arn                 = "arn:aws:route53:::hostedzone/Z1PUBLIC0000000000"
      name_servers        = ["ns-1.awsdns-01.com", "ns-2.awsdns-02.net", "ns-3.awsdns-03.org", "ns-4.awsdns-04.co.uk"]
      primary_name_server = "ns-1.awsdns-01.com"
    }
  }

  override_resource {
    target = aws_route53_zone.private
    values = {
      zone_id             = "Z1PRIVATE000000000"
      arn                 = "arn:aws:route53:::hostedzone/Z1PRIVATE000000000"
      name_servers        = []
      primary_name_server = "ns-internal.aws"
    }
  }

  override_data {
    target = data.aws_route53_zone.existing
    values = {
      name                = "existing.example.com."
      name_servers        = ["ns-1.awsdns-01.com"]
      primary_name_server = "ns-1.awsdns-01.com"
    }
  }

  override_resource {
    target = aws_route53_record.this
    values = {
      fqdn = "record.example.com"
      id   = "Z1PUBLIC0000000000_record.example.com_A"
    }
  }

  override_resource {
    target = aws_route53_key_signing_key.this
    values = {
      id        = "example.com-ksk"
      ds_record = "12345 13 2 ABCDEF1234567890"
    }
  }
}

################################################################################
# Defaults: public zone only, no records
################################################################################

run "defaults_public_zone" {
  command = plan

  variables {
    name = "example.com"
  }

  assert {
    condition     = length(aws_route53_zone.public) == 1
    error_message = "A public hosted zone should be created by default"
  }

  assert {
    condition     = length(aws_route53_zone.private) == 0
    error_message = "A private hosted zone should not be created by default"
  }

  assert {
    condition     = length(aws_route53_record.this) == 0
    error_message = "No records should be created when none are specified"
  }

  assert {
    condition     = length(aws_route53_query_log.this) == 0
    error_message = "Query logging should be disabled by default"
  }

  assert {
    condition     = length(aws_route53_key_signing_key.this) == 0
    error_message = "DNSSEC should be disabled by default"
  }
}

################################################################################
# Private zone with VPC associations
################################################################################

run "private_zone_with_vpcs" {
  command = plan

  variables {
    name         = "internal.example.com"
    private_zone = true
    vpc_associations = {
      primary = {
        vpc_id     = "vpc-12345678"
        vpc_region = "us-east-1"
      }
    }
  }

  assert {
    condition     = length(aws_route53_zone.public) == 0
    error_message = "No public zone should be created for a private zone"
  }

  assert {
    condition     = length(aws_route53_zone.private) == 1
    error_message = "A private hosted zone should be created"
  }
}

################################################################################
# Reference existing zone — manage records only
################################################################################

run "existing_zone_with_records" {
  command = plan

  variables {
    create_zone = false
    zone_id     = "Z1EXISTING00000000"
    records = {
      www = {
        name    = "www.existing.example.com"
        type    = "A"
        ttl     = 300
        records = ["192.0.2.1"]
      }
      txt = {
        name    = "existing.example.com"
        type    = "TXT"
        ttl     = 300
        records = ["v=spf1 -all"]
      }
    }
  }

  assert {
    condition     = length(aws_route53_zone.public) == 0
    error_message = "No zone should be created when create_zone = false"
  }

  assert {
    condition     = length(aws_route53_record.this) == 2
    error_message = "Two records should be created"
  }
}

################################################################################
# Alias record to ALB
################################################################################

run "alias_record" {
  command = plan

  variables {
    name = "example.com"
    records = {
      apex = {
        name = "example.com"
        type = "A"
        alias = {
          name                   = "dualstack.my-alb-1234.us-east-1.elb.amazonaws.com"
          zone_id                = "Z35SXDOTRQ7X7K"
          evaluate_target_health = true
        }
      }
    }
  }

  assert {
    condition     = length(aws_route53_record.this) == 1
    error_message = "The alias record should be created"
  }
}

################################################################################
# Query logging
################################################################################

run "query_logging" {
  command = plan

  variables {
    name                 = "example.com"
    enable_query_logging = true
    query_log_group_arn  = "arn:aws:logs:us-east-1:123456789012:log-group:/aws/route53/example.com:*"
  }

  assert {
    condition     = length(aws_route53_query_log.this) == 1
    error_message = "A query log configuration should be created"
  }
}

################################################################################
# DNSSEC
################################################################################

run "dnssec" {
  command = plan

  variables {
    name               = "example.com"
    enable_dnssec      = true
    dnssec_kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
  }

  assert {
    condition     = length(aws_route53_key_signing_key.this) == 1
    error_message = "A DNSSEC key signing key should be created"
  }

  assert {
    condition     = length(aws_route53_hosted_zone_dnssec.this) == 1
    error_message = "DNSSEC should be enabled on the hosted zone"
  }
}
