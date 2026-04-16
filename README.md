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
| `cache/`      | `elasticache`     | AWS ElastiCache clusters (Redis, Valkey, Memcached)                    | v1.0.0  |
| `cdn/`        | `cloudfront`      | AWS CloudFront distributions                                           | v1.0.0  |
| `compute/`    | `autoscaling`     | AWS Auto Scaling groups                                                | v1.0.0  |
| `compute/`    | `ec2`             | AWS EC2 instances                                                      | Planned |
| `compute/`    | `ecs_cluster`     | AWS ECS clusters with Fargate/EC2 capacity providers and optional ALBs | v1.0.0  |
| `compute/`    | `ecs_service`     | AWS ECS services with task definitions, load balancing, and auto scaling | v1.0.0  |
| `compute/`    | `lambda`          | AWS Lambda functions                                                   | v1.0.0  |
| `database/`   | `aurora`          | AWS Aurora clusters (MySQL, PostgreSQL, Serverless v2, Global Database) | v1.0.0  |
| `database/`   | `dynamodb`        | AWS DynamoDB tables                                                    | v1.0.0  |
| `database/`   | `rds`             | AWS RDS instances                                                      | v1.0.0  |
| `kubernetes/` | -                 | Kubernetes resources                                                   | Planned |
| `messaging/`  | `sns`             | AWS SNS topics and subscriptions                                       | Planned |
| `messaging/`  | `sqs`             | AWS SQS queues                                                         | Planned |
| `monitoring/` | `cloudwatch`      | AWS CloudWatch alarms and dashboards                                   | Planned |
| `networking/` | `alb`             | AWS Application Load Balancers                                         | v1.0.0  |
| `networking/` | `nlb`             | AWS Network Load Balancers                                             | v1.0.0  |
| `networking/` | `route53`         | AWS Route53 hosted zones and records                                   | v1.0.0  |
| `networking/` | `security-groups` | AWS Security Groups                                                    | v1.0.0  |
| `networking/` | `vpc`             | AWS VPC and subnets                                                    | v1.0.0  |
| `security/`   | `acm_certificate` | AWS ACM public certificates (DNS validation, optional Route53, optional wait) | v1.0.0  |
| `security/`   | `iam`             | AWS IAM roles and policies                                             | v1.0.0  |
| `security/`   | `kms`             | AWS KMS keys                                                           | Planned |
| `security/`   | `secrets-manager` | AWS Secrets Manager secrets                                            | Planned |
| `storage/`    | `ebs`             | AWS EBS volumes                                                        | Planned |
| `storage/`    | `efs`             | AWS EFS file systems                                                   | Planned |
| `storage/`    | `s3`              | AWS S3 buckets                                                         | v1.0.0  |

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

## Testing

This repository uses [Terratest](https://terratest.gruntwork.io/) for integration testing of infrastructure modules. Tests deploy real AWS resources to validate module behavior.

### Prerequisites

Set the following environment variables before running tests:

```bash
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_REGION="us-east-1"  # Optional, defaults to us-east-1
```

### Running Tests

```bash
# Navigate to the test directory
cd test

# Run all tests
go test -v -timeout 60m ./...

# Run a specific test
go test -v -timeout 30m -run TestVpcBasic ./...

# Run tests with parallel limit (recommended for cost control)
go test -v -timeout 60m -parallel 2 ./...
```

### Cost Considerations

Integration tests create real AWS resources which incur costs. Tests clean up resources automatically via `terraform destroy`, but failed tests may leave orphaned resources. Monitor your AWS account for any resources tagged with `Environment=terratest`.

For detailed information about the test architecture and adding new tests, see [TERRATEST_PLAN.md](TERRATEST_PLAN.md).

## License

This project is licensed under the **GNU Affero General Public License v3.0 (AGPL-3.0)**.

See the [LICENSE](LICENSE) file for the full license text.

This means:

- You can use, modify, and distribute this code
- If you modify and use this code (including as a network service), you must make your source code available under the same license
- Commercial use in closed-source projects is not permitted without a separate license agreement
