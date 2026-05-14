################################################################################
# Data Sources
################################################################################

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "archive_file" "placeholder" {
  count = local.create_code_bucket ? 1 : 0

  type        = "zip"
  output_path = "${path.module}/.terraform/tmp/${var.name}-placeholder.zip"

  source {
    filename = "index.js"
    content  = <<-EOT
      exports.handler = async () => ({
        statusCode: 200,
        body: "Lambda placeholder — replace via your deploy pipeline."
      });
    EOT
  }
}
