# Terratest Integration Tests

This directory contains [Terratest](https://terratest.gruntwork.io/) integration tests for the Terraform modules in this repository. These tests provision real AWS infrastructure, validate it works correctly, and then destroy it.

## Directory Structure

```
test/
├── README.md              # This file
├── go.mod                 # Go module definition
├── go.sum                 # Go dependency checksums
├── helpers/               # Shared helper functions
│   ├── aws.go             # AWS SDK helper functions
│   ├── random.go          # Random name generation helpers
│   └── tags.go            # Tag validation helpers
├── fixtures/              # Terraform configurations for testing
│   ├── alb/               # ALB module fixtures
│   │   ├── basic/
│   │   ├── with_https/
│   │   ├── with_waf/
│   │   └── with_access_logs/
│   ├── ecs_cluster/       # ECS cluster module fixtures
│   │   ├── fargate/
│   │   ├── fargate_spot/
│   │   └── with_alb/
│   ├── ecs_service/       # ECS service module fixtures
│   │   ├── basic/
│   │   ├── with_alb/
│   │   └── with_autoscaling/
│   ├── elasticache/       # ElastiCache module fixtures
│   │   ├── redis/
│   │   ├── memcached/
│   │   └── redis_replication/
│   ├── nlb/               # NLB module fixtures
│   │   ├── basic/
│   │   └── with_cross_zone/
│   ├── security_groups/   # Security groups module fixtures
│   │   ├── basic/
│   │   └── with_egress/
│   └── vpc/               # VPC module fixtures
│       ├── basic/
│       ├── with_nat/
│       ├── full/
│       └── with_flow_logs_s3/
├── alb_test.go            # ALB integration tests
├── ecs_cluster_test.go    # ECS cluster integration tests
├── ecs_service_test.go    # ECS service integration tests
├── elasticache_test.go    # ElastiCache integration tests
├── nlb_test.go            # NLB integration tests
├── security_groups_test.go # Security groups integration tests
└── vpc_test.go            # VPC integration tests
```

## Prerequisites

- **Go 1.23+**: Required for running tests
- **OpenTofu/Terraform 1.0+**: Required for provisioning infrastructure
- **AWS CLI configured**: With credentials that have permissions to create/destroy resources

## Environment Variables

The following environment variables must be set:

| Variable | Required | Description |
|----------|----------|-------------|
| `AWS_ACCESS_KEY_ID` | Yes | AWS access key for authentication |
| `AWS_SECRET_ACCESS_KEY` | Yes | AWS secret key for authentication |
| `AWS_REGION` | No | AWS region (defaults to `us-east-1`) |

## Running Tests

### Run All Tests

```bash
cd test
go test -v -timeout 60m ./...
```

### Run a Specific Test

```bash
cd test
go test -v -timeout 30m -run TestVpcBasic ./...
```

### Run Tests for a Specific Module

```bash
# VPC tests
go test -v -timeout 60m -run TestVpc ./...

# ALB tests
go test -v -timeout 60m -run TestAlb ./...

# ECS tests
go test -v -timeout 60m -run TestEcs ./...

# ElastiCache tests
go test -v -timeout 60m -run TestElastiCache ./...
```

### Run Tests with Parallel Execution

Tests use `t.Parallel()` and can run concurrently:

```bash
go test -v -timeout 60m -parallel 4 ./...
```

## Test Fixtures

Fixtures are minimal Terraform configurations that instantiate modules for testing. Each fixture:

1. Creates any prerequisite resources (e.g., VPC for ALB tests)
2. Instantiates the module being tested
3. Outputs values needed for assertions
4. Uses standard terratest tags (`Environment=terratest`, `ManagedBy=terratest`)

### Fixture Conventions

- Each fixture is a self-contained Terraform configuration in `fixtures/<module>/<variant>/`
- Fixtures accept at minimum `name` and `region` variables
- Fixtures include standard terratest tags for resource identification
- Outputs should provide all values needed for test assertions

### Creating a New Fixture

1. Create a new directory under `fixtures/<module>/<variant>/`
2. Create `main.tf` with:
   - Required providers block
   - Provider configuration
   - Variables for `name`, `region`, and `tags`
   - Module instantiation with test configuration
   - Outputs for test assertions

Example structure:
```hcl
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "name" {
  type        = string
  description = "Name prefix for all resources."
}

variable "region" {
  type        = string
  description = "AWS region to deploy resources."
  default     = "us-east-1"
}

variable "tags" {
  type        = map(string)
  description = "Additional tags for all resources."
  default     = {}
}

module "example" {
  source = "../../../../path/to/module"

  name = var.name
  # ... module configuration

  tags = merge(
    {
      Environment = "terratest"
      ManagedBy   = "terratest"
    },
    var.tags
  )
}

output "example_id" {
  value = module.example.id
}
```

## Helper Functions

### random.go

- `UniqueResourceName(prefix string) string`: Generates `terratest-{prefix}-{uniqueId}`
- `UniqueId() string`: Returns a lowercase unique identifier

### aws.go

AWS SDK helper functions for validating resources:

**VPC helpers:**
- `GetAwsRegion() string`: Returns AWS region from env or default
- `VpcExists(t, vpcId, region) bool`: Check if VPC exists
- `SubnetsExist(t, subnetIds, region) bool`: Check if subnets exist
- `GetVpcCidr(t, vpcId, region) string`: Get VPC CIDR block
- `GetVpcIpv6CidrBlock(t, vpcId, region) string`: Get VPC IPv6 CIDR
- `VpcHasIpv6CidrBlock(t, vpcId, region) bool`: Check IPv6 support

**NAT Gateway helpers:**
- `NatGatewayExists(t, natGatewayId, region) bool`: Check if NAT GW exists
- `GetNatGatewayState(t, natGatewayId, region) NatGatewayState`: Get state
- `RouteTableHasNatGatewayRoute(t, routeTableId, region) bool`: Check routes

**Load Balancer helpers:**
- `LoadBalancerExists(t, albArn, region) bool`: Check if LB exists
- `GetLoadBalancerState(t, albArn, region) LoadBalancerStateEnum`: Get state
- `GetLoadBalancerCrossZoneEnabled(t, lbArn, region) bool`: Check cross-zone
- `GetLoadBalancerAccessLogsEnabled(t, lbArn, region) bool`: Check access logs

**Security Group helpers:**
- `SecurityGroupExists(t, sgId, region) bool`: Check if SG exists
- `SecurityGroupHasIngressRule(t, sgId, port, region) bool`: Check ingress
- `SecurityGroupHasEgressRule(t, sgId, port, region) bool`: Check egress

**ECS helpers:**
- `EcsClusterExists(t, clusterArn, region) bool`: Check if cluster exists
- `GetEcsClusterStatus(t, clusterArn, region) string`: Get cluster status
- `EcsClusterHasCapacityProvider(t, clusterArn, provider, region) bool`: Check provider
- `EcsServiceExists(t, clusterArn, serviceName, region) bool`: Check service
- `GetEcsServiceRunningCount(t, clusterArn, serviceName, region) int32`: Get running tasks

**ElastiCache helpers:**
- `ElastiCacheReplicationGroupExists(t, rgId, region) bool`: Check Redis exists
- `GetElastiCacheReplicationGroupStatus(t, rgId, region) string`: Get status
- `ElastiCacheClusterExists(t, clusterId, region) bool`: Check Memcached exists

**S3 helpers:**
- `S3BucketExists(t, bucketName, region) bool`: Check if bucket exists
- `S3BucketHasSSEEncryption(t, bucketName, region) bool`: Check encryption
- `S3BucketHasPublicAccessBlocked(t, bucketName, region) bool`: Check public access

**WAF helpers:**
- `WafWebAclExists(t, webAclArn, region) bool`: Check if WebACL exists
- `WafWebAclHasManagedRuleGroup(t, webAclArn, ruleName, region) bool`: Check rules

### tags.go

- `HasTag(tags, key, value) bool`: Check for specific tag
- `ValidateRequiredTags(t, tags, required) bool`: Validate required tags exist
- `ValidateTerratestTags(t, tags)`: Validate standard terratest tags

## Writing New Tests

### Test Structure

```go
func TestModuleFeature(t *testing.T) {
    t.Parallel()

    // Get AWS region
    awsRegion := helpers.GetAwsRegion()

    // Generate unique name
    uniqueName := helpers.UniqueResourceName("feature")

    // Configure Terraform
    terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
        TerraformDir: "./fixtures/module/feature",
        Vars: map[string]interface{}{
            "name":   uniqueName,
            "region": awsRegion,
        },
    })

    // Always destroy resources
    defer terraform.Destroy(t, terraformOptions)

    // Apply configuration
    terraform.InitAndApply(t, terraformOptions)

    // Get outputs
    resourceId := terraform.Output(t, terraformOptions, "resource_id")

    // Assert Terraform outputs
    require.NotEmpty(t, resourceId, "resource_id should not be empty")

    // Validate with AWS SDK
    exists := helpers.ResourceExists(t, resourceId, awsRegion)
    assert.True(t, exists, "Resource should exist in AWS")
}
```

### Best Practices

1. **Always use `t.Parallel()`**: Allows tests to run concurrently
2. **Always use `defer terraform.Destroy()`**: Ensures cleanup even on failures
3. **Use unique names**: Prevents conflicts between parallel tests
4. **Validate with AWS SDK**: Don't just trust Terraform outputs
5. **Use meaningful assertions**: Provide context in failure messages
6. **Keep fixtures minimal**: Only configure what's needed for the test

## CI/CD Integration

Tests run automatically via GitHub Actions:

- **Native tests (`tofu test`)**: Run on all PRs and pushes to main
- **Integration tests (Terratest)**: Run on pushes to main or PRs with `run-terratest` label

See `.github/workflows/terratest.yml` for the workflow configuration.

### Running Integration Tests on PRs

Add the `run-terratest` label to a PR to trigger integration tests before merging.

## Cost Considerations

These tests provision real AWS resources that incur costs:

- **VPC**: Minimal cost (NAT Gateways cost ~$0.045/hour each)
- **ALB/NLB**: ~$0.0225/hour per load balancer
- **ECS**: Tasks run on Fargate (~$0.04/hour for minimal config)
- **ElastiCache**: cache.t4g.micro instances (~$0.016/hour)

**Tips to minimize costs:**
- Tests automatically destroy resources after completion
- Run specific tests instead of full suite during development
- Use smaller instance types in fixtures
- Monitor for orphaned resources if tests fail unexpectedly

## Troubleshooting

### Test Timeout

Increase the timeout if tests are failing due to time limits:

```bash
go test -v -timeout 90m ./...
```

### Resource Cleanup Failures

If `terraform destroy` fails, you may need to manually clean up:

1. Find resources with `terratest` tags in the AWS console
2. Delete resources in reverse dependency order
3. Check CloudWatch Logs, S3 buckets, and IAM roles

### AWS Permission Errors

Ensure your AWS credentials have permissions for:
- VPC, Subnet, Internet Gateway, NAT Gateway, Route Table
- Security Groups
- ALB, NLB, Target Groups, Listeners
- ECS Clusters, Services, Task Definitions
- ElastiCache Clusters, Replication Groups
- S3 Buckets
- CloudWatch Log Groups
- WAF WebACLs
- IAM Roles (for ECS task execution)

### Debugging Failed Tests

Run with verbose output:
```bash
go test -v -timeout 60m -run TestName ./... 2>&1 | tee test-output.txt
```

Check Terraform state:
```bash
cd test/fixtures/module/variant
tofu state list
tofu state show <resource>
```
