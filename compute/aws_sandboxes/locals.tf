################################################################################
# Local Values
################################################################################

locals {
  # Tags
  default_tags = {
    ManagedBy = "terraform"
    Module    = "aws-sandboxes"
  }
  tags = merge(local.default_tags, var.tags, {
    "ravion:pool" = var.pool_id
  })

  # Names. pool_id is a Ravion id (`sbxp_<ksuid>`), and load balancers, target
  # groups and S3 want lowercase alphanumerics and hyphens only, so the id is
  # folded into a name-safe stem first. The `ravion:pool` tag, the SSM prefix
  # and the log groups keep the verbatim id: that is what Tower filters the
  # fleet by and what its per-host IAM conditions are written against.
  pool_name = lower(replace(var.pool_id, "_", "-"))

  # Load balancers and target groups cap at 32 characters, so a long pool id is
  # folded to a readable 20-char stem plus a hash that stays unique.
  pool_suffix = length(local.pool_name) <= 20 ? local.pool_name : "${substr(local.pool_name, 0, 12)}-${substr(sha1(var.pool_id), 0, 7)}"
  name_prefix = "rvn-sbx-${local.pool_suffix}"

  account_id = data.aws_caller_identity.current.account_id
  region     = coalesce(var.region, data.aws_region.current.region)
  partition  = data.aws_partition.current.partition

  # Ingress: <sandboxId>-<port>.sbx.<env>.<domain>
  #
  # The whole public path — NLB, TLS listener, both target groups, the NLB
  # security group, the wildcard certificate and its validation, the wildcard
  # alias record — hangs off this one switch. A pool without it still runs
  # sandboxes; it simply has nowhere to publish a port to, and every in-VPC
  # path (the private zone below, `vpc-ip` addressing, internal_access_cidrs)
  # is untouched. Turning it on later is an ordinary change run.
  #
  # A null `ingress` and an ingress whose `domain` is null or blank mean the
  # same thing. Both spellings have to work: the module.yaml mapping renders the
  # object's keys unconditionally, so an unset domain arrives as
  # `{ domain = null, internet_facing = true, ... }` rather than as no object at
  # all, and treating that as "ingress requested" would produce a certificate
  # for `*.sbx.<env>.` and an apply that never validates.
  ingress_enabled = try(trimspace(var.ingress.domain), "") != ""

  # Read through `try` rather than `var.ingress.x`: a conditional in Terraform
  # is not reliably short-circuiting, so an attribute access on a null object
  # can be evaluated even in the branch that is not taken.
  ingress_domain_input          = try(var.ingress.domain, null)
  ingress_hosted_zone_id        = try(var.ingress.hosted_zone_id, null)
  ingress_internet_facing_input = try(var.ingress.internet_facing, null)
  ingress_allowed_cidrs_input   = try(var.ingress.allowed_cidrs, null)

  ingress_domain  = local.ingress_enabled ? "sbx.${var.env_slug}.${local.ingress_domain_input}" : null
  wildcard_domain = local.ingress_enabled ? "*.sbx.${var.env_slug}.${local.ingress_domain_input}" : null
  create_dns      = local.ingress_enabled && local.ingress_hosted_zone_id != null
  internet_facing = local.ingress_enabled && coalesce(local.ingress_internet_facing_input, true)
  ingress_cidrs   = local.ingress_enabled ? coalesce(local.ingress_allowed_cidrs_input, ["0.0.0.0/0"]) : []

  # Raw TCP exposure is a property of the ingress NLB, so it cannot outlive it.
  tcp_exposure_enabled = local.ingress_enabled && var.enable_tcp_exposure

  # Certificate validation records, empty when there is no certificate.
  # Splatted through the attribute rather than `one(...)` over the resource: the
  # certificate object as a whole carries a sensitive mark, and a sensitive
  # value cannot be a `for_each` key or an unmarked output.
  acm_validation_options = flatten(aws_acm_certificate.wildcard[*].domain_validation_options)

  nlb_subnet_ids   = length(coalesce(var.nlb_subnet_ids, [])) > 0 ? var.nlb_subnet_ids : (local.internet_facing ? var.public_subnet_ids : var.private_subnet_ids)
  ip_address_type  = var.ipv6_enabled ? "dualstack" : "ipv4"
  private_zone     = coalesce(var.private_zone_name, "sbx.${var.env_slug}.internal")
  ssm_param_prefix = "/ravion/sandboxes/${var.pool_id}/hosts"

  # Storage. One pool per environment, so the env slug plus the account id is
  # unique; the account id is what keeps the name globally unique.
  snapshots_bucket = "rvn-sbx-${var.env_slug}-snapshots-${local.account_id}"

  # Observability
  host_log_group    = "/ravion/sandboxes/${var.pool_id}/host"
  sandbox_log_group = "/ravion/sandboxes/${var.pool_id}/sandbox"

  # Mode switches
  vpc_ip_mode = var.network_mode == "vpc-ip"

  # Requests signed with EC2 instance-profile credentials always carry
  # ec2:SourceInstanceARN. Pinning it to an instance ARN in this account and
  # region means "these credentials are being used from an EC2 instance in
  # this pool's account", so a copy exfiltrated to a laptop or a Lambda is
  # refused. On its own it says nothing about *which* instance — that is what
  # host_instance_arn_tag is for on the SSM grant, and what the ENI grants
  # get by tag-scoping to this pool.
  host_instance_arn_pattern = "arn:${local.partition}:ec2:${local.region}:${local.account_id}:instance/*"

  # Tag key the reconciler puts on each host's SSM credential parameter,
  # carrying the ARN of the one instance allowed to read it. IAM has no
  # policy variable for the calling instance's id, but it can compare a
  # resource tag against ${ec2:SourceInstanceARN} — so this tag is what turns
  # a pool-wide resource ARN into a per-instance grant. Kept in lockstep with
  # tower-go's ProvisionSandboxHostCredential activity.
  host_instance_arn_tag = "ravion:instance-arn"
}
