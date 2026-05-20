################################################################################
# Ravion domain control plane — cluster wildcard
#
# Allocates `*.<cluster-fqdn>` under Ravion's apex (e.g. `*.<name>-<hash>.ravion.app`)
# and issues a wildcard ACM cert covering it. Service modules under this
# cluster create child allocations whose FQDNs sit under <cluster-fqdn>,
# so they inherit the wildcard cert via SNI without their own ACM work.
#
# Resources (per the DI design in
# packages/shared-go/domain/domains/DOMAIN_CONTROL_PLANE_DI_DESIGN.md):
#
#   ravion_domain.cluster             — allocates the wildcard FQDN
#   aws_acm_certificate.cluster       — issues the cert (customer's AWS account)
#   ravion_dns_records.cluster_*      — writes the validation + apex routing
#                                        records into Ravion's Route53 (the
#                                        api-go's RavionRoute53Writer)
#   aws_acm_certificate_validation    — blocks ~30s until ACM verifies
#   ravion_managed_certificate.cluster — registers cert metadata at Ravion
#                                        for the UI badge
#
# All AWS resources live in the customer's account, applied by their TF
# runner with their IAM. Ravion never holds customer credentials.
################################################################################

# 1. Allocate the cluster's wildcard FQDN.
#    The local.enable_ravion_domain gate lives in locals.tf next to the
#    ALB-cert-source toggle since both branches need to agree.
resource "ravion_domain" "cluster" {
  count       = local.enable_ravion_domain ? 1 : 0
  dns_zone_id = var.ravion_dns_zone_id
  slug        = coalesce(var.ravion_cluster_slug, var.name)
  wildcard    = true
}

# 2. ACM wildcard cert. Lives in the customer's AWS account.
resource "aws_acm_certificate" "cluster" {
  count = local.enable_ravion_domain ? 1 : 0

  domain_name       = ravion_domain.cluster[0].fqdn
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = var.tags
}

# 3. Validation CNAME(s) into Ravion's Route53. Synchronous — the
# RavionRoute53Writer issues a Route53 ChangeResourceRecordSets call
# inline with our POST and returns when AWS accepts the change.
resource "ravion_dns_records" "cluster_validation" {
  count             = local.enable_ravion_domain ? 1 : 0
  managed_domain_id = ravion_domain.cluster[0].id
  records = [
    for opt in aws_acm_certificate.cluster[0].domain_validation_options : {
      name  = opt.resource_record_name
      type  = opt.resource_record_type
      value = opt.resource_record_value
      ttl   = 60
    }
  ]
}

# 4. Apex routing record — wildcard FQDN points at the cluster's public ALB.
#    Uses ALIAS so apex-style routing works (Route53 expands to A + AliasTarget).
resource "ravion_dns_records" "cluster_routing" {
  count             = local.enable_ravion_domain && var.enable_public_alb ? 1 : 0
  managed_domain_id = ravion_domain.cluster[0].id
  records = [{
    name = ravion_domain.cluster[0].fqdn
    type = "ALIAS"
    value = jsonencode({
      dns_name = module.public_alb[0].alb_dns_name
      zone_id  = module.public_alb[0].alb_zone_id
    })
  }]
}

# 5. Block until ACM has validated the cert. With Ravion's Route53 zone
# under our IAM, the validation CNAME goes live in seconds — this step
# typically completes in well under 60s.
resource "aws_acm_certificate_validation" "cluster" {
  count                   = local.enable_ravion_domain ? 1 : 0
  certificate_arn         = aws_acm_certificate.cluster[0].arn
  validation_record_fqdns = ravion_dns_records.cluster_validation[0].fqdns
}

# 6. Tell Ravion about the cert so the UI shows the cert badge on the
# cluster's domain row.
resource "ravion_managed_certificate" "cluster" {
  count              = local.enable_ravion_domain ? 1 : 0
  cert_arn           = aws_acm_certificate_validation.cluster[0].certificate_arn
  status             = "ISSUED"
  scope              = "CLUSTER_WILDCARD"
  managed_domain_ids = [ravion_domain.cluster[0].managed_domain_id]
}
