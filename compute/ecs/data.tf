################################################################################
# Data Sources
################################################################################

# Get the latest ECS-optimized Amazon Linux 2023 AMI
data "aws_ssm_parameter" "ecs_optimized_ami" {
  count = local.enable_ec2 && var.ec2_ami_id == null ? 1 : 0

  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
}

# Get current AWS region
data "aws_region" "current" {}

# Get current AWS account ID
data "aws_caller_identity" "current" {}

