################################################################################
# Lambda@Edge
#
# Created only in 'filesystem_previews' mode. Lambda@Edge functions must live
# in us-east-1, so the entire module is invoked through the aws.us_east_1
# alias which the caller is required to configure (see versions.tf).
#
# Build flow:
#   1. null_resource.npm_install runs `npm install --omit=dev` in the handler
#      directory whenever package.json changes.
#   2. data.archive_file zips the result into a deterministic location.
#   3. The compute/lambda module ingests the zip, with publish=true (required
#      for Lambda@Edge associations) and an inline least-privilege S3 read
#      policy scoped to the hosting bucket only.
################################################################################

resource "null_resource" "npm_install" {
  count = local.uses_lambda_edge && var.lambda_source_dir == null ? 1 : 0

  triggers = {
    package_json = filesha256("${path.module}/edge/handler/package.json")
  }

  provisioner "local-exec" {
    working_dir = "${path.module}/edge/handler"
    command     = "npm install --omit=dev --silent --no-audit --no-fund"
  }
}

data "archive_file" "edge_handler" {
  count = local.uses_lambda_edge ? 1 : 0

  type        = "zip"
  source_dir  = local.lambda_source_dir
  output_path = local.lambda_zip_path

  depends_on = [null_resource.npm_install]
}

module "edge_lambda" {
  count = local.uses_lambda_edge ? 1 : 0

  source = "../../compute/lambda"

  providers = {
    aws = aws.us_east_1
  }

  name        = local.lambda_name
  description = "${var.name} Lambda@Edge origin-request handler (hosting/static_site)"

  is_lambda_at_edge = true

  package_type = "Zip"
  runtime      = var.lambda_runtime
  handler      = "index.handler"
  filename     = data.archive_file.edge_handler[0].output_path

  source_code_hash = data.archive_file.edge_handler[0].output_base64sha256

  publish       = true
  architectures = ["x86_64"]
  memory_size   = var.lambda_memory_size
  timeout       = var.lambda_timeout

  log_retention_days = var.lambda_log_retention_days

  role_inline_policies = {
    "s3-hosting-read" = data.aws_iam_policy_document.lambda_edge_s3_read[0].json
  }

  tags = local.tags
}
