terraform {
  required_version = ">= 1.10.0"

  cloud {}

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # 6.33.0 is the first release whose `aws_launch_template` exposes
      # `cpu_options.nested_virtualization` (added to `aws_instance` in the same
      # release). Without it there is no way to express the one setting that
      # makes a host a KVM host, so this floor is load-bearing, not cosmetic.
      version = ">= 6.33.0"
    }
  }
}
