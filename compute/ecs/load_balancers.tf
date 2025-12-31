################################################################################
# Public Application Load Balancer
################################################################################

module "public_alb" {
  count = var.enable_public_alb ? 1 : 0

  source = "../../networking/alb"

  name   = "${var.name}-public"
  tags   = var.tags
  vpc_id = var.vpc_id

  subnet_ids = var.public_subnet_ids
  internal   = false

  # Listener configuration
  enable_http_listener   = true
  enable_https_listener  = var.public_alb_enable_https
  http_to_https_redirect = var.public_alb_enable_https

  # SSL/TLS
  certificate_arn = var.public_alb_certificate_arn
  ssl_policy      = var.public_alb_ssl_policy

  # ALB settings
  idle_timeout               = var.public_alb_idle_timeout
  enable_deletion_protection = var.public_alb_enable_deletion_protection

  # Security
  ingress_cidr_blocks = var.public_alb_ingress_cidr_blocks

  # Access logs
  enable_access_logs     = var.public_alb_enable_access_logs
  access_logs_bucket_arn = var.public_alb_access_logs_bucket_arn

  # WAF
  web_acl_arn = var.public_alb_web_acl_arn
}

################################################################################
# Private Application Load Balancer
################################################################################

module "private_alb" {
  count = var.enable_private_alb ? 1 : 0

  source = "../../networking/alb"

  name   = "${var.name}-private"
  tags   = var.tags
  vpc_id = var.vpc_id

  subnet_ids = var.private_subnet_ids
  internal   = true

  # Listener configuration
  enable_http_listener   = true
  enable_https_listener  = var.private_alb_enable_https
  http_to_https_redirect = var.private_alb_enable_https

  # SSL/TLS
  certificate_arn = var.private_alb_certificate_arn
  ssl_policy      = var.private_alb_ssl_policy

  # ALB settings
  idle_timeout               = var.private_alb_idle_timeout
  enable_deletion_protection = var.private_alb_enable_deletion_protection

  # Security
  ingress_cidr_blocks = var.private_alb_ingress_cidr_blocks

  # Access logs
  enable_access_logs     = var.private_alb_enable_access_logs
  access_logs_bucket_arn = var.private_alb_access_logs_bucket_arn
}

