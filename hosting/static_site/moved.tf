################################################################################
# State moves
#
# The viewer-request function was renamed when the viewer-response cache-control
# function was added. Its AWS name did not change, so preserve the existing
# function instead of attempting a conflicting create-before-destroy.
#
# The CloudWatch access-logging resources moved from this module into
# cdn/cloudfront when logging gained the destination select. Without these
# blocks an upgrade plans create-then-destroy on identically named resources
# and the applies collide (log group "already exists", delivery source
# PutDeliverySource conflict).
################################################################################

moved {
  from = aws_cloudfront_function.this
  to   = aws_cloudfront_function.rewrite
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
