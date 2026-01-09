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

// TestElastiCacheMemcached provisions the Memcached ElastiCache fixture.
// It verifies:
// - configuration_endpoint is not empty
// - cluster_id is not empty
// - port is the default Memcached port (11211)
// - security_group_id is not empty
// - ElastiCache cluster is 'available' using AWS SDK
// - ElastiCache cluster engine is 'memcached' using AWS SDK
// - Security group allows access on Memcached port 11211
func TestElastiCacheMemcached(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("memc")

	// Configure Terraform options
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/elasticache/memcached",
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
	clusterId := terraform.Output(t, terraformOptions, "cluster_id")
	configurationEndpoint := terraform.Output(t, terraformOptions, "configuration_endpoint")
	port := terraform.Output(t, terraformOptions, "port")
	securityGroupId := terraform.Output(t, terraformOptions, "security_group_id")

	// Assert cluster_id is not empty
	require.NotEmpty(t, clusterId, "cluster_id should not be empty")

	// Assert configuration_endpoint is not empty
	require.NotEmpty(t, configurationEndpoint, "configuration_endpoint should not be empty")

	// Assert port is the default Memcached port (11211)
	assert.Equal(t, "11211", port, "port should be 11211 for Memcached")

	// Assert security_group_id is not empty
	require.NotEmpty(t, securityGroupId, "security_group_id should not be empty")

	// Use AWS SDK to verify ElastiCache cluster exists
	clusterExists := helpers.ElastiCacheClusterExists(t, clusterId, awsRegion)
	assert.True(t, clusterExists, "ElastiCache cluster should exist in AWS")

	// Use AWS SDK to verify ElastiCache cluster is 'available'
	clusterStatus := helpers.GetElastiCacheClusterStatus(t, clusterId, awsRegion)
	assert.Equal(t, "available", clusterStatus, "ElastiCache cluster should be in 'available' state")

	// Use AWS SDK to verify ElastiCache cluster engine is 'memcached'
	clusterEngine := helpers.GetElastiCacheClusterEngine(t, clusterId, awsRegion)
	assert.Equal(t, "memcached", clusterEngine, "ElastiCache cluster engine should be 'memcached'")

	// Use AWS SDK to verify security group exists
	securityGroupExists := helpers.SecurityGroupExists(t, securityGroupId, awsRegion)
	assert.True(t, securityGroupExists, "Security group should exist in AWS")

	// Use AWS SDK to verify security group allows access on Memcached port 11211
	hasMemcachedRule := helpers.SecurityGroupHasIngressRule(t, securityGroupId, 11211, awsRegion)
	assert.True(t, hasMemcachedRule, "Security group should allow access on Memcached port 11211")
}

// TestElastiCacheReplication provisions a Redis ElastiCache cluster with replication.
// It verifies:
// - replication_group_id is not empty
// - primary_endpoint is not empty
// - reader_endpoint is not empty
// - port is the default Redis port (6379)
// - Replication group is created with 2 nodes (1 primary + 1 replica)
// - Both primary and replica nodes are 'available' using AWS SDK
func TestElastiCacheReplication(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("repl")

	// Configure Terraform options
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/elasticache/redis_replication",
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
	readerEndpoint := terraform.Output(t, terraformOptions, "reader_endpoint")
	port := terraform.Output(t, terraformOptions, "port")
	securityGroupId := terraform.Output(t, terraformOptions, "security_group_id")

	// Assert replication_group_id is not empty
	require.NotEmpty(t, replicationGroupId, "replication_group_id should not be empty")

	// Assert primary_endpoint is not empty
	require.NotEmpty(t, primaryEndpoint, "primary_endpoint should not be empty")

	// Assert reader_endpoint is not empty (only available with replicas)
	require.NotEmpty(t, readerEndpoint, "reader_endpoint should not be empty")

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

	// Use AWS SDK to verify replication group has 2 member clusters (1 primary + 1 replica)
	memberClusterCount := helpers.GetElastiCacheReplicationGroupMemberClusterCount(t, replicationGroupId, awsRegion)
	assert.Equal(t, 2, memberClusterCount, "Replication group should have 2 member clusters (1 primary + 1 replica)")

	// Use AWS SDK to verify total node count is 2
	nodeCount := helpers.GetElastiCacheReplicationGroupNodeCount(t, replicationGroupId, awsRegion)
	assert.Equal(t, 2, nodeCount, "Replication group should have 2 total nodes")

	// Use AWS SDK to verify there is 1 primary node
	primaryCount := helpers.GetElastiCacheReplicationGroupPrimaryCount(t, replicationGroupId, awsRegion)
	assert.Equal(t, 1, primaryCount, "Replication group should have 1 primary node")

	// Use AWS SDK to verify there is 1 replica node
	replicaCount := helpers.GetElastiCacheReplicationGroupReplicaCount(t, replicationGroupId, awsRegion)
	assert.Equal(t, 1, replicaCount, "Replication group should have 1 replica node")

	// Use AWS SDK to verify all member clusters are 'available'
	allMembersAvailable := helpers.AllElastiCacheReplicationGroupMembersAvailable(t, replicationGroupId, awsRegion)
	assert.True(t, allMembersAvailable, "All member clusters should be in 'available' state")

	// Use AWS SDK to verify security group exists
	securityGroupExists := helpers.SecurityGroupExists(t, securityGroupId, awsRegion)
	assert.True(t, securityGroupExists, "Security group should exist in AWS")

	// Use AWS SDK to verify security group allows access on Redis port 6379
	hasRedisRule := helpers.SecurityGroupHasIngressRule(t, securityGroupId, 6379, awsRegion)
	assert.True(t, hasRedisRule, "Security group should allow access on Redis port 6379")
}
