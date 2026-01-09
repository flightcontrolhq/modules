################################################################################
# Basic ECS Service Module Tests
################################################################################

# Mock provider for testing
mock_provider "aws" {}

################################################################################
# Variables for Tests
################################################################################

variables {
  name        = "test-service"
  vpc_id      = "vpc-12345678"
  subnet_ids  = ["subnet-1a2b3c4d", "subnet-5e6f7g8h"]
  cluster_arn = "arn:aws:ecs:us-east-1:123456789012:cluster/test-cluster"
}

################################################################################
# Test: Basic Service Creation
################################################################################

run "basic_service" {
  command = plan

  assert {
    condition     = aws_ecs_service.this.name == "test-service"
    error_message = "Service name should be 'test-service'"
  }

  assert {
    condition     = aws_ecs_task_definition.this.family == "test-service"
    error_message = "Task definition family should be 'test-service'"
  }

  assert {
    condition     = aws_ecs_task_definition.this.cpu == "256"
    error_message = "Default CPU should be 256"
  }

  assert {
    condition     = aws_ecs_task_definition.this.memory == "512"
    error_message = "Default memory should be 512"
  }

  assert {
    condition     = aws_security_group.this.vpc_id == "vpc-12345678"
    error_message = "Security group should be in the correct VPC"
  }
}

################################################################################
# Test: Service with Load Balancer
################################################################################

run "service_with_load_balancer" {
  command = plan

  variables {
    container_port = 8080
    load_balancer_attachment = {
      target_group = {
        port     = 8080
        protocol = "HTTP"
      }
      listener_rules = [{
        listener_arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/my-alb/1234567890123456/1234567890123456"
        priority     = 100
        conditions = [{
          type   = "path-pattern"
          values = ["/api/*"]
        }]
      }]
    }
  }

  assert {
    condition     = length(aws_lb_target_group.this) == 1
    error_message = "Should create one target group for rolling deployment"
  }

  assert {
    condition     = aws_lb_target_group.this[0].port == 8080
    error_message = "Target group port should be 8080"
  }

  assert {
    condition     = aws_lb_target_group.this[0].protocol == "HTTP"
    error_message = "Target group protocol should be HTTP"
  }
}

################################################################################
# Test: Blue/Green Deployment
################################################################################

run "blue_green_deployment" {
  command = plan

  variables {
    deployment_type = "blue_green"
    container_port  = 8080
    load_balancer_attachment = {
      target_group = {
        port     = 8080
        protocol = "HTTP"
      }
      listener_rules = [{
        listener_arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/my-alb/1234567890123456/1234567890123456"
        priority     = 100
        conditions = [{
          type   = "host-header"
          values = ["api.example.com"]
        }]
      }]
    }
  }

  assert {
    condition     = length(aws_lb_target_group.tg_1) == 1
    error_message = "Should create blue target group for blue/green deployment"
  }

  assert {
    condition     = length(aws_lb_target_group.tg_2) == 1
    error_message = "Should create green target group for blue/green deployment"
  }

  assert {
    condition     = length(aws_lb_target_group.this) == 0
    error_message = "Should not create single target group for blue/green deployment"
  }
}

################################################################################
# Test: Auto Scaling
################################################################################

run "service_with_auto_scaling" {
  command = plan

  variables {
    auto_scaling = {
      min_capacity = 1
      max_capacity = 10
      target_tracking = [{
        policy_name       = "cpu-scaling"
        target_value      = 70
        predefined_metric = "ECSServiceAverageCPUUtilization"
      }]
    }
  }

  assert {
    condition     = length(aws_appautoscaling_target.this) == 1
    error_message = "Should create auto scaling target"
  }

  assert {
    condition     = aws_appautoscaling_target.this[0].min_capacity == 1
    error_message = "Auto scaling min capacity should be 1"
  }

  assert {
    condition     = aws_appautoscaling_target.this[0].max_capacity == 10
    error_message = "Auto scaling max capacity should be 10"
  }
}

################################################################################
# Test: Custom Task Configuration
################################################################################

run "custom_task_configuration" {
  command = plan

  variables {
    task_cpu       = 1024
    task_memory    = 2048
    container_port = 3000
    launch_type    = "FARGATE"

    runtime_platform = {
      operating_system_family = "LINUX"
      cpu_architecture        = "ARM64"
    }
  }

  assert {
    condition     = aws_ecs_task_definition.this.cpu == "1024"
    error_message = "Task CPU should be 1024"
  }

  assert {
    condition     = aws_ecs_task_definition.this.memory == "2048"
    error_message = "Task memory should be 2048"
  }
}

################################################################################
# Test: IAM Role Creation
################################################################################

run "iam_role_creation" {
  command = plan

  assert {
    condition     = length(aws_iam_role.execution) == 1
    error_message = "Should create execution role when not provided"
  }

  assert {
    condition     = length(aws_iam_role.task) == 1
    error_message = "Should create task role when not provided"
  }
}

################################################################################
# Test: ECS Exec Enabled
################################################################################

run "ecs_exec_enabled" {
  command = plan

  variables {
    enable_execute_command = true
  }

  assert {
    condition     = aws_ecs_service.this.enable_execute_command == true
    error_message = "ECS Exec should be enabled"
  }

  assert {
    condition     = length(aws_iam_role_policy.task_exec_command) == 1
    error_message = "Should create ECS Exec IAM policy"
  }
}

################################################################################
# Test: Default Container Port
################################################################################

run "default_container_port" {
  command = plan

  assert {
    condition     = output.container_port == 80
    error_message = "Default container port should be 80"
  }

  assert {
    condition     = output.container_name == "app"
    error_message = "Container name should be 'app'"
  }
}
