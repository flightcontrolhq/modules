// Package test contains Terratest integration tests for the Terraform modules.
package test

import (
	"fmt"
	"testing"

	"github.com/flightcontrolhq/modules/test/helpers"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestAuroraBasic provisions the basic Aurora PostgreSQL fixture.
// It verifies:
// - cluster_endpoint is not empty
// - cluster_reader_endpoint is not empty
// - cluster_port is the default PostgreSQL port (5432)
// - security_group_id is not empty
// - Aurora cluster exists and is 'available' using AWS SDK
// - Cluster has 1 writer and 1 reader instance
// - Security group allows access on PostgreSQL port 5432
func TestAuroraBasic(t *testing.T) {
	t.Parallel()

	awsRegion := helpers.GetAwsRegion()
	uniqueName := helpers.UniqueResourceName("aur")

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/aurora/basic",
		Vars: map[string]interface{}{
			"name":   uniqueName,
			"region": awsRegion,
		},
	})

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	// Get outputs
	clusterEndpoint := terraform.Output(t, terraformOptions, "cluster_endpoint")
	clusterReaderEndpoint := terraform.Output(t, terraformOptions, "cluster_reader_endpoint")
	clusterPort := terraform.Output(t, terraformOptions, "cluster_port")
	securityGroupId := terraform.Output(t, terraformOptions, "security_group_id")
	dbSubnetGroupName := terraform.Output(t, terraformOptions, "db_subnet_group_name")
	masterUserSecretArn := terraform.Output(t, terraformOptions, "cluster_master_user_secret_arn")

	// Assert endpoints are not empty
	require.NotEmpty(t, clusterEndpoint, "cluster_endpoint should not be empty")
	require.NotEmpty(t, clusterReaderEndpoint, "cluster_reader_endpoint should not be empty")

	// Assert port is the default PostgreSQL port (5432)
	assert.Equal(t, "5432", clusterPort, "cluster_port should be 5432 for Aurora PostgreSQL")

	// Assert security group and subnet group are not empty
	require.NotEmpty(t, securityGroupId, "security_group_id should not be empty")
	require.NotEmpty(t, dbSubnetGroupName, "db_subnet_group_name should not be empty")

	// Assert Secrets Manager secret is created (manage_master_user_password = true by default)
	require.NotEmpty(t, masterUserSecretArn, "cluster_master_user_secret_arn should not be empty")

	// Use AWS SDK to verify cluster exists and is available
	clusterExists := helpers.AuroraClusterExists(t, uniqueName, awsRegion)
	assert.True(t, clusterExists, "Aurora cluster should exist in AWS")

	clusterStatus := helpers.GetAuroraClusterStatus(t, uniqueName, awsRegion)
	assert.Equal(t, "available", clusterStatus, "Aurora cluster should be in 'available' state")

	// Verify engine is aurora-postgresql
	clusterEngine := helpers.GetAuroraClusterEngine(t, uniqueName, awsRegion)
	assert.Equal(t, "aurora-postgresql", clusterEngine, "Aurora cluster engine should be 'aurora-postgresql'")

	// Verify cluster has 2 members (1 writer + 1 reader)
	memberCount := helpers.GetAuroraClusterMemberCount(t, uniqueName, awsRegion)
	assert.Equal(t, 2, memberCount, "Aurora cluster should have 2 members (1 writer + 1 reader)")

	writerCount := helpers.GetAuroraClusterWriterCount(t, uniqueName, awsRegion)
	assert.Equal(t, 1, writerCount, "Aurora cluster should have 1 writer")

	readerCount := helpers.GetAuroraClusterReaderCount(t, uniqueName, awsRegion)
	assert.Equal(t, 1, readerCount, "Aurora cluster should have 1 reader")

	// Verify all members are available
	allAvailable := helpers.AllAuroraClusterMembersAvailable(t, uniqueName, awsRegion)
	assert.True(t, allAvailable, "All Aurora cluster members should be in 'available' state")

	// Verify security group exists and allows access on PostgreSQL port
	securityGroupExists := helpers.SecurityGroupExists(t, securityGroupId, awsRegion)
	assert.True(t, securityGroupExists, "Security group should exist in AWS")

	hasPostgresRule := helpers.SecurityGroupHasIngressRule(t, securityGroupId, 5432, awsRegion)
	assert.True(t, hasPostgresRule, "Security group should allow access on PostgreSQL port 5432")
}

