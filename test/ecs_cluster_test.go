// Package test contains Terratest integration tests for the Terraform modules.
package test

import (
	"testing"

	"github.com/flightcontrolhq/modules/test/helpers"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestEcsClusterFargate provisions the basic ECS cluster fixture with Fargate capacity provider.
// It verifies:
// - cluster_arn is not empty
// - cluster_name is not empty
// - ECS cluster is in 'ACTIVE' state using AWS SDK
// - FARGATE capacity provider is attached to the cluster
func TestEcsClusterFargate(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("ecs")

	// Configure Terraform options
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/ecs_cluster/fargate",
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
	clusterArn := terraform.Output(t, terraformOptions, "cluster_arn")
	clusterName := terraform.Output(t, terraformOptions, "cluster_name")
	capacityProviders := terraform.OutputList(t, terraformOptions, "capacity_providers")

	// Assert cluster_arn is not empty
	require.NotEmpty(t, clusterArn, "cluster_arn should not be empty")

	// Assert cluster_name is not empty
	require.NotEmpty(t, clusterName, "cluster_name should not be empty")

	// Assert capacity_providers list contains FARGATE
	assert.Contains(t, capacityProviders, "FARGATE", "capacity_providers should contain FARGATE")

	// Use AWS SDK to verify ECS cluster exists
	clusterExists := helpers.EcsClusterExists(t, clusterArn, awsRegion)
	assert.True(t, clusterExists, "ECS cluster should exist in AWS")

	// Use AWS SDK to verify ECS cluster is in 'ACTIVE' state
	clusterStatus := helpers.GetEcsClusterStatus(t, clusterArn, awsRegion)
	assert.Equal(t, "ACTIVE", clusterStatus, "ECS cluster should be in 'ACTIVE' state")

	// Use AWS SDK to verify FARGATE capacity provider is attached
	hasFargate := helpers.EcsClusterHasCapacityProvider(t, clusterArn, "FARGATE", awsRegion)
	assert.True(t, hasFargate, "ECS cluster should have FARGATE capacity provider attached")
}
