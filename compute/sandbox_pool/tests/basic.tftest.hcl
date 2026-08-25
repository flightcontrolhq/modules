# Basic sandbox-pool Module Tests
# Run with: tofu test

# Mock AWS provider with overridden data sources
mock_provider "aws" {
  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "123456789012"
    }
  }

  override_data {
    target = data.aws_region.current
    values = {
      id     = "us-east-1"
      name   = "us-east-1"
      region = "us-east-1"
    }
  }

  override_data {
    target = data.aws_partition.current
    values = {
      partition = "aws"
    }
  }

  override_data {
    target = data.aws_route_tables.vpc
    values = {
      ids = ["rtb-1234567890abcdef0"]
    }
  }

  # Resources that need valid ARNs or stable ids
  override_resource {
    target = aws_iam_role.host
    values = {
      arn = "arn:aws:iam::123456789012:role/rvn-sbx-pool1-host"
    }
  }

  override_resource {
    target = aws_iam_instance_profile.host
    values = {
      arn = "arn:aws:iam::123456789012:instance-profile/rvn-sbx-pool1-host"
    }
  }

  override_resource {
    target = aws_s3_bucket.snapshots
    values = {
      arn = "arn:aws:s3:::rvn-sbx-prod-snapshots-123456789012"
      id  = "rvn-sbx-prod-snapshots-123456789012"
    }
  }

  override_resource {
    target = aws_cloudwatch_log_group.host
    values = {
      arn = "arn:aws:logs:us-east-1:123456789012:log-group:/ravion/sandboxes/pool1/host"
    }
  }

  override_resource {
    target = aws_cloudwatch_log_group.sandbox
    values = {
      arn = "arn:aws:logs:us-east-1:123456789012:log-group:/ravion/sandboxes/pool1/sandbox"
    }
  }

  override_resource {
    target = aws_security_group.host
    values = {
      id  = "sg-0host000000000000"
      arn = "arn:aws:ec2:us-east-1:123456789012:security-group/sg-0host000000000000"
    }
  }

  override_resource {
    target = aws_security_group.nlb
    values = {
      id  = "sg-0nlb0000000000000"
      arn = "arn:aws:ec2:us-east-1:123456789012:security-group/sg-0nlb0000000000000"
    }
  }

  override_resource {
    target = aws_lb.this
    values = {
      arn      = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/net/rvn-sbx-pool1/1234567890123456"
      dns_name = "rvn-sbx-pool1-1234567890.elb.us-east-1.amazonaws.com"
      zone_id  = "Z26RNL4JYFTOTI"
    }
  }

  override_resource {
    target = aws_lb_target_group.proxy
    values = {
      arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/rvn-sbx-pool1-tg/1234567890123456"
    }
  }

  override_resource {
    target = aws_lb_target_group.tcp
    values = {
      arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/rvn-sbx-pool1-ip/6543210987654321"
    }
  }

  override_resource {
    target = aws_acm_certificate.wildcard
    values = {
      arn = "arn:aws:acm:us-east-1:123456789012:certificate/11111111-2222-3333-4444-555555555555"
      domain_validation_options = [{
        domain_name           = "*.sbx.prod.example.com"
        resource_record_name  = "_acme.sbx.prod.example.com."
        resource_record_type  = "CNAME"
        resource_record_value = "_validation.acm-validations.aws."
      }]
    }
  }

  override_resource {
    target = aws_route53_zone.private
    values = {
      zone_id = "Z0PRIVATE0000000000"
    }
  }

  override_resource {
    target = aws_launch_template.host
    values = {
      id             = "lt-0123456789abcdef0"
      arn            = "arn:aws:ec2:us-east-1:123456789012:launch-template/lt-0123456789abcdef0"
      latest_version = 1
    }
  }
}

variables {
  pool_id  = "pool1"
  env_slug = "prod"

  execution_environment = {
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-12345678", "subnet-87654321"]
    security_group_id = "sg-0exec00000000000"
  }

  host_ami_id = "ami-0123456789abcdef0"

  ingress = {
    domain         = "example.com"
    hosted_zone_id = "Z0PUBLIC00000000000"
  }
}

