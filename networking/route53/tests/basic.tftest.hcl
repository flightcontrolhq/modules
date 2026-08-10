# Route53 module tests — run from module root: tofu test

mock_provider "aws" {
  alias = "us_east_1"

  override_resource {
    target = aws_cloudwatch_log_group.query_logs
    values = {
      arn = "arn:aws:logs:us-east-1:123456789012:log-group:/aws/route53/example.com"
    }
  }
}

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
    target = data.aws_iam_policy_document.route53_query_logs
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
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
    name                 = "internal.example.com"
    private_zone_enabled = true
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
    zone_creation_enabled = false
    zone_id               = "Z1EXISTING00000000"
    records = [
      {
        name    = "www.existing.example.com"
        type    = "A"
        ttl     = 300
        records = ["192.0.2.1"]
      },
      {
        name    = "existing.example.com"
        type    = "TXT"
        ttl     = 300
        records = ["v=spf1 -all"]
      }
    ]
  }

  assert {
    condition     = length(aws_route53_zone.public) == 0
    error_message = "No zone should be created when zone_creation_enabled = false"
  }

  assert {
    condition     = length(aws_route53_record.this) == 2
    error_message = "Two records should be created"
  }
}

run "record_value_for_standard_record" {
  command = plan

  variables {
    name = "example.com"
    records = [
      {
        name         = "www.example.com"
        type         = "A"
        standard_ttl = 300
        record_value = "192.0.2.1"
      }
    ]
  }

  assert {
    condition     = aws_route53_record.this["A-www.example.com"].records == toset(["192.0.2.1"])
    error_message = "record_value should be used for standard non-alias records"
  }
}

################################################################################
# Alias record to ALB
################################################################################

run "alias_record" {
  command = plan

  variables {
    name = "example.com"
    records = [
      {
        name = "example.com"
        type = "A"
        alias = {
          name                   = "dualstack.my-alb-1234.us-east-1.elb.amazonaws.com"
          zone_id                = "Z35SXDOTRQ7X7K"
          evaluate_target_health = true
        }
      }
    ]
  }

  assert {
    condition     = length(aws_route53_record.this) == 1
    error_message = "The alias record should be created"
  }
}

################################################################################
# Non-simple routing policies
################################################################################

run "weighted_records_with_set_identifiers" {
  command = plan

  variables {
    name = "example.com"
    records = [
      {
        name                           = "www.example.com"
        type                           = "A"
        ttl                            = 300
        records                        = ["192.0.2.1"]
        routing_policy                 = "weighted"
        set_identifier                 = "blue"
        weighted_routing_policy_weight = 10
      },
      {
        name           = "www.example.com"
        type           = "A"
        ttl            = 300
        records        = ["192.0.2.2"]
        set_identifier = "green"
        weighted_routing_policy = {
          weight = 90
        }
      }
    ]
  }

  assert {
    condition     = length(aws_route53_record.this) == 2
    error_message = "Weighted records with different set identifiers should create separate records"
  }
}

run "routing_policy_requires_set_identifier" {
  command = plan

  variables {
    name = "example.com"
    records = [
      {
        name                           = "www.example.com"
        type                           = "A"
        ttl                            = 300
        records                        = ["192.0.2.1"]
        routing_policy                 = "weighted"
        weighted_routing_policy_weight = 10
      }
    ]
  }

  expect_failures = [var.records]
}

run "nested_routing_policy_requires_set_identifier" {
  command = plan

  variables {
    name = "example.com"
    records = [
      {
        name    = "www.example.com"
        type    = "A"
        ttl     = 300
        records = ["192.0.2.1"]
        weighted_routing_policy = {
          weight = 10
        }
      }
    ]
  }

  expect_failures = [var.records]
}

################################################################################
# Record value character-string limits
################################################################################

run "quoted_caa_value_succeeds" {
  command = plan

  variables {
    name = "example.com"
    records = [
      {
        name    = "example.com"
        type    = "CAA"
        ttl     = 300
        records = ["0 issue \"amazon.com\""]
      }
    ]
  }

  assert {
    condition     = aws_route53_record.this["CAA-example.com"].records == toset(["0 issue \"amazon.com\""])
    error_message = "CAA values should preserve the quoted authority required by Route 53"
  }
}

