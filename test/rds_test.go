// Package test contains Terratest integration tests for the Terraform modules.
package test

import (
	"testing"

	"github.com/flightcontrolhq/modules/test/helpers"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestRdsBasic provisions the basic RDS fixture.
// It verifies:
// - primary RDS outputs are not empty
// - RDS instance exists in AWS
// - instance status, engine, class, and encryption match fixture expectations
func TestRdsBasic(t *testing.T) {
	t.Parallel()

	awsRegion := helpers.GetAwsRegion()
	uniqueName := helpers.UniqueResourceName("rds")

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/rds/basic",
		Vars: map[string]interface{}{
			"name":   uniqueName,
			"region": awsRegion,
		},
	})

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	instanceIdentifier := terraform.Output(t, terraformOptions, "db_instance_identifier")
	instanceArn := terraform.Output(t, terraformOptions, "db_instance_arn")
	instanceStatus := terraform.Output(t, terraformOptions, "db_instance_status")
	engine := terraform.Output(t, terraformOptions, "engine")
	address := terraform.Output(t, terraformOptions, "address")
	port := terraform.Output(t, terraformOptions, "port")
	securityGroupID := terraform.Output(t, terraformOptions, "security_group_id")

	require.NotEmpty(t, instanceIdentifier, "db_instance_identifier should not be empty")
	require.NotEmpty(t, instanceArn, "db_instance_arn should not be empty")
	require.NotEmpty(t, instanceStatus, "db_instance_status should not be empty")
	require.NotEmpty(t, address, "address should not be empty")
	require.NotEmpty(t, securityGroupID, "security_group_id should not be empty")

	assert.Equal(t, "postgres", engine, "engine output should be postgres")
	assert.Equal(t, "5432", port, "port should be 5432 for postgres")

	exists := helpers.RDSInstanceExists(t, instanceIdentifier, awsRegion)
	assert.True(t, exists, "RDS instance should exist in AWS")

	awsStatus := helpers.GetRDSInstanceStatus(t, instanceIdentifier, awsRegion)
	assert.Contains(t, []string{"available", "modifying"}, awsStatus, "RDS status should be in a valid post-create state")

	awsEngine := helpers.GetRDSInstanceEngine(t, instanceIdentifier, awsRegion)
	assert.Equal(t, "postgres", awsEngine, "RDS engine in AWS should match fixture")

	awsClass := helpers.GetRDSInstanceClass(t, instanceIdentifier, awsRegion)
	assert.Equal(t, "db.t3.micro", awsClass, "RDS instance class should match fixture")

	encrypted := helpers.IsRDSInstanceStorageEncrypted(t, instanceIdentifier, awsRegion)
	assert.True(t, encrypted, "RDS storage encryption should be enabled")

	sgExists := helpers.SecurityGroupExists(t, securityGroupID, awsRegion)
	assert.True(t, sgExists, "RDS security group should exist in AWS")
}
