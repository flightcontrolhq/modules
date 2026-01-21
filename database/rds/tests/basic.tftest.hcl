################################################################################
# RDS Module Unit Tests
################################################################################

# Mock AWS provider with overridden data sources
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
      id   = "us-east-1"
      name = "us-east-1"
    }
  }

  override_data {
    target = data.aws_vpc.this
    values = {
      id         = "vpc-12345678"
      cidr_block = "10.0.0.0/16"
    }
  }
}

#-------------------------------------------------------------------------------
# Name Validation Tests
#-------------------------------------------------------------------------------

# Test: Valid name - basic
run "test_name_validation_valid_basic" {
  command = plan

  variables {
    name              = "my-test-db"
    engine            = "postgres"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
  }

  assert {
    condition     = var.name == "my-test-db"
    error_message = "Valid name should be accepted."
  }
}

# Test: Valid name - with numbers
run "test_name_validation_valid_with_numbers" {
  command = plan

  variables {
    name              = "db123test"
    engine            = "postgres"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
  }

  assert {
    condition     = var.name == "db123test"
    error_message = "Valid name with numbers should be accepted."
  }
}

# Test: Invalid name - too long (more than 63 characters)
run "test_name_validation_max_length" {
  command = plan

  variables {
    name              = "this-db-name-is-way-too-long-and-exceeds-the-sixty-three-character-limit-set-by-aws"
    engine            = "postgres"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
  }

  expect_failures = [
    var.name,
  ]
}

# Test: Invalid name - empty
run "test_name_validation_empty" {
  command = plan

  variables {
    name              = ""
    engine            = "postgres"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
  }

  expect_failures = [
    var.name,
  ]
}

# Test: Invalid name - starts with number
run "test_name_validation_starts_with_number" {
  command = plan

  variables {
    name              = "123-invalid"
    engine            = "postgres"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
  }

  expect_failures = [
    var.name,
  ]
}

# Test: Invalid name - contains underscores
run "test_name_validation_invalid_underscore" {
  command = plan

  variables {
    name              = "my_test_db"
    engine            = "postgres"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
  }

  expect_failures = [
    var.name,
  ]
}

#-------------------------------------------------------------------------------
# Engine Validation Tests
#-------------------------------------------------------------------------------

# Test: Valid engine - postgres
run "test_engine_validation_postgres" {
  command = plan

  variables {
    name              = "test-db"
    engine            = "postgres"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
  }

  assert {
    condition     = var.engine == "postgres"
    error_message = "postgres engine should be accepted."
  }
}

# Test: Valid engine - mysql
run "test_engine_validation_mysql" {
  command = plan

  variables {
    name              = "test-db"
    engine            = "mysql"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
  }

  assert {
    condition     = var.engine == "mysql"
    error_message = "mysql engine should be accepted."
  }
}

# Test: Valid engine - mariadb
run "test_engine_validation_mariadb" {
  command = plan

  variables {
    name              = "test-db"
    engine            = "mariadb"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
  }

  assert {
    condition     = var.engine == "mariadb"
    error_message = "mariadb engine should be accepted."
  }
}

# Test: Valid engine - oracle-ee
run "test_engine_validation_oracle" {
  command = plan

  variables {
    name              = "test-db"
    engine            = "oracle-ee"
    license_model     = "bring-your-own-license"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
  }

  assert {
    condition     = var.engine == "oracle-ee"
    error_message = "oracle-ee engine should be accepted."
  }
}

# Test: Valid engine - sqlserver-se
run "test_engine_validation_sqlserver" {
  command = plan

  variables {
    name              = "test-db"
    engine            = "sqlserver-se"
    license_model     = "license-included"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
  }

  assert {
    condition     = var.engine == "sqlserver-se"
    error_message = "sqlserver-se engine should be accepted."
  }
}

# Test: Invalid engine
run "test_engine_validation_invalid" {
  command = plan

  variables {
    name              = "test-db"
    engine            = "invalid-engine"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
  }

  expect_failures = [
    var.engine,
  ]
}

#-------------------------------------------------------------------------------
# Instance Class Validation Tests
#-------------------------------------------------------------------------------

# Test: Valid instance class
run "test_instance_class_valid" {
  command = plan

  variables {
    name              = "test-db"
    engine            = "postgres"
    instance_class    = "db.r6g.large"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
  }

  assert {
    condition     = var.instance_class == "db.r6g.large"
    error_message = "Valid instance class should be accepted."
  }
}

