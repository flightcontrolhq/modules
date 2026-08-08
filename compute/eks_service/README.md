# EKS Service Load Balancer Attachment

Creates the Application Load Balancer attachment for a single EKS workload: one IP-mode `aws_lb_target_group` plus one `aws_lb_listener_rule` on a shared listener created by [`compute/eks/addons`](../eks/addons).

The workload itself is not created here. Pods are deployed by Helm (the `rvn-eks-web` chart), and the AWS Load Balancer Controller registers the Service's pod IPs into this target group through a `TargetGroupBinding` that the chart renders from the `target_group_arn` output. Terraform owns the load balancer objects; Helm owns the workload. This is the same split `compute/ecs_service` uses, with ECS's `RegisterTargets` replaced by the controller.

## Usage

```hcl
module "web_lb_attachment" {
  source = "git::https://github.com/ravionhq/modules.git//compute/eks_service?ref=rvn-eks-web@0.1.0"

  name   = "acme-prod-api"
  region = "us-east-1"
  vpc_id = "vpc-0a1b2c3d4e5f67890"

  listener_arn   = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/acme-pub/50dc.../f2f7..."
  container_port = 8080

  listener_rule_conditions = [
    {
      type   = "host-header"
      values = ["api.example.com"]
    }
  ]

  health_check = {
    path    = "/healthz"
    matcher = "200-399"
  }

  tags = {
    Owner = "Ravion"
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| opentofu/terraform | >= 1.10.0 |
| aws | >= 6.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Name for the target group, listener rule, and related resources | `string` | n/a | yes |
| vpc_id | ID of the VPC the EKS cluster runs in; the target group must live in the same VPC as the pods | `string` | n/a | yes |
| listener_arn | ARN of the shared load balancer listener the rule is attached to | `string` | n/a | yes |
| region | AWS region; when null the provider's configured region is used | `string` | `null` | no |
| tags | A map of tags to assign to all resources | `map(string)` | `{}` | no |
| container_port | Port the application container listens on | `number` | `8080` | no |
| target_group_protocol | Protocol the load balancer uses to reach pods (`HTTP` or `HTTPS`) | `string` | `"HTTP"` | no |
| target_group_deregistration_delay | Seconds before a target is deregistered, letting in-flight requests drain | `number` | `300` | no |
| target_group_slow_start | Seconds over which traffic ramps to a newly registered target; `0` disables | `number` | `0` | no |
| health_check | Load balancer health check settings for the target group | `object` | see below | no |
| stickiness | Target group cookie stickiness settings | `object` | see below | no |
| listener_rule_priority | Listener rule priority; when null AWS assigns the next available one | `number` | `null` | no |
| listener_rule_conditions | Conditions that route requests to this service | `list(object)` | catch-all `/*` | no |

### `health_check`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| enabled | `bool` | `true` | Whether the target group performs health checks |
| path | `string` | `"/"` | HTTP path requested |
| port | `string` | `"traffic-port"` | Port checked; `traffic-port` uses the target group port |
| protocol | `string` | `null` | Falls back to `target_group_protocol` |
| matcher | `string` | `"200-399"` | Status codes treated as healthy |
| interval | `number` | `15` | Seconds between checks |
| timeout | `number` | `5` | Seconds to wait for a response; must be lower than `interval` |
| healthy_threshold | `number` | `2` | Consecutive successes before a target is healthy |
| unhealthy_threshold | `number` | `2` | Consecutive failures before a target is unhealthy |

This health check is independent of the chart's Kubernetes readiness probe. The probe decides whether kubelet considers the pod ready; this one decides whether the load balancer sends it traffic.

### `stickiness`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| enabled | `bool` | `false` | Enable cookie stickiness |
| type | `string` | `"lb_cookie"` | `lb_cookie` or `app_cookie` |
| cookie_duration | `number` | `86400` | Seconds the stickiness cookie lives |
| cookie_name | `string` | `null` | Required when `type` is `app_cookie` |

### `listener_rule_conditions`

Each entry is `{ type, values }`. Supported types: `host-header`, `path-pattern`, `http-header`, `http-request-method`, `query-string`, `source-ip`. A rule AND-combines all of its conditions. For `http-header`, the first value is the header name and the rest are matched values. For `query-string`, the first value is the key and the second the value.

## Outputs

| Name | Description |
|------|-------------|
| target_group_arn | ARN of the target group, passed to the chart as `targetGroupArns` |
| target_group_arn_suffix | ARN suffix of the target group, for CloudWatch metrics |
| target_group_name | Name of the target group |
| listener_rule_arn | ARN of the listener rule |
| listener_rule_priority | Priority assigned to the listener rule |
| load_balancer_arn | ARN of the shared load balancer the listener belongs to |
| load_balancer_dns_name | DNS name of the shared load balancer |
| load_balancer_zone_id | Route 53 hosted zone ID of the load balancer, for alias records |
| load_balancer_arn_suffix | ARN suffix of the load balancer, for CloudWatch metrics |
| vpc_id | ID of the VPC the target group was created in |
| region | AWS region where the resources are deployed |

## Design decisions

- **One target group, no alternate.** `compute/ecs_service` creates a `tg-1`/`tg-2` pair plus a test listener rule so ECS's native controller can shift traffic between them. The 2026-08-06 load balancer ADR on ENG-5033 scopes EKS v1 to rolling Deployment updates, so there is no alternate target group, no test rule, and no traffic-shift configuration here.
- **No `ignore_changes` on the listener rule action.** The ECS module has to ignore `action` because the ECS deployment controller rewrites it mid-deploy. Nothing outside Terraform touches this rule, so drift here is real drift and should be corrected.
- **`target_type` is fixed to `ip`.** The AWS Load Balancer Controller registers pod IPs; `instance` mode would require a `NodePort` Service, which the chart does not render.
- **Listener rules only, no NLB listeners.** NLB-fronted EKS workloads are outside this module.
