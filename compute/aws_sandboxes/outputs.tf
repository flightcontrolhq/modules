################################################################################
# Outputs
#
# Exactly the surface Tower reads back into SandboxPool's module-output cache.
# Nothing here is sensitive: the module system drops sensitive outputs before
# they reach Stack.output, so an output marked sensitive would simply vanish.
################################################################################

output "launch_template_id" {
  description = "Launch template the reconciler launches hosts from."
  value       = aws_launch_template.host.id
}

output "launch_template_latest_version" {
  description = "Latest launch-template version. A change here is what a host rollout rolls to."
  value       = aws_launch_template.host.latest_version
}

output "subnet_ids" {
  description = "Subnets hosts are launched into."
  value       = var.private_subnet_ids
}

output "host_sg_id" {
  description = "Pool host security group. Self-contained: it is the only SG a host carries."
  value       = aws_security_group.host.id
}

output "instance_profile_arn" {
  description = "Instance profile every host boots with."
  value       = aws_iam_instance_profile.host.arn
}

output "snapshots_bucket" {
  description = "Snapshot chunk store bucket name."
  value       = aws_s3_bucket.snapshots.bucket
}

output "ingress_enabled" {
  description = "Whether this pool has a public ingress path at all. False means no NLB, no certificate and no wildcard DNS: sandboxes run, but no port can be published and every ingress output below is null or empty."
  value       = local.ingress_enabled
}

output "nlb_target_group_arn" {
  description = "Instance target group for the host ingress proxy. Hosts are registered on ready and deregistered on cordon. Null when the pool has no ingress."
  value       = one(aws_lb_target_group.proxy[*].arn)
}

output "nlb_ip_target_group_arn" {
  description = "IP target group for raw TCP exposure of sandbox IPs. Null when tcp exposure is disabled or the pool has no ingress."
  value       = one(aws_lb_target_group.tcp[*].arn)
}

output "nlb_dns_name" {
  description = "NLB DNS name, for an external zone's CNAME or for direct use. Null when the pool has no ingress."
  value       = one(aws_lb.this[*].dns_name)
}

output "nlb_arn" {
  description = "ARN of the ingress NLB. Null when the pool has no ingress."
  value       = one(aws_lb.this[*].arn)
}

output "certificate_arn" {
  description = "ARN of the wildcard certificate covering every sandbox hostname. Null when the pool has no ingress."
  value       = one(aws_acm_certificate.wildcard[*].arn)
}

output "ingress_domain" {
  description = "Zone sandbox hostnames live under: <sandboxId>-<port>.<ingress_domain>. Null when the pool has no ingress."
  value       = local.ingress_domain
}

output "private_zone_id" {
  description = "Private hosted zone that carries per-sandbox records in vpc-ip mode."
  value       = aws_route53_zone.private.zone_id
}

output "ssm_param_prefix" {
  description = "Prefix the reconciler writes per-host M2M credentials under; the host role can read only within it."
  value       = local.ssm_param_prefix
}

output "acm_validation_records" {
  description = "DNS records that validate the wildcard certificate. Already created when ingress.hosted_zone_id is set; otherwise these are what an operator must add to an externally hosted zone. Empty when the pool has no ingress."
  value = [
    for dvo in local.acm_validation_options : {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  ]
}

output "private_zone_name" {
  description = "Private hosted zone NAME (not id). The host writes <sandboxId>.<private_zone_name> records under it, and the control plane returns that name to callers; deriving it from env_slug and the ingress domain is wrong the moment private_zone_name is set."
  value       = local.private_zone
}