run "long_unquoted_txt_value_is_split_into_quoted_strings" {
  command = plan

  variables {
    name = "example.com"
    records = [
      {
        name    = "selector._domainkey.example.com"
        type    = "TXT"
        ttl     = 300
        records = ["v=DKIM1;k=rsa;p=012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789"]
      }
    ]
  }

  assert {
    condition     = length(local.normalized_records["TXT-selector._domainkey.example.com"].records) == 1
    error_message = "The split value should stay a single Route 53 record value"
  }

  assert {
    condition     = length(regexall("\"[^\"]{1,255}\"", local.normalized_records["TXT-selector._domainkey.example.com"].records[0])) == 2
    error_message = "A TXT value longer than 255 characters should be split into two quoted strings"
  }

  assert {
    condition     = replace(replace(local.normalized_records["TXT-selector._domainkey.example.com"].records[0], "\" \"", ""), "\"", "") == "v=DKIM1;k=rsa;p=012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789"
    error_message = "Splitting a TXT value should preserve the original characters"
  }
}

run "long_unsplittable_record_value_fails" {
  command = plan

  variables {
    name = "example.com"
    records = [
      {
        name    = "_sip._tcp.example.com"
        type    = "SRV"
        ttl     = 300
        records = ["10 5 5060 012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789.example.com"]
      }
    ]
  }

  expect_failures = [var.records]
}

run "long_quoted_chunk_fails" {
  command = plan

  variables {
    name = "example.com"
    records = [
      {
        name    = "selector._domainkey.example.com"
        type    = "TXT"
        ttl     = 300
        records = ["\"v=DKIM1;k=rsa;p=012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789\""]
      }
    ]
  }

  expect_failures = [var.records]
}

run "unbalanced_quotes_fail" {
  command = plan

  variables {
    name = "example.com"
    records = [
      {
        name    = "example.com"
        type    = "TXT"
        ttl     = 300
        records = ["\"v=spf1 include:example.net ~all"]
      }
    ]
  }

  expect_failures = [var.records]
}

run "quoted_value_with_unquoted_text_fails" {
  command = plan

  variables {
    name = "example.com"
    records = [
      {
        name    = "example.com"
        type    = "TXT"
        ttl     = 300
        records = ["\"v=spf1\" include:example.net012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789 ~all"]
      }
    ]
  }

  expect_failures = [var.records]
}

run "long_non_ascii_txt_value_fails" {
  command = plan

  variables {
    name = "example.com"
    records = [
      {
        name    = "example.com"
        type    = "TXT"
        ttl     = 300
        records = ["ααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααααα"]
      }
    ]
  }

  expect_failures = [var.records]
}

run "manually_split_long_value_succeeds" {
  command = plan

  variables {
    name = "example.com"
    records = [
      {
        name    = "selector._domainkey.example.com"
        type    = "TXT"
        ttl     = 300
        records = ["\"v=DKIM1;k=rsa;p=01234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789\" \"01234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789\""]
      }
    ]
  }

  assert {
    condition     = length(aws_route53_record.this) == 1
    error_message = "A TXT record split into quoted strings of at most 255 characters should be accepted"
  }
}

run "single_record_value_within_limit_succeeds" {
  command = plan

  variables {
    name = "example.com"
    records = [
      {
        name         = "www.example.com"
        type         = "CNAME"
        ttl          = 300
        record_value = "target.example.net"
      }
    ]
  }

  assert {
    condition     = length(aws_route53_record.this) == 1
    error_message = "A single-value record within the character-string limit should be accepted"
  }
}

################################################################################
# Query logging
################################################################################

run "query_logging" {
  command = plan

  variables {
    name                  = "example.com"
    query_logging_enabled = true
    query_log_group_arn   = "arn:aws:logs:us-east-1:123456789012:log-group:/aws/route53/example.com:*"
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
    dnssec_enabled     = true
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