# Test 1: defaults — vpc-ip mode, owned zone, endpoints on
run "defaults" {
  command = plan

  assert {
    condition     = aws_launch_template.host.cpu_options[0].nested_virtualization == "enabled"
    error_message = "Hosts must be launched with nested virtualization enabled or /dev/kvm will not exist."
  }

  assert {
    condition     = aws_launch_template.host.metadata_options[0].http_tokens == "required"
    error_message = "IMDSv2 must be required on sandbox hosts."
  }

  assert {
    condition     = aws_launch_template.host.metadata_options[0].http_put_response_hop_limit == 1
    error_message = "The IMDS hop limit must be 1 so nothing but a host process can reach it."
  }

  assert {
    condition     = aws_launch_template.host.instance_type == "m8i.2xlarge"
    error_message = "The launch template must pin the first entry of host_instance_types."
  }

  assert {
    condition     = length(aws_launch_template.host.block_device_mappings) == 2
    error_message = "Hosts need a root volume and a chunk-cache volume."
  }

  assert {
    condition     = aws_lb.this.load_balancer_type == "network"
    error_message = "Sandbox ingress must be an NLB."
  }

  assert {
    condition     = aws_lb.this.internal == false
    error_message = "ingress.internet_facing defaults to true, so the NLB must not be internal."
  }

  assert {
    condition     = aws_lb_listener.https.port == 443 && aws_lb_listener.https.protocol == "TLS"
    error_message = "The pool must terminate TLS on 443."
  }

  assert {
    condition     = aws_lb_target_group.proxy.port == 8443 && aws_lb_target_group.proxy.target_type == "instance"
    error_message = "The proxy target group must be an instance group on the proxy port."
  }

  assert {
    condition     = length(aws_lb_target_group.tcp) == 1 && aws_lb_target_group.tcp[0].target_type == "ip"
    error_message = "TCP exposure requires an IP target group."
  }

  assert {
    condition     = aws_acm_certificate.wildcard.domain_name == "*.sbx.prod.example.com"
    error_message = "The wildcard certificate must cover every sandbox hostname in the pool."
  }

  assert {
    condition     = aws_route53_zone.private.name == "sbx.prod.internal"
    error_message = "The private zone must default to sbx.<env>.internal."
  }

  assert {
    condition     = anytrue([for v in aws_route53_zone.private.vpc : v.vpc_id == "vpc-12345678"])
    error_message = "The private zone must be associated with the execution environment's VPC."
  }

  assert {
    condition     = output.snapshots_bucket == "rvn-sbx-prod-snapshots-123456789012"
    error_message = "The snapshots bucket name must be derived from the env slug and account."
  }

  assert {
    condition     = aws_s3_bucket_versioning.snapshots.versioning_configuration[0].status == "Disabled"
    error_message = "Content-addressed chunks must not be versioned."
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.snapshots.rule[0].expiration[0].days == 30
    error_message = "Unpinned snapshots must expire at snapshot_retention_days."
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.snapshots.rule[0].filter[0].tag[0].key == "ravion:pinned"
    error_message = "Snapshot expiry must be tag-filtered so pinned objects are exempt."
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.snapshots.block_public_acls
    error_message = "The snapshots bucket must block public access."
  }

  assert {
    condition     = aws_cloudwatch_log_group.host.name == "/ravion/sandboxes/pool1/host"
    error_message = "The host log group must follow the /ravion/sandboxes/<pool>/host convention."
  }

  assert {
    condition     = aws_cloudwatch_log_group.sandbox.name == "/ravion/sandboxes/pool1/sandbox"
    error_message = "The sandbox log group must follow the /ravion/sandboxes/<pool>/sandbox convention."
  }

  assert {
    condition     = length(aws_vpc_endpoint.s3) == 1 && length(aws_vpc_endpoint.interface) == 4
    error_message = "create_vpc_endpoints must produce the S3 gateway plus ssm, ssmmessages, ecr.api and ecr.dkr."
  }

  assert {
    condition     = length(aws_route53_record.wildcard) == 1
    error_message = "A hosted zone id must produce the wildcard alias record."
  }

  assert {
    condition     = length(aws_route53_record.acm_validation) == 1
    error_message = "A hosted zone id must produce the certificate validation records."
  }

  assert {
    condition     = output.ingress_domain == "sbx.prod.example.com"
    error_message = "Sandbox hostnames live under sbx.<env>.<domain>."
  }

  assert {
    condition     = output.ssm_param_prefix == "/ravion/sandboxes/pool1/hosts"
    error_message = "The SSM prefix must match the path the reconciler writes host credentials to."
  }

  assert {
    condition     = output.nlb_ip_target_group_arn != null
    error_message = "The IP target group ARN must be exported when tcp exposure is on."
  }

  assert {
    condition     = length(output.acm_validation_records) == 1
    error_message = "Certificate validation records must always be exported."
  }

  assert {
    condition     = output.private_zone_name == "sbx.prod.internal"
    error_message = "The private zone NAME must be exported, not only its id: the control plane must never derive it."
  }

  assert {
    condition     = output.private_zone_name == aws_route53_zone.private.name
    error_message = "The exported private zone name must be the zone that was actually created."
  }

  # The host reads its whole pool configuration from this file. A key that is
  # not rendered is a subsystem that silently does nothing.
  assert {
    condition = alltrue([
      for key in [
        "RAVION_TCP_TARGET_GROUP_ARN",
        "RAVION_DNS_RESOLVER_ADDR",
        "RAVION_UPLINK_IFACE",
        "RAVION_INSTANCE_TYPE",
        "RAVION_MAX_IP_PREFIXES",
      ] : strcontains(base64decode(aws_launch_template.host.user_data), "${key}=")
    ])
    error_message = "User data must render every env key the host agent's networking reads."
  }

  assert {
    condition     = strcontains(base64decode(aws_launch_template.host.user_data), "RAVION_TCP_TARGET_GROUP_ARN=${aws_lb_target_group.tcp[0].arn}")
    error_message = "With tcp exposure on, the IP target group ARN must reach the host."
  }

  assert {
    condition     = strcontains(base64decode(aws_launch_template.host.user_data), "RAVION_MAX_IP_PREFIXES=\n")
    error_message = "An unset max_ip_prefixes must render empty, meaning the instance type's own limit."
  }
}

