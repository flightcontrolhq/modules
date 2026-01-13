################################################################################
# IAM Instance Profile
################################################################################

resource "aws_iam_instance_profile" "this" {
  count = var.create_instance_profile ? 1 : 0

  name = coalesce(var.instance_profile_name, var.name)
  path = coalesce(var.instance_profile_path, var.path)
  role = aws_iam_role.this.name

  tags = merge(local.tags, {
    Name = coalesce(var.instance_profile_name, var.name, var.name_prefix, "iam-instance-profile")
  })
}
