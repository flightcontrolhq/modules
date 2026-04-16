# Route53 Module

Manage AWS Route53 hosted zones and their DNS records. Supports creating new
public or private hosted zones, or managing records in an existing zone. Also
supports optional VPC associations, query logging, and DNSSEC signing.

## Features

- Create a public or private hosted zone, or reference an existing one
- Manage DNS records of any common type (A, AAAA, CNAME, MX, TXT, SRV, CAA, NS, PTR, NAPTR, SOA, SPF, DS)
- Alias records for AWS resources (ALB, CloudFront, API Gateway, S3, etc.)
- Routing policies: weighted, failover, latency, geolocation, multivalue-answer
- VPC associations for private hosted zones (including additional associations across accounts/regions)
- Optional query logging to CloudWatch Logs
- Optional DNSSEC signing with a customer-managed KMS key
- Reusable delegation sets

## Usage

### Minimal: create a public hosted zone

```hcl
module "dns" {
  source = "git::https://github.com/flightcontrolhq/modules.git//networking/route53?ref=v1.0.0"

  name = "example.com"

  tags = {
    Environment = "production"
  }
}
```

### Public hosted zone with records

```hcl
module "dns" {
  source = "git::https://github.com/flightcontrolhq/modules.git//networking/route53?ref=v1.0.0"

  name = "example.com"

  records = {
    apex = {
      name = "example.com"
      type = "A"
      alias = {
        name                   = module.alb.alb_dns_name
        zone_id                = module.alb.alb_zone_id
        evaluate_target_health = true
      }
    }

    www = {
      name    = "www.example.com"
      type    = "CNAME"
      ttl     = 300
      records = ["example.com"]
    }

    spf = {
      name    = "example.com"
      type    = "TXT"
      ttl     = 300
      records = ["v=spf1 -all"]
    }

    mx = {
      name = "example.com"
      type = "MX"
      ttl  = 300
      records = [
        "10 inbound-smtp.us-east-1.amazonaws.com",
      ]
    }
  }
}
```

### Manage records in an existing hosted zone

```hcl
module "app_dns" {
  source = "git::https://github.com/flightcontrolhq/modules.git//networking/route53?ref=v1.0.0"

  create_zone = false
  zone_id     = "Z1234567890ABC"

  records = {
    api = {
      name    = "api.example.com"
      type    = "A"
      ttl     = 60
      records = ["192.0.2.10"]
    }
  }
}
```

### Private hosted zone

```hcl
module "internal_dns" {
  source = "git::https://github.com/flightcontrolhq/modules.git//networking/route53?ref=v1.0.0"

  name         = "internal.example.com"
  private_zone = true

  vpc_associations = {
    primary = {
      vpc_id     = module.vpc.vpc_id
      vpc_region = "us-east-1"
    }
  }

  records = {
    db = {
      name    = "db.internal.example.com"
      type    = "CNAME"
      ttl     = 60
      records = [module.rds.endpoint]
    }
  }
}
```

### Weighted routing (blue/green)

```hcl
module "dns" {
  source = "..."

  name = "example.com"

  records = {
    api_blue = {
      name           = "api.example.com"
      type           = "A"
      set_identifier = "blue"
      weighted_routing_policy = {
        weight = 90
      }
      alias = {
        name                   = module.alb_blue.alb_dns_name
        zone_id                = module.alb_blue.alb_zone_id
        evaluate_target_health = true
      }
    }

    api_green = {
      name           = "api.example.com"
      type           = "A"
      set_identifier = "green"
      weighted_routing_policy = {
        weight = 10
      }
      alias = {
        name                   = module.alb_green.alb_dns_name
        zone_id                = module.alb_green.alb_zone_id
        evaluate_target_health = true
      }
    }
  }
}
```

### Query logging

Query logging requires a pre-existing CloudWatch log group. For public zones
the log group **must** be in `us-east-1` and have a resource policy permitting
Route53 to write to it.

```hcl
module "dns" {
  source = "..."

  name                 = "example.com"
  enable_query_logging = true
  query_log_group_arn  = aws_cloudwatch_log_group.dns_queries.arn
}
```

### DNSSEC

DNSSEC signing requires a customer-managed KMS key in `us-east-1` with the
appropriate key policy for Route53. After the module is applied, publish the
`dnssec_ds_record` output to the parent zone (registrar).

```hcl
module "dns" {
  source = "..."

  name               = "example.com"
  enable_dnssec      = true
  dnssec_kms_key_arn = aws_kms_key.dnssec.arn
}

output "ds_record" {
  value = module.dns.dnssec_ds_record
}
```

