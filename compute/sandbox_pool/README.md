# Sandbox Pool Module

Provisions the static half of a Ravion sandbox pool in a customer's AWS account: the host identity, the ingress path, the snapshot store and the launch template hosts are stamped from.

**Hosts are not in here.** The pool's fleet is dynamic — the Tower reconciler launches, cordons, drains and terminates EC2 instances from this module's launch template and tags them `ravion:pool=<pool_id>`, so a pool can scale from zero to hundreds of hosts without a Terraform run. This module knows nothing about individual instances, and nothing in its state changes when the fleet does. Everything else a pool needs is here, exactly once.

## Features

- Host IAM role, instance profile and a least-privilege policy: its own M2M credential from SSM, read/write on the snapshots bucket, log delivery, public-ECR auth, and — in `vpc-ip` mode — ENI address management scoped to the pool's own ENIs
- Host and NLB security groups, layered on top of the execution environment's SG
- Network Load Balancer with a TLS listener on 443, an instance target group for the host ingress proxy, and an IP target group for raw TCP exposure of sandbox IPs
- ACM wildcard certificate for `*.sbx.<env>.<domain>`, validated automatically when the Route 53 zone is yours and reported as records to add when it is not
- Route 53 wildcard alias record, plus a private hosted zone (`sbx.<env>.internal`) for per-sandbox records in `vpc-ip` mode
- S3 snapshot chunk store: SSE, public access blocked, versioning off, lifecycle expiry with a tag-based exemption for pinned objects
- Launch template with `cpu_options.nested_virtualization = "enabled"`, IMDSv2 required, a chunk-cache data volume and user-data that writes `/etc/ravion/sandbox-host.env`
- Host and sandbox CloudWatch log groups

## Usage

### A pool on a Route 53 zone you own

```hcl
module "sandbox_pool" {
  source = "git::https://github.com/ravionhq/modules.git//sandbox-pool?ref=v1.0.0"

  pool_id  = "clz9x8y7w6v5u4t3"
  env_slug = "prod"

  execution_environment = {
    vpc_id            = module.vpc.vpc_id
    subnet_ids        = module.vpc.private_subnet_ids
    security_group_id = aws_security_group.execution_environment.id
  }

  host_ami_id         = "ami-0123456789abcdef0"
  host_instance_types = ["m8i.2xlarge", "m8i.4xlarge"]

  ingress = {
    domain         = "example.com"
    hosted_zone_id = aws_route53_zone.public.zone_id
  }

  tags = {
    Environment = "production"
  }
}
```

Sandboxes are then reachable at `<sandboxId>-<port>.sbx.prod.example.com`, and in-VPC clients reach them directly at `<sandboxId>.sbx.prod.internal` on any port.

### An internal pool with an externally hosted zone

```hcl
module "sandbox_pool" {
  source = "git::https://github.com/ravionhq/modules.git//sandbox-pool?ref=v1.0.0"

  pool_id  = "clz9x8y7w6v5u4t3"
  env_slug = "staging"

  execution_environment = {
    vpc_id            = var.vpc_id
    subnet_ids        = var.subnet_ids
    security_group_id = var.security_group_id
  }

  host_ami_id = var.host_ami_id

  ingress = {
    domain          = "example.com"
    internet_facing = false
    allowed_cidrs   = ["10.0.0.0/8"]
  }

  network_mode          = "nat"
  internal_access_cidrs = ["10.0.0.0/8"]
}
```

With no `hosted_zone_id` the apply parks on certificate validation: add the CNAME pair the plan shows (also exported as `acm_validation_records`) to your DNS provider and the apply continues. A listener cannot attach a `PENDING_VALIDATION` certificate, so there is no way to skip that wait — see `acm_validation_timeout`.

## Network modes

| mode               | how a sandbox is addressed                                                                                                                                                                                                                 | trade-off                                                                                                                                    |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------- |
| `vpc-ip` (default) | Its own VPC private IP, taken from the host ENI's delegated `/28` prefixes. Egress leaves with the sandbox's own source IP, so security groups, flow logs and CloudTrail attribute per sandbox, and two sandboxes can both listen on 3306. | Needs subnet space — a `/22` per pool is comfortable — and the ENI permissions this module grants in this mode.                              |
| `nat`              | A private `10.200.x.x` address behind host-IP port remapping.                                                                                                                                                                              | Port collisions between sandboxes on one host have to be remapped, so stock tooling needs the mapped port. Use where subnet space is scarce. |

## IAM scoping limits

One grant is wider than "this host, its own resources", because IAM cannot say that:

- **ENI address management** (`vpc-ip` mode). Scoped by the `ravion:pool` tag the launch template puts on every ENI it creates, plus the same instance-credentials condition. IAM has no expression for "the ENI attached to me", so the residual is cross-host within a pool.

The **SSM host credential** grant used to be in that list, and is not any more. The resource ARN is still the pool prefix (`/ravion/sandboxes/<pool>/hosts/*`) — IAM cannot template the calling instance's id into an ARN — but the reconciler tags each parameter `ravion:instance-arn = <the ARN of the instance that may read it>`, and the grant carries `StringEquals { "ssm:ResourceTag/ravion:instance-arn": "${ec2:SourceInstanceARN}" }`. The tag is compared against the parameter being read and the variable resolves to the instance whose profile signed the request, so the two match for exactly one parameter per host. An untagged parameter under the prefix is unreadable by every host, which is the right direction to fail. The pool prefix in the ARN is what stops a host reading a _differently_ tagged parameter elsewhere in the account, and the `ec2:SourceInstanceARN` `ArnLike` keeps an exfiltrated copy of the credential off a laptop or a Lambda.