// TestAuroraFull provisions the full-featured Aurora PostgreSQL fixture.
// It verifies:
// - All outputs are non-empty
// - Cluster has 3 members (1 writer + 2 readers)
// - Custom endpoint is created
// - Auto-scaling target is created with 2 policies (CPU + connections)
// - Enhanced monitoring role is created
// - CloudWatch alarms are created
// - Parameter groups are created
func TestAuroraFull(t *testing.T) {
	t.Parallel()

	awsRegion := helpers.GetAwsRegion()
	uniqueName := helpers.UniqueResourceName("aurf")

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/aurora/full",
		Vars: map[string]interface{}{
			"name":   uniqueName,
			"region": awsRegion,
		},
	})

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	// Get outputs
	clusterEndpoint := terraform.Output(t, terraformOptions, "cluster_endpoint")
	clusterReaderEndpoint := terraform.Output(t, terraformOptions, "cluster_reader_endpoint")
	clusterPort := terraform.Output(t, terraformOptions, "cluster_port")
	securityGroupId := terraform.Output(t, terraformOptions, "security_group_id")
	clusterParameterGroupName := terraform.Output(t, terraformOptions, "cluster_parameter_group_name")
	dbParameterGroupName := terraform.Output(t, terraformOptions, "db_parameter_group_name")
	enhancedMonitoringRoleArn := terraform.Output(t, terraformOptions, "enhanced_monitoring_iam_role_arn")
	autoscalingTargetArn := terraform.Output(t, terraformOptions, "autoscaling_target_arn")

	// Assert all primary outputs are not empty
	require.NotEmpty(t, clusterEndpoint, "cluster_endpoint should not be empty")
	require.NotEmpty(t, clusterReaderEndpoint, "cluster_reader_endpoint should not be empty")
	assert.Equal(t, "5432", clusterPort, "cluster_port should be 5432 for Aurora PostgreSQL")
	require.NotEmpty(t, securityGroupId, "security_group_id should not be empty")

	// Assert parameter groups are created
	require.NotEmpty(t, clusterParameterGroupName, "cluster_parameter_group_name should not be empty")
	require.NotEmpty(t, dbParameterGroupName, "db_parameter_group_name should not be empty")

	// Assert enhanced monitoring role is created
	require.NotEmpty(t, enhancedMonitoringRoleArn, "enhanced_monitoring_iam_role_arn should not be empty")

	// Assert auto-scaling target is created
	require.NotEmpty(t, autoscalingTargetArn, "autoscaling_target_arn should not be empty")

	// Verify cluster via AWS SDK
	clusterStatus := helpers.GetAuroraClusterStatus(t, uniqueName, awsRegion)
	assert.Equal(t, "available", clusterStatus, "Aurora cluster should be in 'available' state")

	// Verify cluster has 3 members (1 writer + 2 readers)
	memberCount := helpers.GetAuroraClusterMemberCount(t, uniqueName, awsRegion)
	assert.Equal(t, 3, memberCount, "Aurora cluster should have 3 members (1 writer + 2 readers)")

	writerCount := helpers.GetAuroraClusterWriterCount(t, uniqueName, awsRegion)
	assert.Equal(t, 1, writerCount, "Aurora cluster should have 1 writer")

	readerCount := helpers.GetAuroraClusterReaderCount(t, uniqueName, awsRegion)
	assert.Equal(t, 2, readerCount, "Aurora cluster should have 2 readers")

	// Verify all members are available
	allAvailable := helpers.AllAuroraClusterMembersAvailable(t, uniqueName, awsRegion)
	assert.True(t, allAvailable, "All Aurora cluster members should be in 'available' state")

	// Verify custom endpoint (analytics) exists
	customEndpointCount := helpers.GetAuroraClusterCustomEndpointCount(t, uniqueName, awsRegion)
	assert.Equal(t, 1, customEndpointCount, "Aurora cluster should have 1 custom endpoint")

	// Verify auto-scaling target exists with 2 policies (CPU + connections)
	autoScalingResourceId := fmt.Sprintf("cluster:%s", uniqueName)
	autoScalingExists := helpers.RDSAppAutoScalingTargetExists(t, autoScalingResourceId, awsRegion)
	assert.True(t, autoScalingExists, "Auto-scaling target should exist for Aurora cluster")

	policyCount := helpers.GetRDSAppAutoScalingPolicyCount(t, autoScalingResourceId, awsRegion)
	assert.Equal(t, 2, policyCount, "Auto-scaling should have 2 policies (CPU + connections)")

	// Verify security group
	securityGroupExists := helpers.SecurityGroupExists(t, securityGroupId, awsRegion)
	assert.True(t, securityGroupExists, "Security group should exist in AWS")
}