# Test: Invalid instance class - missing db. prefix
run "test_instance_class_invalid_no_prefix" {
  command = plan

  variables {
    name              = "test-db"
    engine            = "postgres"
    instance_class    = "t3.micro"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
  }

  expect_failures = [
    var.instance_class,
  ]
}

#-------------------------------------------------------------------------------
# Storage Validation Tests
#-------------------------------------------------------------------------------

# Test: Valid allocated storage
run "test_allocated_storage_valid" {
  command = plan

  variables {
    name              = "test-db"
    engine            = "postgres"
    instance_class    = "db.t3.micro"
    allocated_storage = 100
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
  }

  assert {
    condition     = var.allocated_storage == 100
    error_message = "Valid allocated_storage should be accepted."
  }
}

# Test: Invalid allocated storage - too small
run "test_allocated_storage_too_small" {
  command = plan

  variables {
    name              = "test-db"
    engine            = "postgres"
    instance_class    = "db.t3.micro"
    allocated_storage = 10
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
  }

  expect_failures = [
    var.allocated_storage,
  ]
}

# Test: Valid storage type
run "test_storage_type_valid" {
  command = plan

  variables {
    name              = "test-db"
    engine            = "postgres"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    storage_type      = "io1"
    iops              = 3000
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
  }

  assert {
    condition     = var.storage_type == "io1"
    error_message = "Valid storage_type should be accepted."
  }
}

# Test: Invalid storage type
run "test_storage_type_invalid" {
  command = plan

  variables {
    name              = "test-db"
    engine            = "postgres"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    storage_type      = "invalid"
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
  }

  expect_failures = [
    var.storage_type,
  ]
}

#-------------------------------------------------------------------------------
# Network Validation Tests
#-------------------------------------------------------------------------------

# Test: Valid VPC ID
run "test_vpc_id_valid" {
  command = plan

  variables {
    name              = "test-db"
    engine            = "postgres"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
  }

  assert {
    condition     = var.vpc_id == "vpc-12345678"
    error_message = "Valid vpc_id should be accepted."
  }
}

# Test: Invalid VPC ID
run "test_vpc_id_invalid" {
  command = plan

  variables {
    name              = "test-db"
    engine            = "postgres"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    vpc_id            = "invalid-vpc"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
  }

  expect_failures = [
    var.vpc_id,
  ]
}

# Test: Invalid subnet IDs - only one provided
run "test_subnet_ids_too_few" {
  command = plan

  variables {
    name              = "test-db"
    engine            = "postgres"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111"]
    username          = "admin"
  }

  expect_failures = [
    var.subnet_ids,
  ]
}

# Test: Invalid subnet ID format
run "test_subnet_ids_invalid_format" {
  command = plan

  variables {
    name              = "test-db"
    engine            = "postgres"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["invalid-subnet", "subnet-22222222"]
    username          = "admin"
  }

  expect_failures = [
    var.subnet_ids,
  ]
}

# Test: Valid port
run "test_port_valid" {
  command = plan

  variables {
    name              = "test-db"
    engine            = "postgres"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
    port              = 5433
  }

  assert {
    condition     = var.port == 5433
    error_message = "Valid custom port should be accepted."
  }
}

# Test: Invalid port - out of range
run "test_port_invalid" {
  command = plan

  variables {
    name              = "test-db"
    engine            = "postgres"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
    port              = 70000
  }

  expect_failures = [
    var.port,
  ]
}

#-------------------------------------------------------------------------------
# Security Group Validation Tests
#-------------------------------------------------------------------------------

# Test: Invalid security group ID format
run "test_security_group_id_invalid" {
  command = plan

  variables {
    name                  = "test-db"
    engine                = "postgres"
    instance_class        = "db.t3.micro"
    allocated_storage     = 20
    vpc_id                = "vpc-12345678"
    subnet_ids            = ["subnet-11111111", "subnet-22222222"]
    username              = "admin"
    create_security_group = false
    security_group_id     = "invalid-sg"
  }

  expect_failures = [
    var.security_group_id,
  ]
}

# Test: Valid allowed security group IDs
run "test_allowed_security_group_ids_valid" {
  command = plan

  variables {
    name                       = "test-db"
    engine                     = "postgres"
    instance_class             = "db.t3.micro"
    allocated_storage          = 20
    vpc_id                     = "vpc-12345678"
    subnet_ids                 = ["subnet-11111111", "subnet-22222222"]
    username                   = "admin"
    allowed_security_group_ids = ["sg-11111111", "sg-22222222"]
  }

  assert {
    condition     = length(var.allowed_security_group_ids) == 2
    error_message = "Valid allowed_security_group_ids should be accepted."
  }
}

