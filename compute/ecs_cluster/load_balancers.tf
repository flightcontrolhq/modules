################################################################################
# Public Application Load Balancer
################################################################################

module "public_alb" {
  count = var.enable_public_alb ? 1 : 0

  source = "../../networking/alb"

  name   = "${var.name}-pub"
  tags   = var.tags
  vpc_id = var.vpc_id

  subnet_ids = var.public_subnet_ids
  internal   = false

  # Listener configuration
  # When Ravion-managed domains are on, HTTPS + redirect are forced on; the
  # alb module derives the default cert from Ravion's cluster cert.
  enable_http_listener   = true
  enable_https_listener  = var.public_alb_enable_https || var.use_ravion_managed_domains
  http_to_https_redirect = var.public_alb_enable_https || var.use_ravion_managed_domains

  # SSL/TLS — index 0 is ignored when use_ravion_managed_domains = true; any
  # additional ARNs still attach as SNI certs.
  certificate_arns = var.public_alb_certificate_arns
  ssl_policy       = var.public_alb_ssl_policy

  # ALB settings
  idle_timeout        = var.public_alb_idle_timeout
  deletion_protection = var.deletion_protection

  # Security
  ingress_cidr_blocks = var.public_alb_ingress_cidr_blocks

  # Access logs
  enable_access_logs     = var.public_alb_enable_access_logs
  access_logs_bucket_arn = var.public_alb_access_logs_bucket_arn

  # WAF
  web_acl_arn = var.public_alb_web_acl_arn

  # Ravion-managed domains (opt-in)
  use_ravion_managed_domains = var.use_ravion_managed_domains
  ravion_aws_account_id      = var.ravion_aws_account_id
  ravion_aws_region          = var.ravion_aws_region
  ravion_slot                = "public_alb"
  ravion_custom_domains      = var.ravion_custom_domains
}

################################################################################
# Private Application Load Balancer
################################################################################

module "private_alb" {
  count = var.enable_private_alb ? 1 : 0

  source = "../../networking/alb"

  name   = "${var.name}-priv"
  tags   = var.tags
  vpc_id = var.vpc_id

  subnet_ids = var.private_subnet_ids
  internal   = true

  # Listener configuration
  enable_http_listener   = true
  enable_https_listener  = var.private_alb_enable_https || var.use_ravion_managed_domains
  http_to_https_redirect = var.private_alb_enable_https || var.use_ravion_managed_domains

  # SSL/TLS — index 0 is ignored when use_ravion_managed_domains = true.
  certificate_arns = var.private_alb_certificate_arns
  ssl_policy       = var.private_alb_ssl_policy

  # ALB settings
  idle_timeout        = var.private_alb_idle_timeout
  deletion_protection = var.deletion_protection

  # Security
  ingress_cidr_blocks = var.private_alb_ingress_cidr_blocks

  # Access logs
  enable_access_logs     = var.private_alb_enable_access_logs
  access_logs_bucket_arn = var.private_alb_access_logs_bucket_arn

  # Ravion-managed domains (opt-in). Same toggle as the public ALB but with a
  # separate slot so both can coexist on the same module instance.
  use_ravion_managed_domains = var.use_ravion_managed_domains
  ravion_aws_account_id      = var.ravion_aws_account_id
  ravion_aws_region          = var.ravion_aws_region
  ravion_slot                = "private_alb"
  ravion_custom_domains      = var.ravion_custom_domains
}

################################################################################
# Public Network Load Balancer
################################################################################

module "public_nlb" {
  count = var.enable_public_nlb ? 1 : 0

  source = "../../networking/nlb"

  name   = "${var.name}-pub"
  tags   = var.tags
  vpc_id = var.vpc_id

  subnet_ids = var.public_subnet_ids
  internal   = false

  # NLB settings
  deletion_protection              = var.deletion_protection
  enable_cross_zone_load_balancing = var.public_nlb_enable_cross_zone_load_balancing

  # Security groups
  additional_security_group_ids = var.public_nlb_security_group_ids

  # Access logs
  enable_access_logs     = var.public_nlb_enable_access_logs
  access_logs_bucket_arn = var.public_nlb_access_logs_bucket_arn

  # Elastic IPs
  enable_elastic_ips        = var.public_nlb_enable_elastic_ips
  elastic_ip_allocation_ids = var.public_nlb_elastic_ip_allocation_ids
}

################################################################################
# Private Network Load Balancer
################################################################################

module "private_nlb" {
  count = var.enable_private_nlb ? 1 : 0

  source = "../../networking/nlb"

  name   = "${var.name}-priv"
  tags   = var.tags
  vpc_id = var.vpc_id

  subnet_ids = var.private_subnet_ids
  internal   = true

  # NLB settings
  deletion_protection              = var.deletion_protection
  enable_cross_zone_load_balancing = var.private_nlb_enable_cross_zone_load_balancing

  # Security groups
  additional_security_group_ids = var.private_nlb_security_group_ids

  # Access logs
  enable_access_logs     = var.private_nlb_enable_access_logs
  access_logs_bucket_arn = var.private_nlb_access_logs_bucket_arn

  # Elastic IPs
  enable_elastic_ips        = var.private_nlb_enable_elastic_ips
  elastic_ip_allocation_ids = var.private_nlb_elastic_ip_allocation_ids
}

