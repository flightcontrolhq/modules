// Package test contains Terratest integration tests for the Terraform modules.
package test

import (
	"testing"

	"github.com/flightcontrolhq/modules/test/helpers"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestAlbBasic provisions the basic ALB fixture and validates the outputs.
// It verifies:
// - alb_dns_name is not empty
// - ALB is in 'active' state using AWS SDK
// - Security group exists with correct inbound rules (port 80 for HTTP)
func TestAlbBasic(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("alb")

	// Configure Terraform options
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/alb/basic",
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
	albArn := terraform.Output(t, terraformOptions, "alb_arn")
	albDnsName := terraform.Output(t, terraformOptions, "alb_dns_name")
	securityGroupId := terraform.Output(t, terraformOptions, "security_group_id")
	httpListenerArn := terraform.Output(t, terraformOptions, "http_listener_arn")

	// Assert alb_dns_name is not empty
	require.NotEmpty(t, albDnsName, "alb_dns_name should not be empty")

	// Assert alb_arn is not empty
	require.NotEmpty(t, albArn, "alb_arn should not be empty")

	// Assert http_listener_arn is not empty
	assert.NotEmpty(t, httpListenerArn, "http_listener_arn should not be empty")

	// Assert security_group_id is not empty
	require.NotEmpty(t, securityGroupId, "security_group_id should not be empty")

	// Use AWS SDK to verify ALB exists
	albExists := helpers.LoadBalancerExists(t, albArn, awsRegion)
	assert.True(t, albExists, "ALB should exist in AWS")

	// Use AWS SDK to verify ALB is in 'active' state
	albState := helpers.GetLoadBalancerState(t, albArn, awsRegion)
	assert.Equal(t, "active", string(albState), "ALB should be in 'active' state")

	// Use AWS SDK to verify security group exists
	sgExists := helpers.SecurityGroupExists(t, securityGroupId, awsRegion)
	assert.True(t, sgExists, "Security group should exist in AWS")

	// Use AWS SDK to verify security group has HTTP inbound rule (port 80)
	hasHttpRule := helpers.SecurityGroupHasIngressRule(t, securityGroupId, 80, awsRegion)
	assert.True(t, hasHttpRule, "Security group should have inbound rule for HTTP (port 80)")
}