# Test 2: vpc-ip mode grants ENI address management, scoped to the pool's ENIs
run "vpc_ip_mode" {
  command = plan

  variables {
    network_mode = "vpc-ip"
    ipv6_enabled = true
  }

  assert {
    condition     = strcontains(aws_iam_role_policy.host_vpc_ip[0].policy, "ec2:DescribeSubnets")
    error_message = "vpc-ip hosts must be able to read the subnet mask and gateway they hand to guests."
  }

  assert {
    condition     = length(aws_iam_role_policy.host_vpc_ip) == 1
    error_message = "vpc-ip mode must attach the ENI address-management policy."
  }

  assert {
    condition     = strcontains(aws_iam_role_policy.host_vpc_ip[0].policy, "ec2:AssignPrivateIpAddresses")
    error_message = "vpc-ip mode must allow assigning private IPs to host ENIs."
  }

  assert {
    condition     = strcontains(aws_iam_role_policy.host_vpc_ip[0].policy, "ec2:AssignIpv6Addresses")
    error_message = "ipv6_enabled must add the IPv6 address actions."
  }

  assert {
    condition     = strcontains(aws_iam_role_policy.host_vpc_ip[0].policy, "ec2:ResourceTag/ravion:pool")
    error_message = "ENI permissions must be scoped by the ravion:pool tag."
  }

  assert {
    condition     = strcontains(aws_iam_role_policy.host_vpc_ip[0].policy, "ec2:SourceInstanceARN")
    error_message = "ENI permissions must only work from EC2 instance credentials."
  }

  assert {
    condition = anytrue([
      for ts in aws_launch_template.host.tag_specifications :
      ts.resource_type == "network-interface" && lookup(ts.tags, "ravion:pool", "") == "pool1"
    ])
    error_message = "The launch template must tag ENIs with ravion:pool, which is what the IAM condition keys on."
  }

  assert {
    condition     = aws_lb.this.ip_address_type == "dualstack"
    error_message = "ipv6_enabled must make the NLB dualstack."
  }

  assert {
    condition     = length(aws_route53_record.wildcard_ipv6) == 1
    error_message = "ipv6_enabled must add the AAAA ingress record."
  }
}

