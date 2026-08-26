################################################################################
# Address migrations
#
# Ingress became optional, so every resource on the public path grew a `count`.
# Adding `count` renames `foo.bar` to `foo.bar[0]`, and a rename is a destroy
# and re-create — of the load balancer, the certificate and the security group
# a live pool is answering traffic on. These blocks tell Terraform it is the
# same object, so an existing pool that keeps its ingress replans clean.
#
# Safe to keep indefinitely: a `moved` block whose source address is absent
# from state is a no-op.
################################################################################

moved {
  from = aws_lb.this
  to   = aws_lb.this[0]
}

moved {
  from = aws_lb_target_group.proxy
  to   = aws_lb_target_group.proxy[0]
}

moved {
  from = aws_lb_listener.https
  to   = aws_lb_listener.https[0]
}

moved {
  from = aws_acm_certificate.wildcard
  to   = aws_acm_certificate.wildcard[0]
}

moved {
  from = aws_security_group.nlb
  to   = aws_security_group.nlb[0]
}

moved {
  from = aws_vpc_security_group_ingress_rule.host_proxy
  to   = aws_vpc_security_group_ingress_rule.host_proxy[0]
}

moved {
  from = aws_vpc_security_group_egress_rule.nlb_to_hosts
  to   = aws_vpc_security_group_egress_rule.nlb_to_hosts[0]
}
