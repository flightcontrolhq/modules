# ECS Service Module

This module creates an Amazon ECS service with a placeholder task definition, load balancer integration, auto scaling, and service discovery. It supports both rolling and blue/green deployment strategies.

**Note:** This module provisions infrastructure with a placeholder container (nginx). CodeDeploy or another CI/CD tool is expected to deploy the actual application by updating the task definition.

## Features

- ECS service with configurable deployment strategies (rolling or blue/green)
- Placeholder task definition (nginx) - CodeDeploy updates with actual application
- IAM roles for task execution and task roles
- Security group for ECS tasks with configurable rules
- Target group creation for ALB/NLB integration
- Listener rule configuration for path-based and host-based routing
- Application Auto Scaling with target tracking and scheduled scaling
- AWS Cloud Map service discovery integration
- Blue/green deployment infrastructure (CodeDeploy managed externally)

## Usage

### Basic Fargate Service

```hcl
module "ecs_cluster" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//compute/ecs_cluster?ref=v1.0.0"

  name               = "my-cluster"
  vpc_id             = "vpc-12345678"
  private_subnet_ids = ["subnet-1a2b3c4d", "subnet-5e6f7g8h"]
  public_subnet_ids  = ["subnet-public-1", "subnet-public-2"]

  enable_public_alb       = true
  public_alb_enable_https = true
  public_alb_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abc123"
}

module "api_service" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//compute/ecs_service?ref=v1.0.0"

  name        = "api"
  cluster_arn = module.ecs_cluster.cluster_arn
  vpc_id      = "vpc-12345678"
  subnet_ids  = ["subnet-1a2b3c4d", "subnet-5e6f7g8h"]

  # Task configuration
  task_cpu       = 256
  task_memory    = 512
  container_port = 80  # Port for the placeholder container

  # Load balancer
  load_balancer_attachment = {
    target_group = {
      port     = 80
      protocol = "HTTP"
      health_check = {
        path = "/"
      }
    }
    listener_rules = [{
      listener_arn = module.ecs_cluster.public_alb_https_listener_arn
      priority     = 100
      conditions = [{
        type   = "path-pattern"
        values = ["/api/*"]
      }]
    }]
  }

  # Auto scaling
  auto_scaling = {
    min_capacity = 1
    max_capacity = 10
    target_tracking = [{
      policy_name       = "cpu"
      target_value      = 70
      predefined_metric = "ECSServiceAverageCPUUtilization"
    }]
  }
}

# After infrastructure is provisioned, deploy actual application via CodeDeploy
```

### Blue/Green Deployment

```hcl
module "api_service" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//compute/ecs_service?ref=v1.0.0"

  name            = "api"
  cluster_arn     = module.ecs_cluster.cluster_arn
  vpc_id          = "vpc-12345678"
  subnet_ids      = ["subnet-1a2b3c4d", "subnet-5e6f7g8h"]
  deployment_type = "blue_green"

  task_cpu       = 512
  task_memory    = 1024
  container_port = 8080

  load_balancer_attachment = {
    target_group = {
      port     = 8080
      protocol = "HTTP"
    }
    listener_rules = [{
      listener_arn = module.ecs_cluster.public_alb_https_listener_arn
      priority     = 100
      conditions = [{
        type   = "host-header"
        values = ["api.example.com"]
      }]
    }]
  }
}

# Use the outputs to configure CodeDeploy externally
# module.api_service.blue_target_group_arn
# module.api_service.green_target_group_arn
# module.api_service.codedeploy_config
```

### With Service Discovery

```hcl
resource "aws_service_discovery_private_dns_namespace" "main" {
  name = "internal.local"
  vpc  = "vpc-12345678"
}

module "backend_service" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//compute/ecs_service?ref=v1.0.0"

  name        = "backend"
  cluster_arn = module.ecs_cluster.cluster_arn
  vpc_id      = "vpc-12345678"
  subnet_ids  = ["subnet-1a2b3c4d", "subnet-5e6f7g8h"]

  task_cpu       = 256
  task_memory    = 512
  container_port = 3000

  # No load balancer, just service discovery
  load_balancer_attachment = null

  service_discovery = {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id
  }
}

# Service is now accessible at: backend.internal.local
```

### Minimal Configuration

```hcl
module "worker_service" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//compute/ecs_service?ref=v1.0.0"

  name        = "worker"
  cluster_arn = module.ecs_cluster.cluster_arn
  vpc_id      = "vpc-12345678"
  subnet_ids  = ["subnet-1a2b3c4d", "subnet-5e6f7g8h"]

  # Uses defaults: 256 CPU, 512 MiB memory, port 80
  # Placeholder nginx container will be deployed initially
  # CodeDeploy will update with actual worker container
}
```

## Requirements

| Name | Version |
|------|---------|
| opentofu/terraform | >= 1.10.0 |
| aws | >= 5.0 |

## Inputs