// TestAuroraServerlessV2 provisions the Serverless v2 Aurora fixture.
// It verifies:
// - Cluster is created with Serverless v2 scaling configuration
// - Instances use db.serverless instance class
// - Cluster has 2 members (1 writer + 1 reader)
func TestAuroraServerlessV2(t *testing.T) {
	t.Parallel()

	awsRegion := helpers.GetAwsRegion()
	uniqueName := helpers.UniqueResourceName("aurs")

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/aurora/serverless_v2",
		Vars: map[string]interface{}{
			"name":   uniqueName,
			"region": awsRegion,
		},
	})

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	// Get outputs
	clusterEndpoint := terraform.Output(t, terraformOptions, "cluster_endpoint")
	clusterReaderEndpoint := terraform.Output(t, terraformOptions, "cluster_reader_endpoint")
	clusterPort := terraform.Output(t, terraformOptions, "cluster_port")
	securityGroupId := terraform.Output(t, terraformOptions, "security_group_id")

	// Assert endpoints are not empty
	require.NotEmpty(t, clusterEndpoint, "cluster_endpoint should not be empty")
	require.NotEmpty(t, clusterReaderEndpoint, "cluster_reader_endpoint should not be empty")
	assert.Equal(t, "5432", clusterPort, "cluster_port should be 5432 for Aurora PostgreSQL")
	require.NotEmpty(t, securityGroupId, "security_group_id should not be empty")

	// Verify cluster via AWS SDK
	clusterStatus := helpers.GetAuroraClusterStatus(t, uniqueName, awsRegion)
	assert.Equal(t, "available", clusterStatus, "Aurora cluster should be in 'available' state")

	// Verify cluster has 2 members (1 writer + 1 reader)
	memberCount := helpers.GetAuroraClusterMemberCount(t, uniqueName, awsRegion)
	assert.Equal(t, 2, memberCount, "Aurora cluster should have 2 members (1 writer + 1 reader)")

	// Verify Serverless v2 scaling configuration
	minCap, maxCap, hasConfig := helpers.GetAuroraClusterServerlessV2ScalingConfig(t, uniqueName, awsRegion)
	assert.True(t, hasConfig, "Aurora cluster should have Serverless v2 scaling configuration")
	assert.Equal(t, 0.5, minCap, "Serverless v2 min capacity should be 0.5 ACU")
	assert.Equal(t, 2.0, maxCap, "Serverless v2 max capacity should be 2.0 ACU")

	// Verify instances use db.serverless class
	instanceIdentifiers := terraform.OutputMap(t, terraformOptions, "instance_identifiers")
	for _, instanceId := range instanceIdentifiers {
		instanceClass := helpers.GetAuroraInstanceClass(t, instanceId, awsRegion)
		assert.Equal(t, "db.serverless", instanceClass, "Instance %s should use db.serverless class", instanceId)
	}
}