# Test: Invalid allowed security group ID format
run "test_allowed_security_group_ids_invalid" {
  command = plan

  variables {
    name                       = "test-db"
    engine                     = "postgres"
    instance_class             = "db.t3.micro"
    allocated_storage          = 20
    vpc_id                     = "vpc-12345678"
    subnet_ids                 = ["subnet-11111111", "subnet-22222222"]
    username                   = "admin"
    allowed_security_group_ids = ["invalid-sg"]
  }

  expect_failures = [
    var.allowed_security_group_ids,
  ]
}

# Test: Valid CIDR blocks
run "test_allowed_cidr_blocks_valid" {
  command = plan

  variables {
    name                = "test-db"
    engine              = "postgres"
    instance_class      = "db.t3.micro"
    allocated_storage   = 20
    vpc_id              = "vpc-12345678"
    subnet_ids          = ["subnet-11111111", "subnet-22222222"]
    username            = "admin"
    allowed_cidr_blocks = ["10.0.0.0/24", "192.168.1.0/24"]
  }

  assert {
    condition     = length(var.allowed_cidr_blocks) == 2
    error_message = "Valid allowed_cidr_blocks should be accepted."
  }
}

# Test: Invalid CIDR block format
run "test_allowed_cidr_blocks_invalid" {
  command = plan

  variables {
    name                = "test-db"
    engine              = "postgres"
    instance_class      = "db.t3.micro"
    allocated_storage   = 20
    vpc_id              = "vpc-12345678"
    subnet_ids          = ["subnet-11111111", "subnet-22222222"]
    username            = "admin"
    allowed_cidr_blocks = ["invalid-cidr"]
  }

  expect_failures = [
    var.allowed_cidr_blocks,
  ]
}

#-------------------------------------------------------------------------------
# Username Validation Tests
#-------------------------------------------------------------------------------

# Test: Valid username
run "test_username_valid" {
  command = plan

  variables {
    name              = "test-db"
    engine            = "postgres"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "db_admin"
  }

  assert {
    condition     = var.username == "db_admin"
    error_message = "Valid username should be accepted."
  }
}

# Test: Invalid username - starts with number
run "test_username_invalid_starts_with_number" {
  command = plan

  variables {
    name              = "test-db"
    engine            = "postgres"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "1admin"
  }

  expect_failures = [
    var.username,
  ]
}

# Test: Invalid username - contains hyphen
run "test_username_invalid_hyphen" {
  command = plan

  variables {
    name              = "test-db"
    engine            = "postgres"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "db-admin"
  }

  expect_failures = [
    var.username,
  ]
}

#-------------------------------------------------------------------------------
# KMS Key Validation Tests
#-------------------------------------------------------------------------------

# Test: Valid KMS key ARN
run "test_kms_key_id_valid" {
  command = plan

  variables {
    name              = "test-db"
    engine            = "postgres"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
    kms_key_id        = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
  }

  assert {
    condition     = var.kms_key_id != null
    error_message = "Valid KMS key ARN should be accepted."
  }
}

# Test: Invalid KMS key ARN
run "test_kms_key_id_invalid" {
  command = plan

  variables {
    name              = "test-db"
    engine            = "postgres"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
    kms_key_id        = "invalid-key"
  }

  expect_failures = [
    var.kms_key_id,
  ]
}

#-------------------------------------------------------------------------------
# Monitoring Interval Validation Tests
#-------------------------------------------------------------------------------

# Test: Valid monitoring interval
run "test_monitoring_interval_valid" {
  command = plan

  variables {
    name                = "test-db"
    engine              = "postgres"
    instance_class      = "db.t3.micro"
    allocated_storage   = 20
    vpc_id              = "vpc-12345678"
    subnet_ids          = ["subnet-11111111", "subnet-22222222"]
    username            = "admin"
    monitoring_interval = 60
  }

  assert {
    condition     = var.monitoring_interval == 60
    error_message = "Valid monitoring_interval should be accepted."
  }
}

# Test: Invalid monitoring interval
run "test_monitoring_interval_invalid" {
  command = plan

  variables {
    name                = "test-db"
    engine              = "postgres"
    instance_class      = "db.t3.micro"
    allocated_storage   = 20
    vpc_id              = "vpc-12345678"
    subnet_ids          = ["subnet-11111111", "subnet-22222222"]
    username            = "admin"
    monitoring_interval = 45
  }

  expect_failures = [
    var.monitoring_interval,
  ]
}

