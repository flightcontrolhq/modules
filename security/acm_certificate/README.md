# AWS ACM Certificate Module

Requests an AWS Certificate Manager (ACM) **public** certificate using **DNS validation**. By default the module only creates the certificate request and **outputs the validation CNAME records** for you to add at your DNS provider. Optional flags enable automatic **Route53** validation records and/or **waiting** until the certificate is issued.

## Features

- DNS validation (`aws_acm_certificate` with `validation_method = DNS`)
- **Default**: output `validation_records` (CNAME name, type, value per domain); no Route53 resources; no blocking wait
- **Optional**: `create_route53_validation_records` + `route53_zone_id` to create validation CNAMEs in a single Route53 public hosted zone
- **Optional**: `wait_for_validation` to add `aws_acm_certificate_validation` (apply waits until the certificate is **ISSUED**)
- Optional Subject Alternative Names (SANs)
- Tags and `create_before_destroy` lifecycle on the certificate

## Regional notes

- **Application Load Balancers**: Use an ACM certificate in the **same AWS Region** as the ALB.
- **CloudFront**: The certificate must be in **us-east-1** (N. Virginia), regardless of where other resources live.

## Usage

### Default — output CNAMEs only

Use this when DNS is managed outside this Terraform stack (or you will add records manually), and you do not want Terraform to wait for issuance on the first apply.

```hcl
module "cert" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//security/acm_certificate?ref=v1.0.0"

  name        = "api"
  domain_name = "api.example.com"

  # create_route53_validation_records = false  # default
  # wait_for_validation                = false # default
}

# After apply: add module.cert.validation_records at your DNS provider, then optionally
# set wait_for_validation = true (and/or create_route53_validation_records) and apply again.
```

### Full automation — Route53 records + wait for issuance

Use when all validation names can be created in **one** Route53 public hosted zone (typical for `example.com` and `*.example.com` in the same zone).

```hcl
module "cert" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//security/acm_certificate?ref=v1.0.0"

  name                              = "api"
  domain_name                       = "api.example.com"
  create_route53_validation_records = true
  route53_zone_id                   = aws_route53_zone.primary.zone_id
  wait_for_validation               = true

  tags = {
    Environment = "production"
  }
}
```

### Subject Alternative Names

```hcl
module "cert" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//security/acm_certificate?ref=v1.0.0"

  name        = "app"
  domain_name = "app.example.com"
  subject_alternative_names = [
    "www.example.com",
  ]
}
```

Do not duplicate the primary `domain_name` in `subject_alternative_names` (ACM will reject invalid combinations).

### With Application Load Balancer

```hcl
module "cert" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//security/acm_certificate?ref=v1.0.0"

  name        = "main"
  domain_name = "api.example.com"
}

module "alb" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//networking/alb?ref=v1.0.0"

  name       = "main"
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnet_ids

  enable_https_listener = true
  certificate_arn       = module.cert.certificate_arn

  tags = {
    Environment = "production"
  }
}
```

Ensure the certificate is **ISSUED** before the ALB listener depends on a fully valid cert in all cases (defaults allow a **PENDING_VALIDATION** ARN until DNS is completed).

## Requirements

| Name              | Version   |
| ----------------- | --------- |
| opentofu/terraform | >= 1.10.0 |
| aws               | >= 5.0    |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Name prefix for tagging the certificate | `string` | n/a | yes |
| domain_name | Primary FQDN for the certificate | `string` | n/a | yes |
| subject_alternative_names | Additional FQDNs (SANs) | `list(string)` | `[]` | no |
| tags | Tags for the ACM certificate | `map(string)` | `{}` | no |
| create_route53_validation_records | Create Route53 CNAME validation records | `bool` | `false` | no |
| route53_zone_id | Route53 public hosted zone ID (required if `create_route53_validation_records` is true) | `string` | `null` | no |
| wait_for_validation | Create `aws_acm_certificate_validation` and wait until issued | `bool` | `false` | no |

## Outputs

| Name | Description |
|------|-------------|
| certificate_arn | ARN of the ACM certificate |
| certificate_status | ACM status string (e.g. `PENDING_VALIDATION`, `ISSUED`) |
| validation_records | List of objects with `domain_name`, `name`, `type`, `value` for DNS validation |

## Limitations (v1)

- **Single Route53 zone**: If you enable `create_route53_validation_records`, all validation record names must be creatable in the supplied `route53_zone_id`. SANs that validate under a different zone are not supported in this module version; use default mode and create those records manually or split stacks.
- **Private CA / imported certificates**: Not supported; use dedicated workflows for those.

Provider and OpenTofu constraints are defined in [versions.tf](versions.tf).