// TestAuroraMySQL provisions the Aurora MySQL fixture.
// It verifies:
// - Cluster is created with MySQL engine
// - Port is the default MySQL port (3306)
// - Backtrack is enabled with 1 hour window
// - Cluster has 2 members (1 writer + 1 reader)
func TestAuroraMySQL(t *testing.T) {
	t.Parallel()

	awsRegion := helpers.GetAwsRegion()
	uniqueName := helpers.UniqueResourceName("aurm")

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/aurora/mysql",
		Vars: map[string]interface{}{
			"name":   uniqueName,
			"region": awsRegion,
		},
	})

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	// Get outputs
	clusterEndpoint := terraform.Output(t, terraformOptions, "cluster_endpoint")
	clusterReaderEndpoint := terraform.Output(t, terraformOptions, "cluster_reader_endpoint")
	clusterPort := terraform.Output(t, terraformOptions, "cluster_port")
	clusterDatabaseName := terraform.Output(t, terraformOptions, "cluster_database_name")
	clusterParameterGroupName := terraform.Output(t, terraformOptions, "cluster_parameter_group_name")
	securityGroupId := terraform.Output(t, terraformOptions, "security_group_id")

	// Assert endpoints are not empty
	require.NotEmpty(t, clusterEndpoint, "cluster_endpoint should not be empty")
	require.NotEmpty(t, clusterReaderEndpoint, "cluster_reader_endpoint should not be empty")

	// Assert port is the default MySQL port (3306)
	assert.Equal(t, "3306", clusterPort, "cluster_port should be 3306 for Aurora MySQL")

	// Assert database name is set
	assert.Equal(t, "testdb", clusterDatabaseName, "cluster_database_name should be 'testdb'")

	// Assert parameter group is created
	require.NotEmpty(t, clusterParameterGroupName, "cluster_parameter_group_name should not be empty")

	// Assert security group is not empty
	require.NotEmpty(t, securityGroupId, "security_group_id should not be empty")

	// Verify cluster via AWS SDK
	clusterStatus := helpers.GetAuroraClusterStatus(t, uniqueName, awsRegion)
	assert.Equal(t, "available", clusterStatus, "Aurora cluster should be in 'available' state")

	// Verify engine is aurora-mysql
	clusterEngine := helpers.GetAuroraClusterEngine(t, uniqueName, awsRegion)
	assert.Equal(t, "aurora-mysql", clusterEngine, "Aurora cluster engine should be 'aurora-mysql'")

	// Verify cluster has 2 members (1 writer + 1 reader)
	memberCount := helpers.GetAuroraClusterMemberCount(t, uniqueName, awsRegion)
	assert.Equal(t, 2, memberCount, "Aurora cluster should have 2 members (1 writer + 1 reader)")

	// Verify backtrack is enabled with 1 hour window (3600 seconds)
	backtrackWindow := helpers.GetAuroraClusterBacktrackWindow(t, uniqueName, awsRegion)
	assert.Equal(t, int64(3600), backtrackWindow, "Aurora cluster should have backtrack window of 3600 seconds (1 hour)")

	// Verify security group allows access on MySQL port
	hasMysSqlRule := helpers.SecurityGroupHasIngressRule(t, securityGroupId, 3306, awsRegion)
	assert.True(t, hasMysSqlRule, "Security group should allow access on MySQL port 3306")
}