# Test 3: nat mode drops the ENI permissions entirely
run "nat_mode" {
  command = plan

  variables {
    network_mode          = "nat"
    internal_access_cidrs = ["10.0.0.0/8"]
  }

  assert {
    condition     = length(aws_iam_role_policy.host_vpc_ip) == 0
    error_message = "nat mode must not grant ENI address management."
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.host_internal) == 0
    error_message = "Direct in-VPC sandbox access is a vpc-ip-mode feature only."
  }

  assert {
    condition     = aws_route53_zone.private.name == "sbx.prod.internal"
    error_message = "The private zone exists in both modes; only its records are mode-specific."
  }
}

# Test 4: internal pool, external DNS zone, no endpoints
run "internal_external_zone" {
  command = plan

  variables {
    ingress = {
      domain          = "example.com"
      internet_facing = false
      allowed_cidrs   = ["10.0.0.0/8"]
    }
    create_vpc_endpoints = false
    private_zone_name    = "sbx.internal.example"
  }

  assert {
    condition     = aws_lb.this.internal == true
    error_message = "internet_facing = false must produce an internal NLB."
  }

  assert {
    condition     = length(aws_route53_record.acm_validation) == 0
    error_message = "Without a hosted zone id the module must not try to write validation records."
  }

  assert {
    condition     = length(aws_route53_record.wildcard) == 0
    error_message = "Without a hosted zone id there is no alias record to write."
  }

  assert {
    condition     = length(output.acm_validation_records) == 1
    error_message = "With an external zone the validation records are the whole point of the output."
  }

  assert {
    condition     = length(aws_vpc_endpoint.interface) == 0 && length(aws_vpc_endpoint.s3) == 0
    error_message = "create_vpc_endpoints = false must create no endpoints."
  }

  assert {
    condition     = aws_route53_zone.private.name == "sbx.internal.example"
    error_message = "private_zone_name must override the default."
  }

  assert {
    condition     = output.private_zone_name == "sbx.internal.example"
    error_message = "The exported private zone name must follow the override; this is the case a derived name gets wrong."
  }

}

# Test 4b: tcp exposure off means the host is told there is no target group,
# which is how it refuses mode=tcp rather than publishing a port that answers
# nothing.
run "tcp_exposure_disabled" {
  command = plan

  variables {
    enable_tcp_exposure = false
  }

  assert {
    condition     = output.nlb_ip_target_group_arn == null
    error_message = "With tcp exposure off there is no IP target group to export."
  }

  assert {
    condition     = strcontains(base64decode(aws_launch_template.host.user_data), "RAVION_TCP_TARGET_GROUP_ARN=\n")
    error_message = "With tcp exposure off the ARN must be rendered empty."
  }
}

