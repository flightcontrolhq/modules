################################################################################
# Public Application Load Balancer
################################################################################

check "public_alb_subnet_requirement" {
  assert {
    condition     = !var.enable_public_alb || length(var.public_subnet_ids) >= 2
    error_message = "At least 2 public_subnet_ids are required when enable_public_alb is true. ALBs require subnets in at least 2 availability zones for high availability."
  }
}

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

check "private_alb_subnet_requirement" {
  assert {
    condition     = !var.enable_private_alb || length(var.private_subnet_ids) >= 2
    error_message = "At least 2 private_subnet_ids are required when enable_private_alb is true. ALBs require subnets in at least 2 availability zones for high availability."
  }
}

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

################################################################################
# Public Network Load Balancer
################################################################################

check "public_nlb_subnet_requirement" {
  assert {
    condition     = !var.enable_public_nlb || length(var.public_subnet_ids) >= 1
    error_message = "At least 1 public_subnet_id is required when enable_public_nlb is true."
  }
}

module "public_nlb" {
  count = var.enable_public_nlb ? 1 : 0

  source = "../../networking/nlb"

  name   = "${var.name}-public"
  tags   = var.tags
  vpc_id = var.vpc_id

  subnet_ids = var.public_subnet_ids
  internal   = false

  # NLB settings
  enable_deletion_protection       = var.public_nlb_enable_deletion_protection
  enable_cross_zone_load_balancing = var.public_nlb_enable_cross_zone_load_balancing

  # Security groups
  security_group_ids = var.public_nlb_security_group_ids

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

check "private_nlb_subnet_requirement" {
  assert {
    condition     = !var.enable_private_nlb || length(var.private_subnet_ids) >= 1
    error_message = "At least 1 private_subnet_id is required when enable_private_nlb is true."
  }
}

module "private_nlb" {
  count = var.enable_private_nlb ? 1 : 0

  source = "../../networking/nlb"

  name   = "${var.name}-private"
  tags   = var.tags
  vpc_id = var.vpc_id

  subnet_ids = var.private_subnet_ids
  internal   = true

  # NLB settings
  enable_deletion_protection       = var.private_nlb_enable_deletion_protection
  enable_cross_zone_load_balancing = var.private_nlb_enable_cross_zone_load_balancing

  # Security groups
  security_group_ids = var.private_nlb_security_group_ids

  # Access logs
  enable_access_logs     = var.private_nlb_enable_access_logs
  access_logs_bucket_arn = var.private_nlb_access_logs_bucket_arn

  # Elastic IPs
  enable_elastic_ips        = var.private_nlb_enable_elastic_ips
  elastic_ip_allocation_ids = var.private_nlb_elastic_ip_allocation_ids
}

