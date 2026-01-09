// Package test contains Terratest integration tests for the Terraform modules.
package test

import (
	"testing"

	"github.com/flightcontrolhq/modules/test/helpers"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestSecurityGroupBasic provisions the basic security group fixture and validates the outputs.
// It verifies:
// - security_group_id is not empty
// - security group exists in AWS using AWS SDK
// - ingress rules match configuration (ports 22 for SSH, 80 for HTTP)
func TestSecurityGroupBasic(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("sg")

	// Configure Terraform options
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/security_groups/basic",
		Vars: map[string]interface{}{
			"name":   uniqueName,
			"region": awsRegion,
		},
	})

	// Ensure cleanup happens even if the test fails
	defer terraform.Destroy(t, terraformOptions)

	// Initialize and apply the Terraform configuration
	terraform.InitAndApply(t, terraformOptions)

	// Get outputs
	securityGroupId := terraform.Output(t, terraformOptions, "security_group_id")
	securityGroupArn := terraform.Output(t, terraformOptions, "security_group_arn")
	securityGroupName := terraform.Output(t, terraformOptions, "security_group_name")

	// Assert security_group_id is not empty
	require.NotEmpty(t, securityGroupId, "security_group_id should not be empty")

	// Assert security_group_arn is not empty
	assert.NotEmpty(t, securityGroupArn, "security_group_arn should not be empty")

	// Assert security_group_name is not empty
	assert.NotEmpty(t, securityGroupName, "security_group_name should not be empty")

	// Use AWS SDK to verify security group exists
	sgExists := helpers.SecurityGroupExists(t, securityGroupId, awsRegion)
	assert.True(t, sgExists, "Security group should exist in AWS")

	// Use AWS SDK to verify security group has SSH inbound rule (port 22)
	hasSshRule := helpers.SecurityGroupHasIngressRule(t, securityGroupId, 22, awsRegion)
	assert.True(t, hasSshRule, "Security group should have inbound rule for SSH (port 22)")

	// Use AWS SDK to verify security group has HTTP inbound rule (port 80)
	hasHttpRule := helpers.SecurityGroupHasIngressRule(t, securityGroupId, 80, awsRegion)
	assert.True(t, hasHttpRule, "Security group should have inbound rule for HTTP (port 80)")
}

// TestSecurityGroupEgress provisions a security group with custom egress rules (not allow-all)
// and verifies:
// - security_group_id is not empty
// - security group exists in AWS using AWS SDK
// - egress rules are applied correctly (HTTPS port 443 to 0.0.0.0/0, PostgreSQL port 5432 to VPC CIDR)
func TestSecurityGroupEgress(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("sgegress")

	// Configure Terraform options
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/security_groups/with_egress",
		Vars: map[string]interface{}{
			"name":   uniqueName,
			"region": awsRegion,
		},
	})

	// Ensure cleanup happens even if the test fails
	defer terraform.Destroy(t, terraformOptions)

	// Initialize and apply the Terraform configuration
	terraform.InitAndApply(t, terraformOptions)

	// Get outputs
	securityGroupId := terraform.Output(t, terraformOptions, "security_group_id")
	securityGroupArn := terraform.Output(t, terraformOptions, "security_group_arn")
	securityGroupName := terraform.Output(t, terraformOptions, "security_group_name")

	// Assert security_group_id is not empty
	require.NotEmpty(t, securityGroupId, "security_group_id should not be empty")

	// Assert security_group_arn is not empty
	assert.NotEmpty(t, securityGroupArn, "security_group_arn should not be empty")

	// Assert security_group_name is not empty
	assert.NotEmpty(t, securityGroupName, "security_group_name should not be empty")

	// Use AWS SDK to verify security group exists
	sgExists := helpers.SecurityGroupExists(t, securityGroupId, awsRegion)
	assert.True(t, sgExists, "Security group should exist in AWS")

	// Use AWS SDK to verify security group has HTTPS egress rule (port 443) to 0.0.0.0/0
	hasHttpsEgress := helpers.SecurityGroupHasEgressRuleWithCidr(t, securityGroupId, 443, "0.0.0.0/0", awsRegion)
	assert.True(t, hasHttpsEgress, "Security group should have egress rule for HTTPS (port 443) to 0.0.0.0/0")

	// Use AWS SDK to verify security group has PostgreSQL egress rule (port 5432) to VPC CIDR
	hasPgEgress := helpers.SecurityGroupHasEgressRuleWithCidr(t, securityGroupId, 5432, "10.0.0.0/16", awsRegion)
	assert.True(t, hasPgEgress, "Security group should have egress rule for PostgreSQL (port 5432) to VPC CIDR 10.0.0.0/16")

	// Use AWS SDK to verify security group does NOT have allow-all egress rule
	// If allow_all_egress were true, there would be an egress rule on port 0 (all ports) or protocol -1
	hasAllEgress := helpers.SecurityGroupHasEgressRule(t, securityGroupId, 0, awsRegion)
	assert.False(t, hasAllEgress, "Security group should NOT have allow-all egress rule (port 0)")
}
