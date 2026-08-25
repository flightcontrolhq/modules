################################################################################
# Local Values
################################################################################

locals {
  # Tags
  default_tags = {
    ManagedBy = "terraform"
    Module    = "sandbox-pool"
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
  ingress_domain   = "sbx.${var.env_slug}.${var.ingress.domain}"
  wildcard_domain  = "*.sbx.${var.env_slug}.${var.ingress.domain}"
  create_dns       = var.ingress.hosted_zone_id != null
  internet_facing  = coalesce(var.ingress.internet_facing, true)
  ingress_cidrs    = coalesce(var.ingress.allowed_cidrs, ["0.0.0.0/0"])
  nlb_subnet_ids   = var.nlb_subnet_ids != null ? var.nlb_subnet_ids : var.execution_environment.subnet_ids
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
