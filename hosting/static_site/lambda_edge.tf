locals {
  edge_router_code = templatefile("${path.module}/functions/edge_router.js", {
    index_document           = var.default_root_object
    routing                  = var.routing
    html_overrides_json      = jsonencode(var.html_path_overrides)
    no_cache_paths_json      = jsonencode(var.no_cache_paths)
    html_cdn_cache_control   = "public, s-maxage=5, stale-while-revalidate=300, stale-if-error=300"
    assets_cdn_cache_control = "public, max-age=31536000, immutable"
    content_types_json = jsonencode({
      ".avif"  = "image/avif"
      ".css"   = "text/css; charset=utf-8"
      ".csv"   = "text/csv; charset=utf-8"
      ".gif"   = "image/gif"
      ".htm"   = "text/html; charset=utf-8"
      ".html"  = "text/html; charset=utf-8"
      ".ico"   = "image/x-icon"
      ".jpeg"  = "image/jpeg"
      ".jpg"   = "image/jpeg"
      ".js"    = "text/javascript; charset=utf-8"
      ".json"  = "application/json; charset=utf-8"
      ".mjs"   = "text/javascript; charset=utf-8"
      ".pdf"   = "application/pdf"
      ".png"   = "image/png"
      ".svg"   = "image/svg+xml"
      ".txt"   = "text/plain; charset=utf-8"
      ".wasm"  = "application/wasm"
      ".webp"  = "image/webp"
      ".woff"  = "font/woff"
      ".woff2" = "font/woff2"
      ".xml"   = "application/xml; charset=utf-8"
    })
  })
}

data "archive_file" "edge_router" {
  count = local.swr_enabled ? 1 : 0

  type        = "zip"
  output_path = "${path.module}/.terraform/${local.edge_router_name}.zip"

  source {
    content  = local.edge_router_code
    filename = "index.js"
  }
}

resource "aws_iam_role" "edge_router" {
  count = local.swr_enabled ? 1 : 0

  provider = aws.us_east_1

  name = local.edge_router_name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["lambda.amazonaws.com", "edgelambda.amazonaws.com"]
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "edge_router_logs" {
  count = local.swr_enabled ? 1 : 0

  provider = aws.us_east_1

  name = "${local.edge_router_name}-logs"
  role = aws_iam_role.edge_router[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "arn:${local.partition}:logs:*:${data.aws_caller_identity.current.account_id}:*"
    }]
  })
}

resource "aws_lambda_function" "edge_router" {
  count = local.swr_enabled ? 1 : 0

  provider = aws.us_east_1

  function_name    = local.edge_router_name
  description      = "Resolve active static-site versions and inject CDN cache headers"
  filename         = data.archive_file.edge_router[0].output_path
  source_code_hash = data.archive_file.edge_router[0].output_base64sha256
  role             = aws_iam_role.edge_router[0].arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  publish          = true

  tags = local.tags

  depends_on = [aws_iam_role_policy.edge_router_logs]

  # Lambda@Edge replicas can delay updates and must be removed by CloudFront
  # before AWS allows the published function version to be deleted.
}
