################################################################################
# Local Values
################################################################################

locals {
  # Default tags for all resources
  default_tags = {
    ManagedBy = "terraform"
    Module    = "compute/ec2"
  }

  tags = merge(local.default_tags, var.tags)

  region = coalesce(var.region, data.aws_region.current.region)

  container_runtime = var.runtime == "container"

  enable_load_balancer = var.load_balancer_attachment != null ? var.load_balancer_attachment.enabled : false

  cpu_architecture = var.ami_id == null ? (
    contains(data.aws_ec2_instance_type.selected[0].supported_architectures, "arm64") ? "arm64" : "x86_64"
  ) : null

  ami_id = var.ami_id != null ? var.ami_id : data.aws_ssm_parameter.al2023_ami[0].value

  log_group_name = "/ravion/ec2/${var.name}"

  # App layout on the instances. The container deploy script rewrites the
  # env file on every deploy; manual instances write it once at boot. The
  # app log path is shipped to CloudWatch for the manual runtime.
  env_file_path = "/etc/ravion/${var.name}.env"
  app_log_path  = "/var/log/ravion/${var.name}/app.log"

  # Env-file builder script shared by the container deploy document and
  # the manual runtime's boot. Plain values are Terraform-rendered (like
  # an ECS task definition's environment); secrets are fetched on the
  # instance so their values stay out of state and the SSM document.
  env_file_script = templatefile("${path.module}/templates/env_file.sh.tpl", {
    environment_variables = var.environment_variables
    secrets               = var.secrets
    app_port              = var.app_port
    env_file_path         = local.env_file_path
    region                = local.region
  })

  # Prelude of the manual deploy document: refresh the app env file
  # (plain values and secrets) and export it, so the deploy commands
  # that follow always run with current configuration. set -e makes any
  # failing command fail the per-instance invocation.
  manual_deploy_prelude = <<-EOT
    #!/bin/bash
    set -euo pipefail
    ${local.env_file_script}
    set -a
    . "${local.env_file_path}"
    set +a
  EOT

  deploy_script = local.container_runtime ? templatefile("${path.module}/templates/deploy_container.sh.tpl", {
    name                   = var.name
    region                 = local.region
    app_port               = var.app_port
    start_command          = var.start_command != null ? var.start_command : ""
    health_check_path      = var.health_check_path != null ? var.health_check_path : ""
    env_file_script        = local.env_file_script
    env_file_path          = local.env_file_path
    log_group_name         = local.log_group_name
    target_group_arn       = local.enable_load_balancer ? aws_lb_target_group.app[0].arn : ""
    data_volume_mount_path = var.data_volume_enabled ? var.data_volume_mount_path : ""
    efs_mount_path         = var.efs_enabled ? var.efs_mount_path : ""
  }) : null

  user_data = base64encode(templatefile("${path.module}/templates/user_data.sh.tpl", {
    name                   = var.name
    region                 = local.region
    runtime                = var.runtime
    env_file_script        = local.env_file_script
    env_file_path          = local.env_file_path
    app_log_path           = local.app_log_path
    log_group_name         = local.log_group_name
    data_volume_enabled    = var.data_volume_enabled
    data_volume_mount_path = var.data_volume_mount_path
    efs_enabled            = var.efs_enabled
    efs_file_system_id     = var.efs_file_system_id != null ? var.efs_file_system_id : ""
    efs_access_point_id    = var.efs_access_point_id != null ? var.efs_access_point_id : ""
    efs_mount_path         = var.efs_mount_path
    additional_user_data   = var.additional_user_data
  }))
}
