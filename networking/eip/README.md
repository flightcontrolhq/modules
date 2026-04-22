# AWS Elastic IP Pool Module

Allocates a pool of AWS Elastic IPs (VPC-domain) with deterministic, zero-padded `Name` tags. Useful for any workload that needs a stable set of egress IPs known at infrastructure-plan time — for example, NAT Gateway egress addresses that downstream consumers reference in `aws:SourceIp` conditions, security group rules, or third-party allowlists.

The module is intentionally thin: it allocates `var.eip_count` Elastic IPs, tags each with a deterministic `<name>-NN` `Name` tag, and exposes the allocation IDs and public IPs.

## Features

- Allocates 1–20 EIPs in a single module invocation
- Deterministic, lexicographically sortable per-address `Name` tags (`<name>-01`, `<name>-02`, ...)
- Outputs ready-to-use `/32` CIDRs for `aws:SourceIp` conditions and security group rules
- Optional `network_border_group` for Local Zones / Wavelength targets

## Usage

```hcl
module "egress_eips" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//networking/eips?ref=v1.0.0"

  name      = "egress-prod"
  eip_count = 6

  tags = {
    Environment = "prod"
  }
}

# Wire the EIPs into a NAT Gateway, security group rule, etc.
output "egress_cidrs" {
  value = module.egress_eips.public_ip_cidrs
}
```

## Quotas

AWS's default Elastic IP quota is **5 per region**. Allocations above that require a prior quota increase via Service Quotas; the module's upper bound of 20 leaves headroom for typical multi-AZ NAT setups but does not bypass the quota itself.

## Requirements

| Name               | Version   |
| ------------------ | --------- |
| opentofu/terraform | >= 1.10.0 |
| aws                | >= 5.0    |

## Inputs

| Name                   | Description                                                                                                             | Type          | Default | Required |
| ---------------------- | ----------------------------------------------------------------------------------------------------------------------- | ------------- | ------- | -------- |
| `name`                 | Name prefix for each EIP's `Name` tag (e.g. `egress-prod` → `egress-prod-01`, `egress-prod-02`, ...). 1–48 characters.  | `string`      | n/a     | yes      |
| `eip_count`            | Number of EIPs to allocate. 1–20. AWS's default quota is 5/region — values above 5 require a prior quota increase.      | `number`      | n/a     | yes      |
| `region`               | AWS region for the EIP allocations. Defaults to the `aws` provider's region. Requires AWS provider v6.0+ when set.      | `string`      | `null`  | no       |
| `network_border_group` | Region's default border group unless set. Only needed for Local Zones / Wavelength targets.                             | `string`      | `null`  | no       |
| `tags`                 | Extra tags merged onto every EIP.                                                                                       | `map(string)` | `{}`    | no       |

## Outputs

| Name              | Description                                                                                          |
| ----------------- | ---------------------------------------------------------------------------------------------------- |
| `allocation_ids`  | EIP allocation IDs, ordered by index. Pass to `aws_nat_gateway.allocation_id` or similar.            |
| `public_ips`      | EIP public addresses, ordered by index.                                                              |
| `public_ip_cidrs` | Public addresses in `/32` CIDR notation. Drop directly into `aws:SourceIp` blocks or SG rules.       |
| `arns`            | EIP ARNs, ordered by index.                                                                          |
| `eip_count`       | Number of EIPs actually allocated.                                                                   |

## Tags applied by the module

Every allocated EIP receives:

- `ManagedBy = "terraform"`
- `Module = "networking/eips"`
- `Name = "<var.name>-NN"` — two-digit zero-padded index, 1-based
- Anything else supplied via `var.tags`