#-------------------------------------------------------------------------------
# Backup Retention Period Validation Tests
#-------------------------------------------------------------------------------

# Test: Valid backup retention period
run "test_backup_retention_period_valid" {
  command = plan

  variables {
    name                    = "test-db"
    engine                  = "postgres"
    instance_class          = "db.t3.micro"
    allocated_storage       = 20
    vpc_id                  = "vpc-12345678"
    subnet_ids              = ["subnet-11111111", "subnet-22222222"]
    username                = "admin"
    backup_retention_period = 14
  }

  assert {
    condition     = var.backup_retention_period == 14
    error_message = "Valid backup_retention_period should be accepted."
  }
}

# Test: Invalid backup retention period - too high
run "test_backup_retention_period_invalid" {
  command = plan

  variables {
    name                    = "test-db"
    engine                  = "postgres"
    instance_class          = "db.t3.micro"
    allocated_storage       = 20
    vpc_id                  = "vpc-12345678"
    subnet_ids              = ["subnet-11111111", "subnet-22222222"]
    username                = "admin"
    backup_retention_period = 40
  }

  expect_failures = [
    var.backup_retention_period,
  ]
}

#-------------------------------------------------------------------------------
# Security-First Default Tests
#-------------------------------------------------------------------------------

# Test: storage_encrypted defaults to true
run "test_storage_encrypted_default" {
  command = plan

  variables {
    name              = "test-db"
    engine            = "postgres"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
  }

  assert {
    condition     = var.storage_encrypted == true
    error_message = "storage_encrypted should default to true."
  }
}

# Test: deletion_protection defaults to true
run "test_deletion_protection_default" {
  command = plan

  variables {
    name              = "test-db"
    engine            = "postgres"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
  }

  assert {
    condition     = var.deletion_protection == true
    error_message = "deletion_protection should default to true."
  }
}

# Test: backup_retention_period defaults to 7
run "test_backup_retention_period_default" {
  command = plan

  variables {
    name              = "test-db"
    engine            = "postgres"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
  }

  assert {
    condition     = var.backup_retention_period == 7
    error_message = "backup_retention_period should default to 7."
  }
}

# Test: manage_master_user_password defaults to true
run "test_manage_master_user_password_default" {
  command = plan

  variables {
    name              = "test-db"
    engine            = "postgres"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
  }

  assert {
    condition     = var.manage_master_user_password == true
    error_message = "manage_master_user_password should default to true."
  }
}

# Test: performance_insights_enabled defaults to true
run "test_performance_insights_enabled_default" {
  command = plan

  variables {
    name              = "test-db"
    engine            = "postgres"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
  }

  assert {
    condition     = var.performance_insights_enabled == true
    error_message = "performance_insights_enabled should default to true."
  }
}

# Test: publicly_accessible defaults to false
run "test_publicly_accessible_default" {
  command = plan

  variables {
    name              = "test-db"
    engine            = "postgres"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
  }

  assert {
    condition     = var.publicly_accessible == false
    error_message = "publicly_accessible should default to false."
  }
}

# Test: skip_final_snapshot defaults to false
run "test_skip_final_snapshot_default" {
  command = plan

  variables {
    name              = "test-db"
    engine            = "postgres"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
  }

  assert {
    condition     = var.skip_final_snapshot == false
    error_message = "skip_final_snapshot should default to false."
  }
}

# Test: storage_type defaults to gp3
run "test_storage_type_default" {
  command = plan

  variables {
    name              = "test-db"
    engine            = "postgres"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
  }

  assert {
    condition     = var.storage_type == "gp3"
    error_message = "storage_type should default to gp3."
  }
}

#-------------------------------------------------------------------------------
# Engine Detection Tests (Local Values)
#-------------------------------------------------------------------------------

# Test: PostgreSQL port defaults to 5432
run "test_postgres_port_default" {
  command = plan

  variables {
    name              = "test-db"
    engine            = "postgres"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
  }

  assert {
    condition     = local.port == 5432
    error_message = "PostgreSQL port should default to 5432."
  }

  assert {
    condition     = local.is_postgres == true
    error_message = "is_postgres should be true for postgres engine."
  }
}

# Test: MySQL port defaults to 3306
run "test_mysql_port_default" {
  command = plan

  variables {
    name              = "test-db"
    engine            = "mysql"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
  }

  assert {
    condition     = local.port == 3306
    error_message = "MySQL port should default to 3306."
  }

  assert {
    condition     = local.is_mysql == true
    error_message = "is_mysql should be true for mysql engine."
  }
}