### General

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Name for the ECS service and related resources | `string` | n/a | yes |
| tags | Map of tags to assign to resources | `map(string)` | `{}` | no |
| vpc_id | VPC ID where the service will run | `string` | n/a | yes |
| subnet_ids | Subnet IDs for ECS tasks | `list(string)` | n/a | yes |
| cluster_arn | ECS cluster ARN | `string` | n/a | yes |

### Task Definition

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| task_cpu | CPU units for the task | `number` | `256` | no |
| task_memory | Memory (MiB) for the task | `number` | `512` | no |
| container_port | Port for the placeholder container | `number` | `80` | no |
| launch_type | Launch type (FARGATE or EC2) | `string` | `"FARGATE"` | no |
| network_mode | Docker networking mode | `string` | `"awsvpc"` | no |
| volumes | List of volume definitions | `list(object)` | `[]` | no |

### IAM

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| execution_role_arn | Existing execution role ARN | `string` | `null` | no |
| task_role_arn | Existing task role ARN | `string` | `null` | no |
| execution_role_policies | Additional policies for execution role | `list(string)` | `[]` | no |
| task_role_policies | Policies to attach to task role | `list(string)` | `[]` | no |

### Service

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| desired_count | Desired number of tasks | `number` | `1` | no |
| deployment_type | Deployment type: rolling or blue_green | `string` | `"rolling"` | no |
| deployment_minimum_healthy_percent | Minimum healthy percent during deployment | `number` | `100` | no |
| deployment_maximum_percent | Maximum percent during deployment | `number` | `200` | no |
| enable_execute_command | Enable ECS Exec | `bool` | `false` | no |
| health_check_grace_period_seconds | Grace period for LB health checks | `number` | `0` | no |
| capacity_provider_strategies | Capacity provider strategies | `list(object)` | `[]` | no |

### Load Balancer

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| load_balancer_attachment | Load balancer attachment configuration | `object` | `null` | no |

### Auto Scaling

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| auto_scaling | Auto scaling configuration | `object` | `null` | no |

### Service Discovery

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| service_discovery | Cloud Map service discovery config | `object` | `null` | no |

## Outputs

### ECS Service

| Name | Description |
|------|-------------|
| service_id | The ID of the ECS service |
| service_arn | The ARN of the ECS service |
| service_name | The name of the ECS service |

### Task Definition

| Name | Description |
|------|-------------|
| task_definition_arn | The ARN of the task definition |
| task_definition_family | The family of the task definition |
| execution_role_arn | The ARN of the execution role |
| task_role_arn | The ARN of the task role |

### Security

| Name | Description |
|------|-------------|
| security_group_id | The ID of the service security group |

### Target Groups

| Name | Description |
|------|-------------|
| target_group_arn | Target group ARN (rolling deployment) |
| blue_target_group_arn | Blue target group ARN (blue/green) |
| green_target_group_arn | Green target group ARN (blue/green) |
| target_group_arns | Map of all target group ARNs |

### Auto Scaling

| Name | Description |
|------|-------------|
| autoscaling_target_arn | Auto scaling target ARN |
| autoscaling_policies | Map of scaling policy ARNs |

### Service Discovery

| Name | Description |
|------|-------------|
| service_discovery_arn | Cloud Map service ARN |

### CodeDeploy Integration

| Name | Description |
|------|-------------|
| codedeploy_config | Config values for CodeDeploy setup |

### Container Information

| Name | Description |
|------|-------------|
| container_name | The name of the placeholder container |
| container_port | The port of the placeholder container |

## Deployment Workflow

This module is designed for an infrastructure-first provisioning workflow:

1. **Provision Infrastructure**: This module creates the ECS service with a placeholder nginx container
2. **Configure CodeDeploy**: Use the module outputs to set up CodeDeploy application and deployment group
3. **Deploy Application**: CodeDeploy updates the task definition with the actual application container

### Placeholder Container

The module deploys the hello-world container (`public.ecr.aws/docker/library/hello-world:latest`) as a placeholder. This container prints a message and exits, so:
- Load balancer health checks will fail until the actual application is deployed
- This is expected behavior for infrastructure-first provisioning
- CodeDeploy should deploy the actual application immediately after infrastructure is ready

## Deployment Strategies

### Rolling Deployment (Default)

Uses the ECS deployment controller for zero-downtime rolling updates:
- Configurable minimum/maximum healthy percent
- Built-in circuit breaker with optional rollback
- Simple and fully managed by ECS

### Blue/Green Deployment

Sets up infrastructure for CodeDeploy-managed blue/green deployments:
- Creates two target groups (blue and green)
- Sets deployment controller to CODE_DEPLOY
- Outputs all ARNs needed for CodeDeploy configuration
- CodeDeploy application and deployment group must be managed externally

## Notes

- The module creates a security group that allows inbound traffic from the VPC CIDR
- For Fargate tasks in public subnets without NAT, set `assign_public_ip = true`
- The placeholder container uses nginx:alpine from public ECR - no special permissions needed
- For blue/green deployments, the module only creates the infrastructure; CodeDeploy must be configured separately
