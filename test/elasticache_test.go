// Package test contains Terratest integration tests for the Terraform modules.
package test

import (
	"testing"

	"github.com/flightcontrolhq/modules/test/helpers"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestElastiCacheRedis provisions the basic Redis ElastiCache fixture.
// It verifies:
// - primary_endpoint is not empty
// - replication_group_id is not empty
// - port is the default Redis port (6379)
// - security_group_id is not empty
// - ElastiCache cluster is 'available' using AWS SDK
// - Security group allows access on Redis port 6379
func TestElastiCacheRedis(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("redis")

	// Configure Terraform options
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/elasticache/redis",
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
	replicationGroupId := terraform.Output(t, terraformOptions, "replication_group_id")
	primaryEndpoint := terraform.Output(t, terraformOptions, "primary_endpoint")
	port := terraform.Output(t, terraformOptions, "port")
	securityGroupId := terraform.Output(t, terraformOptions, "security_group_id")

	// Assert replication_group_id is not empty
	require.NotEmpty(t, replicationGroupId, "replication_group_id should not be empty")

	// Assert primary_endpoint is not empty
	require.NotEmpty(t, primaryEndpoint, "primary_endpoint should not be empty")

	// Assert port is the default Redis port (6379)
	assert.Equal(t, "6379", port, "port should be 6379 for Redis")

	// Assert security_group_id is not empty
	require.NotEmpty(t, securityGroupId, "security_group_id should not be empty")

	// Use AWS SDK to verify ElastiCache replication group exists
	replicationGroupExists := helpers.ElastiCacheReplicationGroupExists(t, replicationGroupId, awsRegion)
	assert.True(t, replicationGroupExists, "ElastiCache replication group should exist in AWS")

	// Use AWS SDK to verify ElastiCache replication group is 'available'
	replicationGroupStatus := helpers.GetElastiCacheReplicationGroupStatus(t, replicationGroupId, awsRegion)
	assert.Equal(t, "available", replicationGroupStatus, "ElastiCache replication group should be in 'available' state")

	// Use AWS SDK to verify security group exists
	securityGroupExists := helpers.SecurityGroupExists(t, securityGroupId, awsRegion)
	assert.True(t, securityGroupExists, "Security group should exist in AWS")

	// Use AWS SDK to verify security group allows access on Redis port 6379
	hasRedisRule := helpers.SecurityGroupHasIngressRule(t, securityGroupId, 6379, awsRegion)
	assert.True(t, hasRedisRule, "Security group should allow access on Redis port 6379")
}
