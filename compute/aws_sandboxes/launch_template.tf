################################################################################
# Host launch template
#
# The shape of a host, not a host: no instance is created here. The reconciler
# (§2.3) launches and terminates from this template with EC2 Fleet `instant`,
# which is also why `host_instance_types` beyond the first appear only as fleet
# overrides on its side.
################################################################################

resource "aws_launch_template" "host" {
  name        = local.name_prefix
  description = "Sandbox hosts for pool ${var.pool_id}"

  image_id      = var.host_ami_id
  instance_type = var.host_instance_types[0]
  ebs_optimized = true

  update_default_version = true

  iam_instance_profile {
    arn = aws_iam_instance_profile.host.arn
  }

  # The pool's own host SG only. There is no base security group to layer on:
  # the pool is a tenant of the network module, which owns no per-workload SG,
  # so everything a host may send or receive is stated in security_groups.tf.
  vpc_security_group_ids = [aws_security_group.host.id]

  # The setting that makes this a KVM host: without it /dev/kvm does not exist
  # and the CPU shows no vmx flag, whatever the instance size. Opt-in per
  # instance and only on 8th-gen Intel (c8i/m8i/r8i and flex variants).
  cpu_options {
    nested_virtualization = var.nested_virtualization
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
    # 1 hop: only a process on the host itself. Guests see their own MMDS at
    # 169.254.169.254, so the real IMDS is unreachable from a sandbox by
    # construction — this keeps it unreachable from anything else too.
    http_put_response_hop_limit = 1
    # Lets the host agent read its own ravion:* tags without an EC2 API call
    # or the ec2:DescribeTags permission that would come with one.
    instance_metadata_tags = "enabled"
  }

  monitoring {
    enabled = true
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.root_volume_size_gb
      volume_type           = var.root_volume_type
      encrypted             = true
      delete_on_termination = true
    }
  }

  # Chunk cache: XFS with reflink, holding snapshot chunks, reflinked rootfs
  # copies and jailer chroots. Pure cache of the S3 chunk store, so it dies
  # with the host and nothing is lost but warmth.
  block_device_mappings {
    device_name = var.cache_volume_device_name

    ebs {
      volume_size           = var.cache_volume_size_gb
      volume_type           = "gp3"
      iops                  = var.cache_volume_iops
      throughput            = var.cache_volume_throughput
      encrypted             = true
      delete_on_termination = true
    }
  }

  user_data = base64encode(templatefile("${path.module}/templates/user-data.sh.tpl", {
    pool_id           = var.pool_id
    env_slug          = var.env_slug
    region            = local.region
    ssm_param_prefix  = local.ssm_param_prefix
    snapshots_bucket  = aws_s3_bucket.snapshots.bucket
    proxy_port        = var.proxy_port
    network_mode      = var.network_mode
    ipv6_enabled      = var.ipv6_enabled
    private_zone_id   = aws_route53_zone.private.zone_id
    private_zone_name = local.private_zone
    # Empty on a pool with no ingress, which is how the host agent knows not to
    # register with a load balancer and how it refuses `expose-port` instead of
    # publishing a hostname that resolves to nothing.
    ingress_domain    = local.ingress_enabled ? local.ingress_domain : ""
    host_log_group    = local.host_log_group
    sandbox_log_group = local.sandbox_log_group
    cache_device      = var.cache_volume_device_name
    target_group_arn  = local.ingress_enabled ? aws_lb_target_group.proxy[0].arn : ""
    # Empty when TCP exposure is off or the pool has no ingress at all, which is
    # exactly how the host refuses a mode=tcp port request instead of publishing
    # one that answers nothing.
    tcp_target_group_arn = local.tcp_exposure_enabled ? aws_lb_target_group.tcp[0].arn : ""
    max_ip_prefixes      = var.max_ip_prefixes == null ? "" : tostring(var.max_ip_prefixes)
  }))

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.tags, { Name = "${local.name_prefix}-host" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(local.tags, { Name = "${local.name_prefix}-host" })
  }

  # The ENI tag is load-bearing, not decorative: it is what scopes the host
  # role's Assign/UnassignPrivateIpAddresses permission to this pool's ENIs.
  tag_specifications {
    resource_type = "network-interface"
    tags          = merge(local.tags, { Name = "${local.name_prefix}-host" })
  }

  tags = merge(local.tags, { Name = local.name_prefix })

  lifecycle {
    precondition {
      condition     = !local.vpc_ip_mode || length(var.private_subnet_ids) > 0
      error_message = "vpc-ip network mode requires at least one subnet with room for prefix delegation."
    }
  }
}
