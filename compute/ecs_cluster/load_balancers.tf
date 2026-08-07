################################################################################
# Public Application Load Balancers
################################################################################

module "public_alb" {
  count = length(var.public_albs)

  source = "../../networking/alb"

  name   = local.public_alb_names[count.index]
  tags   = var.tags
  vpc_id = var.vpc_id

  subnet_ids                     = var.public_subnet_ids
  internal_load_balancer_enabled = false

  # Listener configuration
  http_listener_enabled          = true
  https_listener_enabled         = var.public_albs[count.index].https_enabled
  http_to_https_redirect_enabled = var.public_albs[count.index].https_enabled

  # SSL/TLS
  certificate_arns = var.public_albs[count.index].certificate_arns
  ssl_policy       = var.public_albs[count.index].ssl_policy

  # ALB settings
  idle_timeout                = var.public_albs[count.index].idle_timeout
  deletion_protection_enabled = var.load_balancer_deletion_protection_enabled

  # Security
  ingress_cidr_blocks        = var.public_albs[count.index].ingress_cidr_blocks
  ingress_ipv6_cidr_blocks   = var.public_albs[count.index].ingress_ipv6_cidr_blocks
  ingress_security_group_ids = var.public_albs[count.index].ingress_security_group_ids

  # Access logs
  access_logs_enabled    = var.public_albs[count.index].access_logs_enabled
  access_logs_bucket_arn = var.public_albs[count.index].access_logs_bucket_arn

  # WAF
  web_acl_arn = var.public_albs[count.index].web_acl_arn
}

################################################################################
# Private Application Load Balancers
################################################################################

module "private_alb" {
  count = length(var.private_albs)

  source = "../../networking/alb"

  name   = local.private_alb_names[count.index]
  tags   = var.tags
  vpc_id = var.vpc_id

  subnet_ids                     = var.private_subnet_ids
  internal_load_balancer_enabled = true

  # Listener configuration
  http_listener_enabled          = true
  https_listener_enabled         = var.private_albs[count.index].https_enabled
  http_to_https_redirect_enabled = var.private_albs[count.index].https_enabled

  # SSL/TLS
  certificate_arns = var.private_albs[count.index].certificate_arns
  ssl_policy       = var.private_albs[count.index].ssl_policy

  # ALB settings
  idle_timeout                = var.private_albs[count.index].idle_timeout
  deletion_protection_enabled = var.load_balancer_deletion_protection_enabled

  # Security
  ingress_cidr_blocks        = var.private_albs[count.index].ingress_cidr_blocks
  ingress_ipv6_cidr_blocks   = var.private_albs[count.index].ingress_ipv6_cidr_blocks
  ingress_security_group_ids = var.private_albs[count.index].ingress_security_group_ids

  # Access logs
  access_logs_enabled    = var.private_albs[count.index].access_logs_enabled
  access_logs_bucket_arn = var.private_albs[count.index].access_logs_bucket_arn
}

################################################################################
# Public Network Load Balancers
################################################################################

module "public_nlb" {
  count = length(var.public_nlbs)

  source = "../../networking/nlb"

  name   = local.public_nlb_names[count.index]
  tags   = var.tags
  vpc_id = var.vpc_id

  subnet_ids                     = var.public_subnet_ids
  internal_load_balancer_enabled = false

  # NLB settings
  deletion_protection_enabled       = var.load_balancer_deletion_protection_enabled
  cross_zone_load_balancing_enabled = var.public_nlbs[count.index].cross_zone_load_balancing_enabled

  # Security groups
  additional_security_group_ids = var.public_nlbs[count.index].security_group_ids

  # Access logs
  access_logs_enabled    = var.public_nlbs[count.index].access_logs_enabled
  access_logs_bucket_arn = var.public_nlbs[count.index].access_logs_bucket_arn

  # Elastic IPs
  elastic_ips_enabled       = var.public_nlbs[count.index].elastic_ips_enabled
  elastic_ip_allocation_ids = var.public_nlbs[count.index].elastic_ip_allocation_ids
}

################################################################################
# Private Network Load Balancers
################################################################################

module "private_nlb" {
  count = length(var.private_nlbs)

  source = "../../networking/nlb"

  name   = local.private_nlb_names[count.index]
  tags   = var.tags
  vpc_id = var.vpc_id

  subnet_ids                     = var.private_subnet_ids
  internal_load_balancer_enabled = true

  # NLB settings
  deletion_protection_enabled       = var.load_balancer_deletion_protection_enabled
  cross_zone_load_balancing_enabled = var.private_nlbs[count.index].cross_zone_load_balancing_enabled

  # Security groups
  additional_security_group_ids = var.private_nlbs[count.index].security_group_ids

  # Access logs
  access_logs_enabled    = var.private_nlbs[count.index].access_logs_enabled
  access_logs_bucket_arn = var.private_nlbs[count.index].access_logs_bucket_arn

  # Elastic IPs
  elastic_ips_enabled       = var.private_nlbs[count.index].elastic_ips_enabled
  elastic_ip_allocation_ids = var.private_nlbs[count.index].elastic_ip_allocation_ids
}
