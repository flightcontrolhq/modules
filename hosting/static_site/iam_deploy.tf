################################################################################
# Deploy Role (optional)
#
# A least-privilege IAM role for CI to assume when uploading new builds and
# invalidating CloudFront. The trust policy is fully user-supplied so any
# identity provider can be used (GitHub OIDC, GitLab OIDC, an external account,
# a specific user/role principal, etc.).
#
# This replaces the FC `CodeBuildServiceRole` pattern: instead of running
# builds inside the same CloudFormation stack, your CI runs the build, assumes
# this role, and runs:
#   aws s3 sync ./dist s3://${hosting_bucket}/
#   aws cloudfront create-invalidation --distribution-id <id> --paths '/*'
################################################################################

resource "aws_iam_role" "deploy" {
  count = var.create_deploy_role ? 1 : 0

  name               = local.deploy_role_name
  assume_role_policy = var.deploy_role_trust_policy

  tags = local.tags

  lifecycle {
    precondition {
      condition     = var.deploy_role_trust_policy != null
      error_message = "deploy_role_trust_policy is required when create_deploy_role = true."
    }
  }
}

resource "aws_iam_role_policy" "deploy" {
  count = var.create_deploy_role ? 1 : 0

  name   = "${local.deploy_role_name}-policy"
  role   = aws_iam_role.deploy[0].id
  policy = data.aws_iam_policy_document.deploy_role_policy[0].json
}