# Test: MariaDB port defaults to 3306
run "test_mariadb_port_default" {
  command = plan

  variables {
    name              = "test-db"
    engine            = "mariadb"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
  }

  assert {
    condition     = local.port == 3306
    error_message = "MariaDB port should default to 3306."
  }

  assert {
    condition     = local.is_mariadb == true
    error_message = "is_mariadb should be true for mariadb engine."
  }
}

# Test: Oracle port defaults to 1521
run "test_oracle_port_default" {
  command = plan

  variables {
    name              = "test-db"
    engine            = "oracle-ee"
    license_model     = "bring-your-own-license"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
  }

  assert {
    condition     = local.port == 1521
    error_message = "Oracle port should default to 1521."
  }

  assert {
    condition     = local.is_oracle == true
    error_message = "is_oracle should be true for oracle-ee engine."
  }
}

# Test: SQL Server port defaults to 1433
run "test_sqlserver_port_default" {
  command = plan

  variables {
    name              = "test-db"
    engine            = "sqlserver-se"
    license_model     = "license-included"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
  }

  assert {
    condition     = local.port == 1433
    error_message = "SQL Server port should default to 1433."
  }

  assert {
    condition     = local.is_sqlserver == true
    error_message = "is_sqlserver should be true for sqlserver-se engine."
  }
}

# Test: Custom port overrides default
run "test_custom_port_override" {
  command = plan

  variables {
    name              = "test-db"
    engine            = "postgres"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
    port              = 5433
  }

  assert {
    condition     = local.port == 5433
    error_message = "Custom port should override default."
  }
}

#-------------------------------------------------------------------------------
# Conditional Resource Creation Tests
#-------------------------------------------------------------------------------

# Test: Security group is created by default
run "test_security_group_created_by_default" {
  command = plan

  variables {
    name              = "test-db"
    engine            = "postgres"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
  }

  assert {
    condition     = local.create_security_group == true
    error_message = "Security group should be created by default."
  }
}

# Test: Security group is not created when create_security_group is false
run "test_security_group_not_created" {
  command = plan

  variables {
    name                  = "test-db"
    engine                = "postgres"
    instance_class        = "db.t3.micro"
    allocated_storage     = 20
    vpc_id                = "vpc-12345678"
    subnet_ids            = ["subnet-11111111", "subnet-22222222"]
    username              = "admin"
    create_security_group = false
    security_group_id     = "sg-12345678"
  }

  assert {
    condition     = local.create_security_group == false
    error_message = "Security group should not be created when create_security_group is false."
  }
}

# Test: Parameter group is created by default
run "test_parameter_group_created_by_default" {
  command = plan

  variables {
    name              = "test-db"
    engine            = "postgres"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
  }

  assert {
    condition     = local.create_parameter_group == true
    error_message = "Parameter group should be created by default."
  }
}

# Test: Option group is created for Oracle when enabled
run "test_option_group_created_for_oracle" {
  command = plan

  variables {
    name                = "test-db"
    engine              = "oracle-ee"
    license_model       = "bring-your-own-license"
    instance_class      = "db.t3.micro"
    allocated_storage   = 20
    vpc_id              = "vpc-12345678"
    subnet_ids          = ["subnet-11111111", "subnet-22222222"]
    username            = "admin"
    create_option_group = true
  }

  assert {
    condition     = local.create_option_group == true
    error_message = "Option group should be created for Oracle when enabled."
  }
}

# Test: Option group is created for SQL Server when enabled
run "test_option_group_created_for_sqlserver" {
  command = plan

  variables {
    name                = "test-db"
    engine              = "sqlserver-se"
    license_model       = "license-included"
    instance_class      = "db.t3.micro"
    allocated_storage   = 20
    vpc_id              = "vpc-12345678"
    subnet_ids          = ["subnet-11111111", "subnet-22222222"]
    username            = "admin"
    create_option_group = true
  }

  assert {
    condition     = local.create_option_group == true
    error_message = "Option group should be created for SQL Server when enabled."
  }
}

# Test: Option group is NOT created for PostgreSQL even when enabled
run "test_option_group_not_created_for_postgres" {
  command = plan

  variables {
    name                = "test-db"
    engine              = "postgres"
    instance_class      = "db.t3.micro"
    allocated_storage   = 20
    vpc_id              = "vpc-12345678"
    subnet_ids          = ["subnet-11111111", "subnet-22222222"]
    username            = "admin"
    create_option_group = true
  }

  assert {
    condition     = local.create_option_group == false
    error_message = "Option group should NOT be created for PostgreSQL."
  }
}

