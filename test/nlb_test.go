// Package test contains Terratest integration tests for the Terraform modules.
package test

import (
	"testing"

	"github.com/flightcontrolhq/modules/test/helpers"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestNlbBasic provisions the basic NLB fixture and validates the outputs.
// It verifies:
// - nlb_dns_name is not empty
// - NLB is in 'active' state using AWS SDK
// - TCP listener exists on port 80
func TestNlbBasic(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("nlb")

	// Configure Terraform options
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/nlb/basic",
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
	nlbArn := terraform.Output(t, terraformOptions, "nlb_arn")
	nlbDnsName := terraform.Output(t, terraformOptions, "nlb_dns_name")
	targetGroupArn := terraform.Output(t, terraformOptions, "target_group_arn")
	listenerArn := terraform.Output(t, terraformOptions, "listener_arn")

	// Assert nlb_dns_name is not empty
	require.NotEmpty(t, nlbDnsName, "nlb_dns_name should not be empty")

	// Assert nlb_arn is not empty
	require.NotEmpty(t, nlbArn, "nlb_arn should not be empty")

	// Assert target_group_arn is not empty
	assert.NotEmpty(t, targetGroupArn, "target_group_arn should not be empty")

	// Assert listener_arn is not empty
	require.NotEmpty(t, listenerArn, "listener_arn should not be empty")

	// Use AWS SDK to verify NLB exists
	nlbExists := helpers.LoadBalancerExists(t, nlbArn, awsRegion)
	assert.True(t, nlbExists, "NLB should exist in AWS")

	// Use AWS SDK to verify NLB is in 'active' state
	nlbState := helpers.GetLoadBalancerState(t, nlbArn, awsRegion)
	assert.Equal(t, "active", string(nlbState), "NLB should be in 'active' state")

	// Use AWS SDK to verify TCP listener exists
	tcpListenerExists := helpers.ListenerExists(t, listenerArn, awsRegion)
	assert.True(t, tcpListenerExists, "TCP listener should exist in AWS")

	// Use AWS SDK to verify listener is TCP on port 80
	listenerProtocol := helpers.GetListenerProtocol(t, listenerArn, awsRegion)
	assert.Equal(t, "TCP", string(listenerProtocol), "Listener should have TCP protocol")

	listenerPort := helpers.GetListenerPort(t, listenerArn, awsRegion)
	assert.Equal(t, int32(80), listenerPort, "TCP listener should be on port 80")
}

// TestNlbCrossZone provisions an NLB with cross-zone load balancing enabled and validates the configuration.
// It verifies:
// - NLB is created and in 'active' state
// - Cross-zone load balancing attribute is enabled
func TestNlbCrossZone(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("nlb-xz")

	// Configure Terraform options
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/nlb/with_cross_zone",
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
	nlbArn := terraform.Output(t, terraformOptions, "nlb_arn")
	nlbDnsName := terraform.Output(t, terraformOptions, "nlb_dns_name")

	// Assert nlb_arn is not empty
	require.NotEmpty(t, nlbArn, "nlb_arn should not be empty")

	// Assert nlb_dns_name is not empty
	require.NotEmpty(t, nlbDnsName, "nlb_dns_name should not be empty")

	// Use AWS SDK to verify NLB exists
	nlbExists := helpers.LoadBalancerExists(t, nlbArn, awsRegion)
	assert.True(t, nlbExists, "NLB should exist in AWS")

	// Use AWS SDK to verify NLB is in 'active' state
	nlbState := helpers.GetLoadBalancerState(t, nlbArn, awsRegion)
	assert.Equal(t, "active", string(nlbState), "NLB should be in 'active' state")

	// Use AWS SDK to verify cross-zone load balancing is enabled
	crossZoneEnabled := helpers.GetLoadBalancerCrossZoneEnabled(t, nlbArn, awsRegion)
	assert.True(t, crossZoneEnabled, "Cross-zone load balancing should be enabled")
}
