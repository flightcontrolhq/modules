locals {
  region = coalesce(var.region, data.aws_region.current.id)

  # Auto-mode resolution. When use_ravion_subdomain is on, the data
  # source ignores customer-supplied provider inputs and looks up the
  # platform apex by its stable givenId (seeded at api-go boot). When
  # off, the customer's provider id/given_id is used.
  auto_provider_id = (
    var.use_ravion_subdomain
    ? null
    : (var.ravion_dns_provider_id != null && var.ravion_dns_provider_id != "" ? var.ravion_dns_provider_id : null)
  )
  auto_provider_given_id = (
    var.use_ravion_subdomain
    ? "ravion-platform-apex"
    : (var.ravion_dns_provider_given_id != null && var.ravion_dns_provider_given_id != "" ? var.ravion_dns_provider_given_id : null)
  )

  # The data source's count is gated on having SOMETHING to look up.
  # Auto-mode always has the platform given_id; customer mode requires
  # one of the two caller inputs.
  enable_dns_provider_lookup = (
    var.use_ravion_subdomain ||
    local.auto_provider_id != null ||
    local.auto_provider_given_id != null
  )

  # The resolved DnsProvider row (only present when the data source's
  # count == 1). Per-variant attribute groups (`route53_ravion`,
  # `route53`, `cloudflare`, `external`) are how the ravion_domains.tf
  # blocks dispatch — exactly one is non-null per row.
  dns_provider = local.enable_dns_provider_lookup ? data.ravion_dns_provider.this[0] : null

  # Ravion-managed domains gate. When true the cluster allocates a
  # wildcard FQDN + issues a wildcard ACM cert in ravion_domains.tf;
  # service modules under this cluster inherit the wildcard via SNI.
  enable_ravion_domain = (
    var.enable_public_alb &&
    var.public_alb_enable_https &&
    local.dns_provider != null
  )

  # Auto-mode fqdnOverride: literal `<module-instance-id>.<apex>`. The
  # cluster's wildcard cert covers `*.<module-instance-id>.<apex>` so
  # services under it inherit via SNI. Falls back to null when
  # module_instance_id is unset (standalone use) — in that case auto-
  # mode is effectively disabled and slug-mode kicks in.
  #
  # Apex trim — the DnsProvider's domain_name MAY arrive with a
  # trailing dot (depends on how the row was seeded). Trim it so the
  # resulting FQDN is canonical (no `<id>.example.com..`) and the
  # api-go under-apex check passes without depending on its
  # forgiving-trailing-dot logic.
  cluster_auto_fqdn = (
    var.use_ravion_subdomain && var.module_instance_id != null && var.module_instance_id != ""
    ? format("%s.%s", var.module_instance_id, local.dns_provider != null ? trimsuffix(local.dns_provider.domain_name, ".") : "")
    : null
  )

  # Per-variant flags — count gating on these decides which writer
  # path validation + apex routing records take. Mutually exclusive:
  # exactly one is true when enable_ravion_domain is true (except
  # EXTERNAL — see note below).
  is_route53_ravion = local.enable_ravion_domain && local.dns_provider.route53_ravion != null
  is_route53        = local.enable_ravion_domain && local.dns_provider.route53 != null
  is_cloudflare     = local.enable_ravion_domain && local.dns_provider.cloudflare != null
  # EXTERNAL: the customer brings their own DNS + cert flow entirely.
  # Ravion-managed cert is NOT available for this variant — module
  # allocates the FQDN row for tracking but skips ACM. The cluster
  # must be configured with public_alb_certificate_arns in this mode.
  is_external = local.enable_ravion_domain && local.dns_provider.external != null

  # ACM cert is issued for variants where Ravion (or the customer's
  # TF) can write DNS validation records the cert validation block
  # can wait on. EXTERNAL is excluded because we don't have a
  # variant-specific writer for arbitrary registrars.
  enable_acm_cert = local.is_route53_ravion || local.is_route53 || local.is_cloudflare

  # The ALB's HTTPS listener takes a single default cert + N SNI extras.
  # Ravion-managed mode puts the wildcard first (default); BYO mode uses
  # the customer's list verbatim. Using the validation resource's output
  # ensures the listener depends on ACM validation completing.
  public_alb_effective_certificate_arns = (
    local.enable_acm_cert
    ? concat([aws_acm_certificate_validation.cluster[0].certificate_arn], var.public_alb_certificate_arns)
    : var.public_alb_certificate_arns
  )
}

################################################################################
# Local Values
################################################################################

locals {
  # Default tags for all resources
  default_tags = {
    ManagedBy = "terraform"
    Module    = "compute/ecs_cluster"
  }

  tags = merge(local.default_tags, var.tags)

  # Determine if EC2 capacity provider should be created
  enable_ec2 = var.ec2_instance_type != null

  # Cluster name
  cluster_name = var.name

  # EC2 capacity provider name
  ec2_capacity_provider_name = local.enable_ec2 ? "${var.name}-ec2" : null

  # Build capacity provider strategy based on enabled providers
  capacity_provider_strategy = concat(
    var.enable_fargate ? [{
      capacity_provider = "FARGATE"
      weight            = var.fargate_weight
      base              = var.fargate_base
    }] : [],
    var.enable_fargate_spot ? [{
      capacity_provider = "FARGATE_SPOT"
      weight            = var.fargate_spot_weight
      base              = var.fargate_spot_base
    }] : [],
    local.enable_ec2 ? [{
      capacity_provider = aws_ecs_capacity_provider.ec2[0].name
      weight            = var.ec2_weight
      base              = var.ec2_base
    }] : []
  )

  # User data script for ECS EC2 instances
  ecs_user_data = local.enable_ec2 ? base64encode(<<-EOF
    #!/bin/bash
    echo ECS_CLUSTER=${aws_ecs_cluster.this.name} >> /etc/ecs/ecs.config
    echo ECS_ENABLE_CONTAINER_METADATA=true >> /etc/ecs/ecs.config
    ${var.ec2_user_data}
  EOF
  ) : null

  # Instance types for mixed instances policy
  ec2_instance_types = local.enable_ec2 ? concat(
    [var.ec2_instance_type],
    var.ec2_spot_instance_types
  ) : []
}