# Test 5: the host role's grants stay inside the pool
run "host_policy_scoping" {
  command = plan

  assert {
    condition     = strcontains(aws_iam_role_policy.host.policy, "parameter/ravion/sandboxes/pool1/hosts/*")
    error_message = "SSM reads must be confined to this pool's host credential prefix."
  }

  assert {
    condition     = strcontains(aws_iam_role_policy.host.policy, "ec2:SourceInstanceARN")
    error_message = "The host credential grant must require EC2 instance credentials."
  }

  # SBX-04. The pool prefix alone lets any host in the pool read any other
  # host's WorkOS M2M pair. What narrows it to one parameter is the tag
  # condition: the reconciler tags each parameter with the ARN of the single
  # instance allowed to read it, and the grant compares that tag against the
  # calling instance's ARN.
  assert {
    condition     = strcontains(aws_iam_role_policy.host.policy, "\"ssm:ResourceTag/ravion:instance-arn\":\"$${ec2:SourceInstanceARN}\"")
    error_message = "The host credential grant must be scoped to the calling instance by resource tag, not just to the pool."
  }

  # GetParameters (plural) and every path-enumerating call stay off the host.
  assert {
    condition     = !strcontains(aws_iam_role_policy.host.policy, "ssm:GetParameters") && !strcontains(aws_iam_role_policy.host.policy, "ssm:DescribeParameters")
    error_message = "The host may only read one parameter at a time, by name."
  }

  assert {
    condition     = strcontains(aws_iam_role_policy.host.policy, "ecr-public:GetAuthorizationToken") && strcontains(aws_iam_role_policy.host.policy, "sts:GetServiceBearerToken")
    error_message = "Hosts must be able to authenticate to public ECR for base images."
  }

  assert {
    condition     = strcontains(aws_iam_role_policy.host.policy, "kms:ViaService")
    error_message = "SecureString decryption must be pinned to SSM as the calling service."
  }

  assert {
    condition     = !strcontains(aws_iam_role_policy.host.policy, "\"s3:*\"")
    error_message = "The host must not hold wildcard S3 permissions."
  }

  assert {
    condition     = strcontains(aws_s3_bucket_policy.snapshots.policy, "DenyInsecureTransport")
    error_message = "The snapshots bucket must refuse plaintext transport."
  }
}

# Test 6: a pool id longer than a load balancer name folds deterministically
run "long_pool_id" {
  command = plan

  variables {
    pool_id = "clz9x8y7w6v5u4t3s2r1q0p9o8n7m6"
  }

  assert {
    condition     = length(aws_lb.this.name) <= 32
    error_message = "The NLB name must fit AWS's 32-character limit for any pool id."
  }

  assert {
    condition     = length(aws_lb_target_group.proxy.name) <= 32
    error_message = "The target group name must fit AWS's 32-character limit for any pool id."
  }

  assert {
    condition     = output.ssm_param_prefix == "/ravion/sandboxes/clz9x8y7w6v5u4t3s2r1q0p9o8n7m6/hosts"
    error_message = "The SSM prefix must use the full pool id, not the shortened resource-name stem."
  }
}

# Test 7: a real Ravion pool id (`sbxp_<ksuid>`) is accepted verbatim.
#
# pool_id IS the SandboxPool row id: the reconciler lists the fleet with
# `tag:ravion:pool = <row id>` and builds each host's SSM parameter path from
# the same string, so anything the module did to the value here would silently
# hide every host from Tower. Resource names are the only place it is folded,
# because load balancers and IAM do not accept underscores or uppercase.
run "ravion_pool_id" {
  command = plan

  variables {
    pool_id = "sbxp_2ZxKq7WcB3nR8vLmA1sPdT4eYuG"
  }

  assert {
    condition     = local.tags["ravion:pool"] == "sbxp_2ZxKq7WcB3nR8vLmA1sPdT4eYuG"
    error_message = "The ravion:pool tag must carry the pool id verbatim — Tower filters the fleet on it."
  }

  assert {
    condition     = output.ssm_param_prefix == "/ravion/sandboxes/sbxp_2ZxKq7WcB3nR8vLmA1sPdT4eYuG/hosts"
    error_message = "The SSM prefix must use the verbatim pool id, which is how Tower builds each host's parameter path."
  }

  assert {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*$", aws_lb.this.name)) && length(aws_lb.this.name) <= 32
    error_message = "The NLB name must be lowercase alphanumerics and hyphens within 32 characters."
  }

  assert {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*$", aws_lb_target_group.proxy.name)) && length(aws_lb_target_group.proxy.name) <= 32
    error_message = "The target group name must be lowercase alphanumerics and hyphens within 32 characters."
  }
}