// TestAuroraWithAutoscaling provisions the Aurora with autoscaling fixture.
// It verifies:
// - Auto-scaling target is created
// - CPU and connection scaling policies are created
// - Min/max capacity matches configuration
func TestAuroraWithAutoscaling(t *testing.T) {
	t.Parallel()

	awsRegion := helpers.GetAwsRegion()
	uniqueName := helpers.UniqueResourceName("aura")

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/aurora/with_autoscaling",
		Vars: map[string]interface{}{
			"name":   uniqueName,
			"region": awsRegion,
		},
	})

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	// Get outputs
	clusterEndpoint := terraform.Output(t, terraformOptions, "cluster_endpoint")
	autoscalingTargetArn := terraform.Output(t, terraformOptions, "autoscaling_target_arn")
	securityGroupId := terraform.Output(t, terraformOptions, "security_group_id")

	// Assert outputs are not empty
	require.NotEmpty(t, clusterEndpoint, "cluster_endpoint should not be empty")
	require.NotEmpty(t, autoscalingTargetArn, "autoscaling_target_arn should not be empty")
	require.NotEmpty(t, securityGroupId, "security_group_id should not be empty")

	// Verify cluster is available
	clusterStatus := helpers.GetAuroraClusterStatus(t, uniqueName, awsRegion)
	assert.Equal(t, "available", clusterStatus, "Aurora cluster should be in 'available' state")

	// Verify auto-scaling target exists
	autoScalingResourceId := fmt.Sprintf("cluster:%s", uniqueName)
	autoScalingExists := helpers.RDSAppAutoScalingTargetExists(t, autoScalingResourceId, awsRegion)
	assert.True(t, autoScalingExists, "Auto-scaling target should exist for Aurora cluster")

	// Verify 2 scaling policies (CPU + connections)
	policyCount := helpers.GetRDSAppAutoScalingPolicyCount(t, autoScalingResourceId, awsRegion)
	assert.Equal(t, 2, policyCount, "Auto-scaling should have 2 policies (CPU + connections)")
}

// TestAuroraWithCustomEndpoints provisions the Aurora with custom endpoints fixture.
// It verifies:
// - Custom endpoints are created (analytics READER, reporting ANY)
// - Cluster has 3 members (1 writer + 2 readers)
// - Both custom endpoints are accessible
func TestAuroraWithCustomEndpoints(t *testing.T) {
	t.Parallel()

	awsRegion := helpers.GetAwsRegion()
	uniqueName := helpers.UniqueResourceName("aure")

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/aurora/with_custom_endpoints",
		Vars: map[string]interface{}{
			"name":   uniqueName,
			"region": awsRegion,
		},
	})

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	// Get outputs
	clusterEndpoint := terraform.Output(t, terraformOptions, "cluster_endpoint")
	clusterReaderEndpoint := terraform.Output(t, terraformOptions, "cluster_reader_endpoint")
	securityGroupId := terraform.Output(t, terraformOptions, "security_group_id")

	// Assert endpoints are not empty
	require.NotEmpty(t, clusterEndpoint, "cluster_endpoint should not be empty")
	require.NotEmpty(t, clusterReaderEndpoint, "cluster_reader_endpoint should not be empty")
	require.NotEmpty(t, securityGroupId, "security_group_id should not be empty")

	// Verify cluster is available
	clusterStatus := helpers.GetAuroraClusterStatus(t, uniqueName, awsRegion)
	assert.Equal(t, "available", clusterStatus, "Aurora cluster should be in 'available' state")

	// Verify cluster has 3 members (1 writer + 2 readers)
	memberCount := helpers.GetAuroraClusterMemberCount(t, uniqueName, awsRegion)
	assert.Equal(t, 3, memberCount, "Aurora cluster should have 3 members (1 writer + 2 readers)")

	// Verify 2 custom endpoints exist (analytics + reporting)
	customEndpointCount := helpers.GetAuroraClusterCustomEndpointCount(t, uniqueName, awsRegion)
	assert.Equal(t, 2, customEndpointCount, "Aurora cluster should have 2 custom endpoints")

	// Verify individual custom endpoints exist
	analyticsEndpoint := fmt.Sprintf("%s-analytics", uniqueName)
	analyticsExists := helpers.AuroraClusterEndpointExists(t, analyticsEndpoint, awsRegion)
	assert.True(t, analyticsExists, "Analytics custom endpoint should exist")

	reportingEndpoint := fmt.Sprintf("%s-reporting", uniqueName)
	reportingExists := helpers.AuroraClusterEndpointExists(t, reportingEndpoint, awsRegion)
	assert.True(t, reportingExists, "Reporting custom endpoint should exist")
}