# Test: Monitoring role is created when monitoring_interval > 0
run "test_monitoring_role_created" {
  command = plan

  variables {
    name                = "test-db"
    engine              = "postgres"
    instance_class      = "db.t3.micro"
    allocated_storage   = 20
    vpc_id              = "vpc-12345678"
    subnet_ids          = ["subnet-11111111", "subnet-22222222"]
    username            = "admin"
    monitoring_interval = 60
  }

  assert {
    condition     = local.create_monitoring_role == true
    error_message = "Monitoring role should be created when monitoring_interval > 0."
  }
}

# Test: Monitoring role is NOT created when monitoring_interval is 0
run "test_monitoring_role_not_created" {
  command = plan

  variables {
    name                = "test-db"
    engine              = "postgres"
    instance_class      = "db.t3.micro"
    allocated_storage   = 20
    vpc_id              = "vpc-12345678"
    subnet_ids          = ["subnet-11111111", "subnet-22222222"]
    username            = "admin"
    monitoring_interval = 0
  }

  assert {
    condition     = local.create_monitoring_role == false
    error_message = "Monitoring role should NOT be created when monitoring_interval is 0."
  }
}

#-------------------------------------------------------------------------------
# Read Replica Tests
#-------------------------------------------------------------------------------

# Test: Read replicas are not created by default
run "test_read_replicas_not_created_by_default" {
  command = plan

  variables {
    name              = "test-db"
    engine            = "postgres"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
  }

  assert {
    condition     = local.create_read_replicas == false
    error_message = "Read replicas should not be created by default."
  }

  assert {
    condition     = local.read_replica_count == 0
    error_message = "Read replica count should be 0 by default."
  }
}

# Test: Read replicas are created when enabled
run "test_read_replicas_created_when_enabled" {
  command = plan

  variables {
    name                = "test-db"
    engine              = "postgres"
    instance_class      = "db.t3.micro"
    allocated_storage   = 20
    vpc_id              = "vpc-12345678"
    subnet_ids          = ["subnet-11111111", "subnet-22222222"]
    username            = "admin"
    create_read_replica = true
    read_replica_count  = 2
  }

  assert {
    condition     = local.create_read_replicas == true
    error_message = "Read replicas should be created when enabled."
  }

  assert {
    condition     = local.read_replica_count == 2
    error_message = "Read replica count should match var.read_replica_count."
  }
}

# Test: Read replica instance class defaults to primary instance class
run "test_read_replica_instance_class_default" {
  command = plan

  variables {
    name                = "test-db"
    engine              = "postgres"
    instance_class      = "db.r6g.large"
    allocated_storage   = 20
    vpc_id              = "vpc-12345678"
    subnet_ids          = ["subnet-11111111", "subnet-22222222"]
    username            = "admin"
    create_read_replica = true
  }

  assert {
    condition     = local.read_replica_instance_class == "db.r6g.large"
    error_message = "Read replica instance class should default to primary instance class."
  }
}

# Test: Read replica instance class can be overridden
run "test_read_replica_instance_class_override" {
  command = plan

  variables {
    name                        = "test-db"
    engine                      = "postgres"
    instance_class              = "db.r6g.large"
    allocated_storage           = 20
    vpc_id                      = "vpc-12345678"
    subnet_ids                  = ["subnet-11111111", "subnet-22222222"]
    username                    = "admin"
    create_read_replica         = true
    read_replica_instance_class = "db.t3.medium"
  }

  assert {
    condition     = local.read_replica_instance_class == "db.t3.medium"
    error_message = "Read replica instance class should be overridden when specified."
  }
}

#-------------------------------------------------------------------------------
# IAM Database Authentication Tests
#-------------------------------------------------------------------------------

# Test: IAM database authentication is enabled for PostgreSQL
run "test_iam_auth_enabled_postgres" {
  command = plan

  variables {
    name                                = "test-db"
    engine                              = "postgres"
    instance_class                      = "db.t3.micro"
    allocated_storage                   = 20
    vpc_id                              = "vpc-12345678"
    subnet_ids                          = ["subnet-11111111", "subnet-22222222"]
    username                            = "admin"
    iam_database_authentication_enabled = true
  }

  assert {
    condition     = local.iam_database_authentication_enabled == true
    error_message = "IAM database authentication should be enabled for PostgreSQL."
  }
}

