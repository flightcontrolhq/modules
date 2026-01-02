# AWS Application Load Balancer

Creates an Application Load Balancer (ALB) with HTTP and HTTPS listeners, security group, optional access logging, and WAF integration.

This module creates the ALB infrastructure only. Target groups and listener rules are created by service modules (e.g., ECS) that register targets with the ALB.

## Usage

### Basic ALB (HTTP Only)

```hcl
module "alb" {
  source = "git::https://github.com/flightcontrolhq/modules.git//networking/alb?ref=v1.0.0"

  name       = "main"
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnet_ids

  tags = {
    Environment = "production"
  }
}
```

### ALB with HTTPS

To enable HTTPS, you must set `enable_https_listener = true` and provide a `certificate_arn`:

```hcl
module "alb" {
  source = "git::https://github.com/flightcontrolhq/modules.git//networking/alb?ref=v1.0.0"

  name       = "main"
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnet_ids

  enable_https_listener = true
  certificate_arn       = aws_acm_certificate.main.arn

  tags = {
    Environment = "production"
  }
}
```

### Internal ALB with HTTPS

```hcl
module "alb" {
  source = "git::https://github.com/flightcontrolhq/modules.git//networking/alb?ref=v1.0.0"

  name       = "internal"
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids
  internal   = true

  enable_https_listener = true
  certificate_arn       = aws_acm_certificate.internal.arn
}
```

### With Access Logs and WAF

```hcl
module "alb" {
  source = "git::https://github.com/flightcontrolhq/modules.git//networking/alb?ref=v1.0.0"

  name       = "secure"
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnet_ids

  enable_https_listener = true
  certificate_arn       = aws_acm_certificate.main.arn

  # Access Logs - creates S3 bucket automatically
  enable_access_logs         = true
  access_logs_retention_days = 365

  # WAF
  web_acl_arn = aws_wafv2_web_acl.main.arn

  # Custom default response
  default_action_status_code = 404
  default_action_message     = "Not Found"
}
```

### Integration with ECS Service

```hcl
# Create ALB with HTTPS
module "alb" {
  source = "git::https://github.com/flightcontrolhq/modules.git//networking/alb?ref=v1.0.0"

  name       = "main"
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnet_ids

  enable_https_listener = true
  certificate_arn       = aws_acm_certificate.main.arn
}

# ECS service creates its own target group and listener rule
module "api_service" {
  source = "git::https://github.com/flightcontrolhq/modules.git//compute/ecs?ref=v1.0.0"

  name       = "api"
  cluster_id = module.ecs_cluster.id

  # ALB integration - ECS module creates target group and listener rule
  alb_listener_arn      = module.alb.https_listener_arn
  alb_security_group_id = module.alb.security_group_id

  listener_rule_priority = 100
  listener_rule_conditions = {
    path_patterns = ["/api/*"]
  }

  target_group_port = 8080
  health_check = {
    path = "/health"
  }
}

# Another ECS service on the same ALB
module "web_service" {
  source = "git::https://github.com/flightcontrolhq/modules.git//compute/ecs?ref=v1.0.0"

  name       = "web"
  cluster_id = module.ecs_cluster.id

  alb_listener_arn      = module.alb.https_listener_arn
  alb_security_group_id = module.alb.security_group_id

  listener_rule_priority = 200
  listener_rule_conditions = {
    path_patterns = ["/*"]
  }

  target_group_port = 3000
  health_check = {
    path = "/"
  }
}
```

### Integration with EKS (TargetGroupBinding)

For EKS, the ECS-style integration won't work directly. Instead, use the AWS Load Balancer Controller's `TargetGroupBinding` resource in Kubernetes to register pods with a target group created outside of Kubernetes.

```hcl
# Create ALB with HTTPS
module "alb" {
  source = "git::https://github.com/flightcontrolhq/modules.git//networking/alb?ref=v1.0.0"

  name       = "eks-alb"
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnet_ids

  enable_https_listener = true
  certificate_arn       = aws_acm_certificate.main.arn
}

# Create target group for EKS service
resource "aws_lb_target_group" "eks_api" {
  name        = "eks-api"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"

  health_check {
    path = "/health"
  }
}

# Create listener rule
resource "aws_lb_listener_rule" "eks_api" {
  listener_arn = module.alb.https_listener_arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.eks_api.arn
  }

  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }
}

# Output for Kubernetes TargetGroupBinding
output "eks_api_target_group_arn" {
  value = aws_lb_target_group.eks_api.arn
}
```

Then in Kubernetes:

```yaml
apiVersion: elbv2.k8s.aws/v1beta1
kind: TargetGroupBinding
metadata:
  name: api-tgb
spec:
  serviceRef:
    name: api-service
    port: 8080
  targetGroupARN: <output from terraform>
  targetType: ip
```

## Requirements

