################################################################################
# State moves
#
# Failed upgrades may leave the original viewer-request function in AWS after
# its Terraform state entry is gone. Forget either legacy address and create
# the replacement under a new address and AWS name so upgrades cannot collide
# with that orphaned function.
#
# The legacy HTML and asset Cache-Control policies cannot be deleted in the
# same apply that detaches them from CloudFront. Forget them after detaching so
# the distribution update is not blocked by ResponseHeadersPolicyInUse.
#
# The CloudWatch access-logging resources moved from this module into
# cdn/cloudfront when logging gained the destination select. Without these
# blocks an upgrade plans create-then-destroy on identically named resources
# and the applies collide (log group "already exists", delivery source
# PutDeliverySource conflict).
################################################################################

removed {
  from = aws_cloudfront_function.this

  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_cloudfront_function.rewrite

  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_cloudfront_response_headers_policy.html

  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_cloudfront_response_headers_policy.assets

  lifecycle {
    destroy = false
  }
}

moved {
  from = aws_cloudwatch_log_group.access_logs
  to   = module.cdn.aws_cloudwatch_log_group.access_logs
}

moved {
  from = aws_cloudwatch_log_delivery_source.access_logs
  to   = module.cdn.aws_cloudwatch_log_delivery_source.access_logs
}

moved {
  from = aws_cloudwatch_log_delivery_destination.access_logs
  to   = module.cdn.aws_cloudwatch_log_delivery_destination.access_logs
}

moved {
  from = aws_cloudwatch_log_delivery.access_logs
  to   = module.cdn.aws_cloudwatch_log_delivery.access_logs
}