# Test: IAM database authentication is enabled for MySQL
run "test_iam_auth_enabled_mysql" {
  command = plan

  variables {
    name                                = "test-db"
    engine                              = "mysql"
    instance_class                      = "db.t3.micro"
    allocated_storage                   = 20
    vpc_id                              = "vpc-12345678"
    subnet_ids                          = ["subnet-11111111", "subnet-22222222"]
    username                            = "admin"
    iam_database_authentication_enabled = true
  }

  assert {
    condition     = local.iam_database_authentication_enabled == true
    error_message = "IAM database authentication should be enabled for MySQL."
  }
}

# Test: IAM database authentication is filtered for unsupported engines
run "test_iam_auth_filtered_for_oracle" {
  command = plan

  variables {
    name                                = "test-db"
    engine                              = "oracle-ee"
    license_model                       = "bring-your-own-license"
    instance_class                      = "db.t3.micro"
    allocated_storage                   = 20
    vpc_id                              = "vpc-12345678"
    subnet_ids                          = ["subnet-11111111", "subnet-22222222"]
    username                            = "admin"
    iam_database_authentication_enabled = true
  }

  assert {
    condition     = local.iam_database_authentication_enabled == false
    error_message = "IAM database authentication should be filtered for Oracle (not supported)."
  }
}

#-------------------------------------------------------------------------------
# SQL Server db_name Handling Tests
#-------------------------------------------------------------------------------

# Test: db_name is passed through for PostgreSQL
run "test_db_name_passed_postgres" {
  command = plan

  variables {
    name              = "test-db"
    engine            = "postgres"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
    db_name           = "mydb"
  }

  assert {
    condition     = local.db_name == "mydb"
    error_message = "db_name should be passed through for PostgreSQL."
  }
}

# Test: db_name is set to null for SQL Server
run "test_db_name_null_for_sqlserver" {
  command = plan

  variables {
    name              = "test-db"
    engine            = "sqlserver-se"
    license_model     = "license-included"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
    db_name           = "mydb"
  }

  assert {
    condition     = local.db_name == null
    error_message = "db_name should be null for SQL Server."
  }
}

#-------------------------------------------------------------------------------
# Final Snapshot Identifier Tests
#-------------------------------------------------------------------------------

# Test: Final snapshot identifier is auto-generated when skip_final_snapshot is false
run "test_final_snapshot_identifier_auto_generated" {
  command = plan

  variables {
    name                = "test-db"
    engine              = "postgres"
    instance_class      = "db.t3.micro"
    allocated_storage   = 20
    vpc_id              = "vpc-12345678"
    subnet_ids          = ["subnet-11111111", "subnet-22222222"]
    username            = "admin"
    skip_final_snapshot = false
  }

  assert {
    condition     = local.final_snapshot_identifier == "test-db-final-snapshot"
    error_message = "Final snapshot identifier should be auto-generated."
  }
}

# Test: Final snapshot identifier is null when skip_final_snapshot is true
run "test_final_snapshot_identifier_null_when_skipped" {
  command = plan

  variables {
    name                = "test-db"
    engine              = "postgres"
    instance_class      = "db.t3.micro"
    allocated_storage   = 20
    vpc_id              = "vpc-12345678"
    subnet_ids          = ["subnet-11111111", "subnet-22222222"]
    username            = "admin"
    skip_final_snapshot = true
  }

  assert {
    condition     = local.final_snapshot_identifier == null
    error_message = "Final snapshot identifier should be null when skip_final_snapshot is true."
  }
}

# Test: Custom final snapshot identifier is used
run "test_final_snapshot_identifier_custom" {
  command = plan

  variables {
    name                      = "test-db"
    engine                    = "postgres"
    instance_class            = "db.t3.micro"
    allocated_storage         = 20
    vpc_id                    = "vpc-12345678"
    subnet_ids                = ["subnet-11111111", "subnet-22222222"]
    username                  = "admin"
    skip_final_snapshot       = false
    final_snapshot_identifier = "my-custom-snapshot"
  }

  assert {
    condition     = local.final_snapshot_identifier == "my-custom-snapshot"
    error_message = "Custom final snapshot identifier should be used."
  }
}

#-------------------------------------------------------------------------------
# Tags Tests
#-------------------------------------------------------------------------------

# Test: Default tags are applied
run "test_default_tags" {
  command = plan

  variables {
    name              = "test-db"
    engine            = "postgres"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
  }

  assert {
    condition     = local.tags["ManagedBy"] == "terraform"
    error_message = "ManagedBy default tag should be set."
  }

  assert {
    condition     = local.tags["Module"] == "database/rds"
    error_message = "Module default tag should be set."
  }
}

