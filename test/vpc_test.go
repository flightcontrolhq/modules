// Package test contains Terratest integration tests for the Terraform modules.
package test

import (
	"testing"

	"github.com/flightcontrolhq/modules/test/helpers"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestVpcBasic provisions the basic VPC fixture and validates the outputs.
// It verifies:
// - vpc_id is not empty
// - public_subnet_ids has 3 elements
// - private_subnet_ids has 3 elements
// - VPC exists in AWS with the correct CIDR block
func TestVpcBasic(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("vpc")

	// Configure Terraform options
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/vpc/basic",
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
	vpcId := terraform.Output(t, terraformOptions, "vpc_id")
	publicSubnetIds := terraform.OutputList(t, terraformOptions, "public_subnet_ids")
	privateSubnetIds := terraform.OutputList(t, terraformOptions, "private_subnet_ids")
	internetGatewayId := terraform.Output(t, terraformOptions, "internet_gateway_id")

	// Assert vpc_id is not empty
	require.NotEmpty(t, vpcId, "vpc_id should not be empty")

	// Assert public_subnet_ids has 3 elements
	assert.Len(t, publicSubnetIds, 3, "public_subnet_ids should have 3 elements")

	// Assert private_subnet_ids has 3 elements
	assert.Len(t, privateSubnetIds, 3, "private_subnet_ids should have 3 elements")

	// Assert internet_gateway_id is not empty
	assert.NotEmpty(t, internetGatewayId, "internet_gateway_id should not be empty")

	// Use AWS SDK to verify VPC exists
	vpcExists := helpers.VpcExists(t, vpcId, awsRegion)
	assert.True(t, vpcExists, "VPC should exist in AWS")

	// Use AWS SDK to verify VPC has correct CIDR
	vpcCidr := helpers.GetVpcCidr(t, vpcId, awsRegion)
	assert.Equal(t, "10.0.0.0/16", vpcCidr, "VPC should have CIDR 10.0.0.0/16")

	// Use AWS SDK to verify all subnets exist
	allSubnetIds := append(publicSubnetIds, privateSubnetIds...)
	subnetsExist := helpers.SubnetsExist(t, allSubnetIds, awsRegion)
	assert.True(t, subnetsExist, "All subnets should exist in AWS")
}
