mock_provider "aws" {
  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "123456789012"
    }
  }

  override_data {
    target = data.aws_region.current
    values = {
      id     = "us-east-1"
      name   = "us-east-1"
      region = "us-east-1"
    }
  }

  override_data {
    target = data.aws_vpc.this
    values = {
      cidr_block = "10.0.0.0/16"
    }
  }
}

run "test_fresh_cluster_requires_master_credentials" {
  command = plan

  variables {
    name                                    = "test-cluster"
    engine                                  = "aurora-postgresql"
    engine_version                          = "16.4"
    instance_class                          = "db.t4g.medium"
    vpc_id                                  = "vpc-12345678"
    subnet_ids                              = ["subnet-11111111", "subnet-22222222"]
    security_group_creation_enabled         = false
    security_group_id                       = "sg-12345678"
    master_username                         = "dbadmin"
    master_user_password_management_enabled = false
  }

  expect_failures = [
    aws_rds_cluster.this,
  ]
}

run "test_unmanaged_import_password_is_omitted" {
  command = plan

  variables {
    name                                      = "test-cluster"
    engine                                    = "aurora-postgresql"
    engine_version                            = "16.4"
    instance_class                            = "db.t4g.medium"
    vpc_id                                    = "vpc-12345678"
    subnet_ids                                = ["subnet-11111111", "subnet-22222222"]
    security_group_creation_enabled           = false
    security_group_id                         = "sg-12345678"
    master_username                           = "dbadmin"
    master_user_password_management_enabled   = false
    master_user_password_preservation_enabled = true
  }

  assert {
    condition     = aws_rds_cluster.this.manage_master_user_password == null
    error_message = "manage_master_user_password should be omitted when password management is disabled."
  }
}