| Name | Version |
|------|---------|
| opentofu/terraform | >= 1.10.0 |
| aws | >= 5.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Name prefix for all resources created by this module. | `string` | n/a | yes |
| vpc_id | The ID of the VPC where the ALB will be created. | `string` | n/a | yes |
| subnet_ids | A list of subnet IDs for the ALB. Use public subnets for internet-facing ALBs. | `list(string)` | n/a | yes |
| tags | A map of tags to assign to all resources. | `map(string)` | `{}` | no |
| internal | If true, the ALB will be internal (not internet-facing). | `bool` | `false` | no |
| enable_deletion_protection | Enable deletion protection on the ALB. | `bool` | `false` | no |
| idle_timeout | The time in seconds that the connection is allowed to be idle. | `number` | `60` | no |
| enable_http2 | Enable HTTP/2 on the ALB. | `bool` | `true` | no |
| drop_invalid_header_fields | Drop HTTP headers with invalid header fields. Recommended for security. | `bool` | `true` | no |
| desync_mitigation_mode | Determines how the ALB handles requests that might pose a security risk due to HTTP desync. | `string` | `"defensive"` | no |
| preserve_host_header | Preserve the Host header in the HTTP request. | `bool` | `false` | no |
| xff_header_processing_mode | Determines how the ALB modifies the X-Forwarded-For header. | `string` | `"append"` | no |
| enable_waf_fail_open | Enable WAF fail open. If true, traffic is allowed when WAF is unavailable. | `bool` | `false` | no |
| enable_http_listener | Create an HTTP listener on port 80. | `bool` | `true` | no |
| enable_https_listener | Create an HTTPS listener on port 443. Requires certificate_arn to be provided. | `bool` | `false` | no |
| http_listener_port | The port for the HTTP listener. | `number` | `80` | no |
| https_listener_port | The port for the HTTPS listener. | `number` | `443` | no |
| http_to_https_redirect | Redirect HTTP traffic to HTTPS. Only applies when both listeners are enabled. | `bool` | `true` | no |
| certificate_arn | The ARN of the ACM certificate for the HTTPS listener. Required if enable_https_listener is true. | `string` | `null` | no |
| ssl_policy | The SSL policy for the HTTPS listener. | `string` | `"ELBSecurityPolicy-TLS13-1-2-2021-06"` | no |
| additional_certificate_arns | A list of additional ACM certificate ARNs for SNI. | `list(string)` | `[]` | no |
| default_action_status_code | The HTTP status code to return when no listener rule matches. | `number` | `503` | no |
| default_action_content_type | The content type for the fixed response. | `string` | `"text/plain"` | no |
| default_action_message | The message body for the fixed response. | `string` | `"Service Unavailable"` | no |
| ingress_cidr_blocks | A list of IPv4 CIDR blocks allowed to access the ALB. | `list(string)` | `["0.0.0.0/0"]` | no |
| ingress_ipv6_cidr_blocks | A list of IPv6 CIDR blocks allowed to access the ALB. | `list(string)` | `["::/0"]` | no |
| enable_access_logs | Enable access logging for the ALB. | `bool` | `false` | no |
| access_logs_bucket_arn | The ARN of an existing S3 bucket for access logs. If null and access logs are enabled, a new bucket will be created. | `string` | `null` | no |
| access_logs_prefix | The S3 prefix for access logs. | `string` | `""` | no |
| access_logs_retention_days | The number of days to retain access logs in S3. | `number` | `90` | no |
| access_logs_kms_key_id | KMS key ID for S3 bucket encryption. If null, uses AES256. | `string` | `null` | no |
| access_logs_versioning_enabled | Enable versioning for the access logs S3 bucket. | `bool` | `false` | no |
| web_acl_arn | The ARN of a WAFv2 Web ACL to associate with the ALB. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| alb_id | The ID of the Application Load Balancer. |
| alb_arn | The ARN of the Application Load Balancer. |
| alb_arn_suffix | The ARN suffix of the ALB for use with CloudWatch Metrics. |
| alb_dns_name | The DNS name of the Application Load Balancer. |
| alb_zone_id | The canonical hosted zone ID of the ALB (for Route53 alias records). |
| http_listener_arn | The ARN of the HTTP listener (null if disabled). |
| https_listener_arn | The ARN of the HTTPS listener (null if disabled). |
| security_group_id | The ID of the ALB security group. |
| security_group_arn | The ARN of the ALB security group. |
| access_logs_bucket_name | The name of the S3 bucket for access logs (null if access logs disabled or using existing bucket). |
| access_logs_bucket_arn | The ARN of the S3 bucket for access logs (null if access logs disabled or using existing bucket). |

## Architecture

```
                    ┌─────────────────────────────────────────┐
                    │            ALB Module                    │
                    │  ┌─────────────┐  ┌─────────────────┐   │
Internet ─────────▶ │  │     ALB     │  │    Listeners    │   │
                    │  │             │  │  (HTTP/HTTPS)   │   │
                    │  └─────────────┘  └─────────────────┘   │
                    │  ┌─────────────┐                        │
                    │  │  Security   │  Default action:       │
                    │  │   Group     │  Fixed response        │
                    │  └─────────────┘                        │
                    └─────────────────────────────────────────┘
                                    │
                                    │ Outputs: listener_arn, security_group_id
                                    ▼
                    ┌─────────────────────────────────────────┐
                    │         ECS Service Module               │
                    │  ┌─────────────────┐  ┌──────────────┐  │
                    │  │  Target Group   │  │ Listener     │  │
                    │  │  (for this svc) │  │ Rule         │  │
                    │  └─────────────────┘  └──────────────┘  │
                    │  ┌─────────────────┐                    │
                    │  │  ECS Service    │                    │
                    │  │  (registers     │                    │
                    │  │   targets)      │                    │
                    │  └─────────────────┘                    │
                    └─────────────────────────────────────────┘
```

## Security Considerations

- **TLS 1.3**: The default SSL policy (`ELBSecurityPolicy-TLS13-1-2-2021-06`) enforces TLS 1.2 or 1.3.
- **Invalid Headers**: `drop_invalid_header_fields` is enabled by default to prevent HTTP header injection attacks.
- **Desync Protection**: `desync_mitigation_mode` is set to `defensive` by default to protect against HTTP desync attacks.
- **WAF Integration**: Optionally attach a WAFv2 Web ACL for additional protection.

## Notes

- At least 2 subnets in different availability zones are required for high availability.
- When HTTPS is enabled, a valid ACM certificate ARN must be provided.
- The security group allows all egress traffic to enable health checks and communication with targets.