# Test: Custom tags are merged with defaults
run "test_custom_tags_merged" {
  command = plan

  variables {
    name              = "test-db"
    engine            = "postgres"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
    tags = {
      Environment = "production"
      Team        = "platform"
    }
  }

  assert {
    condition     = local.tags["ManagedBy"] == "terraform"
    error_message = "ManagedBy default tag should still be set."
  }

  assert {
    condition     = local.tags["Environment"] == "production"
    error_message = "Custom Environment tag should be set."
  }

  assert {
    condition     = local.tags["Team"] == "platform"
    error_message = "Custom Team tag should be set."
  }
}

#-------------------------------------------------------------------------------
# RDS Instance Resource Tests
#-------------------------------------------------------------------------------

# Test: RDS instance is created with correct identifier
run "test_rds_instance_identifier" {
  command = plan

  variables {
    name              = "my-test-db"
    engine            = "postgres"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
  }

  assert {
    condition     = aws_db_instance.this.identifier == "my-test-db"
    error_message = "RDS instance should have the correct identifier."
  }
}

# Test: RDS instance has correct engine
run "test_rds_instance_engine" {
  command = plan

  variables {
    name              = "test-db"
    engine            = "postgres"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
  }

  assert {
    condition     = aws_db_instance.this.engine == "postgres"
    error_message = "RDS instance should have postgres engine."
  }
}

# Test: RDS instance has correct instance class
run "test_rds_instance_instance_class" {
  command = plan

  variables {
    name              = "test-db"
    engine            = "postgres"
    instance_class    = "db.r6g.large"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
  }

  assert {
    condition     = aws_db_instance.this.instance_class == "db.r6g.large"
    error_message = "RDS instance should have the correct instance class."
  }
}

# Test: RDS instance has storage encrypted by default
run "test_rds_instance_storage_encrypted" {
  command = plan

  variables {
    name              = "test-db"
    engine            = "postgres"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
  }

  assert {
    condition     = aws_db_instance.this.storage_encrypted == true
    error_message = "RDS instance should have storage encryption enabled by default."
  }
}

# Test: RDS instance has deletion protection by default
run "test_rds_instance_deletion_protection" {
  command = plan

  variables {
    name              = "test-db"
    engine            = "postgres"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
  }

  assert {
    condition     = aws_db_instance.this.deletion_protection == true
    error_message = "RDS instance should have deletion protection enabled by default."
  }
}

# Test: RDS instance has multi_az disabled by default
run "test_rds_instance_multi_az_default" {
  command = plan

  variables {
    name              = "test-db"
    engine            = "postgres"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
  }

  assert {
    condition     = aws_db_instance.this.multi_az == false
    error_message = "RDS instance should have multi_az disabled by default."
  }
}

# Test: RDS instance can have multi_az enabled
run "test_rds_instance_multi_az_enabled" {
  command = plan

  variables {
    name              = "test-db"
    engine            = "postgres"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
    multi_az          = true
  }

  assert {
    condition     = aws_db_instance.this.multi_az == true
    error_message = "RDS instance should have multi_az enabled when specified."
  }
}

# Test: RDS instance Name tag is set correctly
run "test_rds_instance_name_tag" {
  command = plan

  variables {
    name              = "my-test-db"
    engine            = "postgres"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
  }

  assert {
    condition     = aws_db_instance.this.tags["Name"] == "my-test-db"
    error_message = "RDS instance should have Name tag set correctly."
  }
}

#-------------------------------------------------------------------------------
# Subnet Group Tests
#-------------------------------------------------------------------------------

# Test: Subnet group is created with correct name
run "test_subnet_group_name" {
  command = plan

  variables {
    name              = "my-test-db"
    engine            = "postgres"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222"]
    username          = "admin"
  }

  assert {
    condition     = aws_db_subnet_group.this.name == "my-test-db"
    error_message = "Subnet group should have the correct name."
  }
}

# Test: Subnet group has correct subnet IDs
run "test_subnet_group_subnet_ids" {
  command = plan

  variables {
    name              = "test-db"
    engine            = "postgres"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-11111111", "subnet-22222222", "subnet-33333333"]
    username          = "admin"
  }

  assert {
    condition     = length(aws_db_subnet_group.this.subnet_ids) == 3
    error_message = "Subnet group should have 3 subnet IDs."
  }
}
