# EFS Module

This module creates an AWS EFS file system inside a VPC with mount targets, security groups, automatic backups, lifecycle management, and an optional access point.

## Features

- Encrypted EFS file system (SSE with the AWS managed key or a customer KMS key)
- One mount target per subnet, placed in the subnets you provide
- Client security group pattern: workloads attach a managed client security group to gain NFS access, so no security group rules need to change when consumers come and go
- Additional allowed security groups and IPv4/IPv6 CIDR blocks for external clients
- Automatic backups through AWS Backup (enabled by default)
- Lifecycle policies for Infrequent Access, Archive, and transition back to Standard storage
- Bursting, elastic, or provisioned throughput modes
- Optional access point with POSIX user and root directory creation info
- Automatic tag propagation with module defaults

## Usage

### Basic File System

```hcl
module "efs" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//storage/efs?ref=v1.0.0"

  name       = "my-app-files"
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  tags = {
    Environment = "production"
  }
}
```

Attach `module.efs.client_security_group_id` to any workload that should mount the file system.

### File System with Access Point

```hcl
module "efs" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//storage/efs?ref=v1.0.0"

  name       = "my-app-files"
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  access_point_enabled             = true
  access_point_root_directory_path = "/uploads"
  access_point_posix_uid           = 1000
  access_point_posix_gid           = 1000
  access_point_permissions         = "755"
}
```

### Lifecycle Management and Provisioned Throughput

```hcl
module "efs" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//storage/efs?ref=v1.0.0"

  name       = "my-app-files"
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  throughput_mode                 = "provisioned"
  provisioned_throughput_in_mibps = 128

  transition_to_ia                    = "AFTER_30_DAYS"
  transition_to_archive               = "AFTER_90_DAYS"
  transition_to_primary_storage_class = "AFTER_1_ACCESS"
}
```

## Security Model

The module creates two security groups:

- **Mount-target security group** (`security_group_id`): attached to every mount target. Allows NFS (TCP 2049) only from the client security group, plus any `allowed_security_group_ids` and `allowed_cidr_blocks` you configure.
- **Client security group** (`client_security_group_id`): carries no ingress rules. Attach it to ECS tasks, Lambda functions, or EC2 instances that need to mount the file system.

This keeps NFS access closed by default and avoids editing the mount-target security group each time a new consumer appears.

## Requirements

| Name | Version |
|------|---------|
| opentofu/terraform | >= 1.10.0 |
| aws | >= 6.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Name prefix for all EFS resources; also the file system creation token | `string` | n/a | yes |
| vpc_id | VPC for mount targets and security groups | `string` | n/a | yes |
| subnet_ids | Subnets for mount targets, one per subnet | `list(string)` | n/a | yes |
| region | AWS region; provider default when null | `string` | `null` | no |
| encrypted | Enable encryption at rest | `bool` | `true` | no |
| kms_key_id | KMS key ARN for encryption at rest | `string` | `null` | no |
| performance_mode | generalPurpose or maxIO | `string` | `"generalPurpose"` | no |
| throughput_mode | bursting, elastic, or provisioned | `string` | `"bursting"` | no |
| provisioned_throughput_in_mibps | Throughput in MiB/s for provisioned mode | `number` | `null` | no |
| transition_to_ia | Lifecycle transition to Infrequent Access | `string` | `null` | no |
| transition_to_archive | Lifecycle transition to Archive (requires transition_to_ia) | `string` | `null` | no |
| transition_to_primary_storage_class | Transition back to Standard on access (AFTER_1_ACCESS) | `string` | `null` | no |
| backup_enabled | Enable automatic backups through AWS Backup | `bool` | `true` | no |
| access_point_enabled | Create an EFS access point | `bool` | `false` | no |
| access_point_root_directory_path | Root directory exposed through the access point | `string` | `"/data"` | no |
| access_point_posix_uid | POSIX user ID for access point requests and directory ownership | `number` | `1000` | no |
| access_point_posix_gid | POSIX group ID for access point requests and directory ownership | `number` | `1000` | no |
| access_point_permissions | Octal permissions for the created root directory | `string` | `"755"` | no |
| allowed_security_group_ids | Additional security groups allowed NFS access | `list(string)` | `[]` | no |
| allowed_cidr_blocks | IPv4 CIDR blocks allowed NFS access | `list(string)` | `[]` | no |
| allowed_ipv6_cidr_blocks | IPv6 CIDR blocks allowed NFS access | `list(string)` | `[]` | no |
| tags | Additional tags for all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| file_system_id | The ID of the EFS file system |
| file_system_arn | The ARN of the EFS file system |
| file_system_dns_name | The DNS name of the EFS file system |
| mount_target_ids | Map of subnet ID to mount target ID |
| access_point_id | The ID of the EFS access point, or null |
| access_point_arn | The ARN of the EFS access point, or null |
| security_group_id | The ID of the mount-target security group |
| security_group_arn | The ARN of the mount-target security group |
| client_security_group_id | The ID of the client security group to attach to consumers |
| client_security_group_arn | The ARN of the client security group |
| aws_account_id | The AWS account ID where the resources are deployed |
| region | The AWS region where the resources are deployed |
