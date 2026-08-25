################################################################################
# Public ingress record
#
# One wildcard alias for the whole pool. Sandbox hostnames are created and
# destroyed far too fast to be DNS records; the proxy resolves them in process.
################################################################################

resource "aws_route53_record" "wildcard" {
  count = local.create_dns ? 1 : 0

  zone_id = var.ingress.hosted_zone_id
  name    = local.wildcard_domain
  type    = "A"

  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "wildcard_ipv6" {
  count = local.create_dns && var.ipv6_enabled ? 1 : 0

  zone_id = var.ingress.hosted_zone_id
  name    = local.wildcard_domain
  type    = "AAAA"

  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = false
  }
}

################################################################################
# Private zone
#
# `<sandboxId>.sbx.<env>.internal` → the sandbox's own VPC IP, written on create
# and removed on stop by the host agent (through the broker). This is what makes
# a sandbox reachable from in-VPC, VPN and peered clients on any port with stock
# tools, without the NLB in the path.
################################################################################

resource "aws_route53_zone" "private" {
  name          = local.private_zone
  comment       = "Sandbox pool ${var.pool_id} — per-sandbox records"
  force_destroy = true

  vpc {
    vpc_id = var.vpc_id
  }

  tags = merge(local.tags, { Name = local.private_zone })

  # Records inside are written at runtime, never by Terraform, so the VPC
  # association list must not fight with anything the control plane adds.
  lifecycle {
    ignore_changes = [vpc]
  }
}