`ec2:DescribeNetworkInterfaces` takes no resource-level scoping at all; only the instance-credentials condition applies.

## Certificate validation

`acm_validation_records` is always exported, whether or not the module wrote the records itself. With `ingress.hosted_zone_id` set, the records are created and validation completes unattended; without it, the output is the instruction list.

## Provider version

`>= 6.33.0`. That is the first `hashicorp/aws` release whose `aws_launch_template` exposes `cpu_options.nested_virtualization` — the one setting that makes a host a KVM host. On an older provider the attribute does not exist, `/dev/kvm` never appears, and every sandbox on the pool fails to boot. This floor is higher than the `>= 5.0` the `networking/*` modules use, deliberately.

## Publishing

This module is Ravion-owned and reaches customer accounts through the module system, not by being applied by hand:

1. The directory is mirrored to `github.com/ravionhq/modules` under `sandbox-pool/` and tagged.
2. `module.yaml` here is the `ModuleVersion.config` for the Ravion-owned `ravion/sandbox-pool` `ModuleDefinition` (`organizationId = null`). Its `ref` pins the tag from step 1 — bump both together.
3. Enabling sandboxes on an environment creates a **system-managed** `ModuleInstance` in that environment: hidden from the module canvas, not user-editable, with the pool's settings as its inputs. Upgrades are a new `ModuleVersion`; Tower rolls system-managed instances onto it.

No output may be marked `sensitive`: the runner drops sensitive outputs before they reach `Stack.output`, so a sensitive output would simply never arrive at the pool's module-output cache.

## Teardown

Destroy is safe only after the reconciler has drained and terminated the pool's hosts, which it gates on there being no non-terminated sandboxes. The snapshots bucket refuses to be destroyed while it holds objects unless `force_destroy_snapshots_bucket` is set — snapshots are a cache, but losing the prewarm bases costs a cold rebuild.

## Inputs

See `variables.tf`. The ones that shape everything else:

| Name                      | Description                                                                                             | Default                   |
| ------------------------- | ------------------------------------------------------------------------------------------------------- | ------------------------- |
| `pool_id`                 | SandboxPool id; names every resource and keys the `ravion:pool` tag                                     | —                         |
| `env_slug`                | Environment slug; appears in the ingress domain, bucket name and private zone                           | —                         |
| `execution_environment`   | `{vpc_id, subnet_ids, security_group_id}` from the pool's ExecutionEnvironment                          | —                         |
| `host_ami_id`             | Ravion sandbox host AMI, shared to this account for this region                                         | —                         |
| `host_instance_types`     | Preference-ordered; the launch template pins the first, the reconciler uses the rest as fleet overrides | `["m8i.2xlarge"]`         |
| `network_mode`            | `vpc-ip` or `nat`                                                                                       | `vpc-ip`                  |
| `ingress`                 | `{domain, hosted_zone_id?, internet_facing?, allowed_cidrs?}`                                           | —                         |
| `private_zone_name`       | Private hosted zone name                                                                                | `sbx.<env_slug>.internal` |
| `snapshot_retention_days` | Expiry for unpinned snapshot objects                                                                    | `30`                      |
| `ravion_role_arn`         | Grants the Ravion cross-account role access to the snapshots bucket                                     | `null`                    |

## Outputs

Exactly the surface Tower caches on `SandboxPool` and hands to the reconciler:

| Name                             | Description                                           |
| -------------------------------- | ----------------------------------------------------- |
| `launch_template_id`             | Launch template hosts are stamped from                |
| `launch_template_latest_version` | The version a host rollout rolls to                   |
| `subnet_ids`                     | Subnets hosts launch into                             |
| `host_sg_id`                     | Pool host security group                              |
| `instance_profile_arn`           | Instance profile every host boots with                |
| `snapshots_bucket`               | Snapshot chunk store                                  |
| `nlb_target_group_arn`           | Instance target group for the ingress proxy           |
| `nlb_ip_target_group_arn`        | IP target group for TCP exposure (null when disabled) |
| `nlb_dns_name`                   | NLB DNS name                                          |
| `ingress_domain`                 | `sbx.<env>.<domain>`                                  |
| `private_zone_id`                | Private hosted zone for per-sandbox records           |
| `ssm_param_prefix`               | Where the reconciler writes per-host M2M credentials  |
| `acm_validation_records`         | Certificate validation records                        |

## Testing

```bash
cd packages/terraform/sandbox-pool
tofu init -backend=false
tofu validate
tofu test
```

The tests run entirely in plan mode against a mocked AWS provider — no credentials, no API calls. They cover the defaults, both network modes, an internal pool on an external zone, the host policy's scoping, and the name-length folding a long pool id triggers.

## Notes

- **VPC endpoints.** None are created here: the execution environment's network stack owns the S3 gateway and SSM/ECR interface endpoints the hosts use.
- **Host egress** defaults to TCP 443 plus DNS, matching the plan. Sandboxes that need other outbound ports need `host_allow_all_egress = true`; per-sandbox egress policy is enforced on the host by nftables either way, so this security group is the outer envelope, not the policy.
- **TCP exposure** pre-authorises `tcp_exposure_port_range` on both security groups. The NLB still drops traffic on any port without a listener, and listeners are added per exposed port by Tower.
