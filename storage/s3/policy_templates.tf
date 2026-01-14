################################################################################
# S3 Bucket Policy Templates
################################################################################

# This file contains local policy document templates for common use cases.
# Each template produces a list of policy statements that can be merged
# into a bucket policy.

locals {
  #-----------------------------------------------------------------------------
  # Data sources for policy templates
  #-----------------------------------------------------------------------------
  account_id      = data.aws_caller_identity.current.account_id
  region          = data.aws_region.current.id
  elb_service_arn = data.aws_elb_service_account.current.arn
  bucket_arn      = aws_s3_bucket.this.arn

  #-----------------------------------------------------------------------------
  # Policy Template: Deny Insecure Transport
  #-----------------------------------------------------------------------------
  # Enforces HTTPS-only access to the bucket. Any request over HTTP is denied.
  policy_deny_insecure_transport = [
    {
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        local.bucket_arn,
        "${local.bucket_arn}/*"
      ]
      Condition = {
        Bool = {
          "aws:SecureTransport" = "false"
        }
      }
    }
  ]

  #-----------------------------------------------------------------------------
  # Policy Template: ALB Access Logs
  #-----------------------------------------------------------------------------
  # Allows Application Load Balancer to deliver access logs to this bucket.
  # Includes permissions for:
  # - ELB service account (regional) to put objects
  # - AWS delivery.logs.amazonaws.com service for log delivery
  # - GetBucketAcl permission for ACL checks
  policy_alb_access_logs = [
    {
      Sid    = "AllowELBRootAccount"
      Effect = "Allow"
      Principal = {
        AWS = local.elb_service_arn
      }
      Action   = "s3:PutObject"
      Resource = "${local.bucket_arn}/AWSLogs/${local.account_id}/*"
    },
    {
      Sid    = "AllowELBLogDelivery"
      Effect = "Allow"
      Principal = {
        Service = "delivery.logs.amazonaws.com"
      }
      Action   = "s3:PutObject"
      Resource = "${local.bucket_arn}/AWSLogs/${local.account_id}/*"
      Condition = {
        StringEquals = {
          "s3:x-amz-acl" = "bucket-owner-full-control"
        }
      }
    },
    {
      Sid    = "AllowELBLogDeliveryAclCheck"
      Effect = "Allow"
      Principal = {
        Service = "delivery.logs.amazonaws.com"
      }
      Action   = "s3:GetBucketAcl"
      Resource = local.bucket_arn
    }
  ]

  #-----------------------------------------------------------------------------
  # Policy Template: NLB Access Logs
  #-----------------------------------------------------------------------------
  # Allows Network Load Balancer to deliver access logs to this bucket.
  # NLB uses only the delivery.logs.amazonaws.com service (not ELB service account).
  policy_nlb_access_logs = [
    {
      Sid    = "AllowNLBLogDelivery"
      Effect = "Allow"
      Principal = {
        Service = "delivery.logs.amazonaws.com"
      }
      Action   = "s3:PutObject"
      Resource = "${local.bucket_arn}/AWSLogs/${local.account_id}/*"
      Condition = {
        StringEquals = {
          "s3:x-amz-acl" = "bucket-owner-full-control"
        }
      }
    },
    {
      Sid    = "AllowNLBLogDeliveryAclCheck"
      Effect = "Allow"
      Principal = {
        Service = "delivery.logs.amazonaws.com"
      }
      Action   = "s3:GetBucketAcl"
      Resource = local.bucket_arn
    }
  ]

  #-----------------------------------------------------------------------------
  # Policy Template: VPC Flow Logs
  #-----------------------------------------------------------------------------
  # Allows VPC Flow Logs to deliver logs to this bucket via the
  # delivery.logs.amazonaws.com service. Includes source account and ARN
  # conditions for additional security.
  policy_vpc_flow_logs = [
    {
      Sid    = "AWSLogDeliveryAclCheck"
      Effect = "Allow"
      Principal = {
        Service = "delivery.logs.amazonaws.com"
      }
      Action   = "s3:GetBucketAcl"
      Resource = local.bucket_arn
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = local.account_id
        }
        ArnLike = {
          "aws:SourceArn" = "arn:aws:logs:${local.region}:${local.account_id}:*"
        }
      }
    },
    {
      Sid    = "AWSLogDeliveryWrite"
      Effect = "Allow"
      Principal = {
        Service = "delivery.logs.amazonaws.com"
      }
      Action   = "s3:PutObject"
      Resource = "${local.bucket_arn}/*"
      Condition = {
        StringEquals = {
          "s3:x-amz-acl"      = "bucket-owner-full-control"
          "aws:SourceAccount" = local.account_id
        }
        ArnLike = {
          "aws:SourceArn" = "arn:aws:logs:${local.region}:${local.account_id}:*"
        }
      }
    }
  ]

  #-----------------------------------------------------------------------------
  # Policy Template Lookup Map
  #-----------------------------------------------------------------------------
  # Maps template names to their policy statement lists
  policy_template_map = {
    deny_insecure_transport = local.policy_deny_insecure_transport
    alb_access_logs         = local.policy_alb_access_logs
    nlb_access_logs         = local.policy_nlb_access_logs
    vpc_flow_logs           = local.policy_vpc_flow_logs
  }

  #-----------------------------------------------------------------------------
  # Computed Policy Statements
  #-----------------------------------------------------------------------------
  # Flatten all selected policy templates into a single list of statements
  policy_template_statements = flatten([
    for template_name in var.policy_templates :
    lookup(local.policy_template_map, template_name, [])
  ])
}
