# Ravion Modules

OpenTofu/Terraform module library for [Flightcontrol](https://www.flightcontrol.dev/).

## Overview

This repository contains reusable infrastructure modules designed for enterprise-grade deployments. All modules follow OpenTofu/Terraform best practices and are optimized for use with Flightcontrol's module system.

### Compatibility

- **OpenTofu**: >= 1.10.0
- **Terraform**: >= 1.5.0

## Module Directory

| Category      | Module            | Description                                                            | Status  |
| ------------- | ----------------- | ---------------------------------------------------------------------- | ------- |
| `cache/`      | `elasticache`     | AWS ElastiCache clusters                                               | Planned |
| `cdn/`        | `cloudfront`      | AWS CloudFront distributions                                           | Planned |
| `compute/`    | `autoscaling`     | AWS Auto Scaling groups                                                | Planned |
| `compute/`    | `ec2`             | AWS EC2 instances                                                      | Planned |
| `compute/`    | `ecs`             | AWS ECS clusters with Fargate/EC2 capacity providers and optional ALBs | v1.0.0  |
| `compute/`    | `lambda`          | AWS Lambda functions                                                   | Planned |
| `database/`   | `aurora`          | AWS Aurora clusters                                                    | Planned |
| `database/`   | `dynamodb`        | AWS DynamoDB tables                                                    | Planned |
| `database/`   | `rds`             | AWS RDS instances                                                      | Planned |
| `kubernetes/` | -                 | Kubernetes resources                                                   | Planned |
| `messaging/`  | `sns`             | AWS SNS topics and subscriptions                                       | Planned |
| `messaging/`  | `sqs`             | AWS SQS queues                                                         | Planned |
| `monitoring/` | `cloudwatch`      | AWS CloudWatch alarms and dashboards                                   | Planned |
| `networking/` | `alb`             | AWS Application Load Balancers                                         | v1.0.0  |
| `networking/` | `nlb`             | AWS Network Load Balancers                                             | Planned |
| `networking/` | `route53`         | AWS Route53 hosted zones and records                                   | Planned |
| `networking/` | `security-group`  | AWS Security Groups                                                    | Planned |
| `networking/` | `vpc`             | AWS VPC and subnets                                                    | v1.0.0  |
| `security/`   | `iam`             | AWS IAM roles and policies                                             | Planned |
| `security/`   | `kms`             | AWS KMS keys                                                           | Planned |
| `security/`   | `secrets-manager` | AWS Secrets Manager secrets                                            | Planned |
| `storage/`    | `ebs`             | AWS EBS volumes                                                        | Planned |
| `storage/`    | `efs`             | AWS EFS file systems                                                   | Planned |
| `storage/`    | `s3`              | AWS S3 buckets                                                         | Planned |

## Usage

Reference modules using Git URLs with version pinning:

```hcl
module "sqs_queue" {
  source = "git::https://github.com/flightcontrolhq/modules.git//messaging/sqs?ref=v1.0.0"

  # Module inputs
  name = "my-queue"
  # ...
}
```

### Version Pinning

Always pin to a specific version using Git tags:

```hcl
# Recommended: Pin to exact version
source = "git::https://github.com/flightcontrolhq/modules.git//messaging/sqs?ref=v1.0.0"

# Alternative: Pin to major version branch (if available)
source = "git::https://github.com/flightcontrolhq/modules.git//messaging/sqs?ref=v1"
```

## Module Standards

Each module in this repository follows a consistent structure:

```
<category>/<module-name>/
├── main.tf          # Primary resource definitions
├── variables.tf     # Input variables with descriptions and validation
├── outputs.tf       # Output values with descriptions
├── versions.tf      # Provider and OpenTofu version constraints
└── README.md        # Module documentation with usage examples
```

### Requirements

- All variables must have `description` and `type`
- All variables should have `validation` blocks where applicable
- All outputs must have `description`
- Resources must follow consistent naming conventions
- Security best practices must be followed (no hardcoded secrets, least privilege IAM)

## Contributing

### Adding a New Module

1. Create a new directory following the `<category>/<module-name>` structure
2. Include all required files (`main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`, `README.md`)
3. Ensure all variables and outputs have descriptions
4. Add validation rules for variables where applicable
5. Include usage examples in the module's README
6. **Update this README's Module Directory table**
7. Run `tofu fmt` and `tofu validate` before committing

### Versioning

This repository follows [Semantic Versioning](https://semver.org/):

- **MAJOR**: Breaking changes (removed variables, renamed resources, changed defaults that affect behavior)
- **MINOR**: New features, new modules, new optional variables
- **PATCH**: Bug fixes, documentation updates

## License

This project is licensed under the **GNU Affero General Public License v3.0 (AGPL-3.0)**.

See the [LICENSE](LICENSE) file for the full license text.

This means:

- You can use, modify, and distribute this code
- If you modify and use this code (including as a network service), you must make your source code available under the same license
- Commercial use in closed-source projects is not permitted without a separate license agreement
