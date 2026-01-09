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

// TestEcsClusterWithAlb provisions the ECS cluster fixture with ALB integration.
// It verifies:
// - cluster_arn is not empty
// - cluster_name is not empty
// - alb_arn is not empty
// - alb_dns_name is not empty
// - alb_target_group_arn is not empty
// - ECS cluster and ALB are created using AWS SDK
// - Target group is properly configured for ECS (IP target type)
func TestEcsClusterWithAlb(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("ecsalb")

	// Configure Terraform options
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/ecs_cluster/with_alb",
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
	albArn := terraform.Output(t, terraformOptions, "alb_arn")
	albDnsName := terraform.Output(t, terraformOptions, "alb_dns_name")
	targetGroupArn := terraform.Output(t, terraformOptions, "alb_target_group_arn")
	albSecurityGroupId := terraform.Output(t, terraformOptions, "alb_security_group_id")

	// Assert cluster outputs are not empty
	require.NotEmpty(t, clusterArn, "cluster_arn should not be empty")
	require.NotEmpty(t, clusterName, "cluster_name should not be empty")

	// Assert ALB outputs are not empty
	require.NotEmpty(t, albArn, "alb_arn should not be empty")
	require.NotEmpty(t, albDnsName, "alb_dns_name should not be empty")
	require.NotEmpty(t, targetGroupArn, "alb_target_group_arn should not be empty")
	require.NotEmpty(t, albSecurityGroupId, "alb_security_group_id should not be empty")

	// Use AWS SDK to verify ECS cluster exists
	clusterExists := helpers.EcsClusterExists(t, clusterArn, awsRegion)
	assert.True(t, clusterExists, "ECS cluster should exist in AWS")

	// Use AWS SDK to verify ECS cluster is in 'ACTIVE' state
	clusterStatus := helpers.GetEcsClusterStatus(t, clusterArn, awsRegion)
	assert.Equal(t, "ACTIVE", clusterStatus, "ECS cluster should be in 'ACTIVE' state")

	// Use AWS SDK to verify ALB exists
	albExists := helpers.LoadBalancerExists(t, albArn, awsRegion)
	assert.True(t, albExists, "ALB should exist in AWS")

	// Use AWS SDK to verify ALB is in 'active' state
	albState := helpers.GetLoadBalancerState(t, albArn, awsRegion)
	assert.Equal(t, "active", string(albState), "ALB should be in 'active' state")

	// Use AWS SDK to verify target group exists
	tgExists := helpers.TargetGroupExists(t, targetGroupArn, awsRegion)
	assert.True(t, tgExists, "Target group should exist in AWS")

	// Use AWS SDK to verify target group is configured for ECS (IP target type)
	targetType := helpers.GetTargetGroupTargetType(t, targetGroupArn, awsRegion)
	assert.Equal(t, "ip", string(targetType), "Target group should have 'ip' target type for ECS Fargate")

	// Use AWS SDK to verify target group protocol is HTTP
	tgProtocol := helpers.GetTargetGroupProtocol(t, targetGroupArn, awsRegion)
	assert.Equal(t, "HTTP", string(tgProtocol), "Target group should have HTTP protocol")

	// Use AWS SDK to verify target group port is 80
	tgPort := helpers.GetTargetGroupPort(t, targetGroupArn, awsRegion)
	assert.Equal(t, int32(80), tgPort, "Target group should be on port 80")
}

// TestEcsClusterFargateSpot provisions the ECS cluster fixture with both Fargate and Fargate Spot capacity providers.
// It verifies:
// - cluster_arn is not empty
// - cluster_name is not empty
// - ECS cluster is in 'ACTIVE' state using AWS SDK
// - Both FARGATE and FARGATE_SPOT capacity providers are attached to the cluster
func TestEcsClusterFargateSpot(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("ecsspot")

	// Configure Terraform options
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/ecs_cluster/fargate_spot",
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
	fargateSpotName := terraform.Output(t, terraformOptions, "fargate_spot_capacity_provider_name")

	// Assert cluster_arn is not empty
	require.NotEmpty(t, clusterArn, "cluster_arn should not be empty")

	// Assert cluster_name is not empty
	require.NotEmpty(t, clusterName, "cluster_name should not be empty")

	// Assert capacity_providers list contains both FARGATE and FARGATE_SPOT
	assert.Contains(t, capacityProviders, "FARGATE", "capacity_providers should contain FARGATE")
	assert.Contains(t, capacityProviders, "FARGATE_SPOT", "capacity_providers should contain FARGATE_SPOT")

	// Assert fargate_spot_capacity_provider_name output is correct
	assert.Equal(t, "FARGATE_SPOT", fargateSpotName, "fargate_spot_capacity_provider_name should be FARGATE_SPOT")

	// Use AWS SDK to verify ECS cluster exists
	clusterExists := helpers.EcsClusterExists(t, clusterArn, awsRegion)
	assert.True(t, clusterExists, "ECS cluster should exist in AWS")

	// Use AWS SDK to verify ECS cluster is in 'ACTIVE' state
	clusterStatus := helpers.GetEcsClusterStatus(t, clusterArn, awsRegion)
	assert.Equal(t, "ACTIVE", clusterStatus, "ECS cluster should be in 'ACTIVE' state")

	// Use AWS SDK to verify FARGATE capacity provider is attached
	hasFargate := helpers.EcsClusterHasCapacityProvider(t, clusterArn, "FARGATE", awsRegion)
	assert.True(t, hasFargate, "ECS cluster should have FARGATE capacity provider attached")

	// Use AWS SDK to verify FARGATE_SPOT capacity provider is attached
	hasFargateSpot := helpers.EcsClusterHasCapacityProvider(t, clusterArn, "FARGATE_SPOT", awsRegion)
	assert.True(t, hasFargateSpot, "ECS cluster should have FARGATE_SPOT capacity provider attached")
}