## Requirements

| Name               | Version   |
| ------------------ | --------- |
| opentofu/terraform | >= 1.10.0 |
| aws                | >= 5.0    |

## Inputs

### General

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| tags | A map of tags to assign to the hosted zone | `map(string)` | `{}` | no |

### Hosted Zone

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| create_zone | If true, create a new hosted zone; if false, reference an existing zone via `zone_id` | `bool` | `true` | no |
| zone_id | ID of an existing hosted zone to manage records in (required when `create_zone = false`) | `string` | `null` | conditional |
| name | FQDN for the hosted zone (required when `create_zone = true`) | `string` | `null` | conditional |
| comment | Comment for the hosted zone | `string` | `"Managed by Terraform"` | no |
| force_destroy | Destroy all records when the zone is destroyed | `bool` | `false` | no |
| delegation_set_id | Reusable delegation set ID (public zones only) | `string` | `null` | no |

### Private Zone

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| private_zone | Whether the created zone is private | `bool` | `false` | no |
| vpc_associations | Map of VPCs to associate with the private zone | `map(object)` | `{}` | no |

Each entry in `vpc_associations` supports:

| Key | Description | Type | Required |
|-----|-------------|------|----------|
| vpc_id | The ID of the VPC to associate | `string` | yes |
| vpc_region | The region of the VPC | `string` | no |

### Records

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| records | Map of DNS records to manage, keyed by a stable identifier | `map(object)` | `{}` | no |

Each record supports:

| Key | Description | Type | Required |
|-----|-------------|------|----------|
| name | The record name (FQDN or relative to the zone) | `string` | yes |
| type | Record type: `A`, `AAAA`, `CNAME`, `CAA`, `MX`, `NAPTR`, `NS`, `PTR`, `SOA`, `SPF`, `SRV`, `TXT`, `DS` | `string` | yes |
| ttl | TTL in seconds (required unless using `alias`) | `number` | conditional |
| records | Record values (required unless using `alias`) | `list(string)` | conditional |
| alias | Alias target `{ name, zone_id, evaluate_target_health }` (use instead of `ttl`/`records`) | `object` | conditional |
| set_identifier | Unique ID for routing-policy records | `string` | no |
| health_check_id | Route53 health check ID | `string` | no |
| allow_overwrite | Allow creation to overwrite an existing record | `bool` | no |
| weighted_routing_policy | `{ weight }` block | `object` | no |
| failover_routing_policy | `{ type }` (PRIMARY or SECONDARY) | `object` | no |
| latency_routing_policy | `{ region }` | `object` | no |
| geolocation_routing_policy | `{ continent, country, subdivision }` | `object` | no |
| multivalue_answer_routing_policy | Enable multivalue answer routing | `bool` | no |

### Query Logging

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| enable_query_logging | Enable Route53 query logging | `bool` | `false` | no |
| query_log_group_arn | ARN of the destination CloudWatch log group | `string` | `null` | conditional |

### DNSSEC

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| enable_dnssec | Enable DNSSEC signing | `bool` | `false` | no |
| dnssec_kms_key_arn | KMS key ARN in `us-east-1` used for signing | `string` | `null` | conditional |
| dnssec_signing_status | `SIGNING` or `NOT_SIGNING` | `string` | `"SIGNING"` | no |

## Outputs

| Name | Description |
|------|-------------|
| zone_id | The ID of the hosted zone |
| zone_arn | The ARN of the hosted zone (null when referencing existing) |
| zone_name | The name of the hosted zone |
| name_servers | The name servers assigned to the zone |
| primary_name_server | The primary name server of the zone |
| is_private_zone | Whether the zone is private |
| record_names | Map of record keys to FQDNs |
| record_ids | Map of record keys to Route53 record IDs |
| dnssec_key_signing_key_id | The ID of the KSK (null when DNSSEC disabled) |
| dnssec_ds_record | The DS record to publish to the parent zone |
| query_log_id | The ID of the query log configuration |

## Notes

- Route53 hosted zones are global; the provider region does not affect zone
  placement, but DNSSEC KMS keys and public-zone query log groups must live in
  `us-east-1`.
- For private zones, the initial VPC associations are attached to the zone
  resource directly. To associate additional VPCs (including cross-account
  VPCs), use the `aws_route53_vpc_association_authorization` /
  `aws_route53_zone_association` resources outside the module.
- When using `create_zone = false`, `force_destroy` has no effect and the
  upstream zone is not managed.
- Alias records cannot specify a TTL; TTLs are inherited from the target.
