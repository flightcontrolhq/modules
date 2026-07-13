################################################################################
# State moves
#
# The CloudWatch access-logging resources moved from this module into
# cdn/cloudfront when logging gained the destination select. Without these
# blocks an upgrade plans create-then-destroy on identically named resources
# and the applies collide (log group "already exists", delivery source
# PutDeliverySource conflict).
################################################################################

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
