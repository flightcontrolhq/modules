// Package test contains Terratest integration tests for the Terraform modules.
package test

import (
	"strings"
	"testing"

	"github.com/flightcontrolhq/modules/test/helpers"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestDynamoDBBasic provisions the basic on-demand DynamoDB fixture and
// verifies core outputs are populated correctly.
func TestDynamoDBBasic(t *testing.T) {
	t.Parallel()

	awsRegion := helpers.GetAwsRegion()
	uniqueName := helpers.UniqueResourceName("ddb")

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/dynamodb/basic",
		Vars: map[string]interface{}{
			"name":   uniqueName,
			"region": awsRegion,
		},
	})

	defer terraform.Destroy(t, terraformOptions)

	terraform.InitAndApply(t, terraformOptions)

	tableName := terraform.Output(t, terraformOptions, "table_name")
	tableArn := terraform.Output(t, terraformOptions, "table_arn")
	billingMode := terraform.Output(t, terraformOptions, "billing_mode")
	hashKey := terraform.Output(t, terraformOptions, "table_hash_key")

	assert.Equal(t, uniqueName, tableName, "table_name should equal the provided name")
	require.NotEmpty(t, tableArn, "table_arn should not be empty")
	assert.True(t, strings.HasPrefix(tableArn, "arn:aws:dynamodb:"), "table_arn should be a DynamoDB ARN")
	assert.Equal(t, "PAY_PER_REQUEST", billingMode, "billing_mode should default to on-demand")
	assert.Equal(t, "session_id", hashKey, "hash_key should match fixture configuration")
}

// TestDynamoDBWithGsi provisions a DynamoDB table that has one GSI, one LSI,
// and DynamoDB Streams enabled.
func TestDynamoDBWithGsi(t *testing.T) {
	t.Parallel()

	awsRegion := helpers.GetAwsRegion()
	uniqueName := helpers.UniqueResourceName("ddb-gsi")

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/dynamodb/with_gsi",
		Vars: map[string]interface{}{
			"name":   uniqueName,
			"region": awsRegion,
		},
	})

	defer terraform.Destroy(t, terraformOptions)

	terraform.InitAndApply(t, terraformOptions)

	tableArn := terraform.Output(t, terraformOptions, "table_arn")
	streamArn := terraform.Output(t, terraformOptions, "stream_arn")
	gsiNames := terraform.OutputList(t, terraformOptions, "global_secondary_index_names")
	lsiNames := terraform.OutputList(t, terraformOptions, "local_secondary_index_names")

	require.NotEmpty(t, tableArn, "table_arn should not be empty")
	require.NotEmpty(t, streamArn, "stream_arn should not be empty when streams are enabled")
	assert.True(t, strings.HasPrefix(streamArn, "arn:aws:dynamodb:"), "stream_arn should be a DynamoDB stream ARN")

	assert.Equal(t, []string{"by_event_type"}, gsiNames, "GSI name list should match fixture")
	assert.Equal(t, []string{"by_user_event_type"}, lsiNames, "LSI name list should match fixture")
}

// TestDynamoDBProvisioned provisions a DynamoDB table in PROVISIONED billing
// mode with Application Auto Scaling enabled for read and write capacity.
func TestDynamoDBProvisioned(t *testing.T) {
	t.Parallel()

	awsRegion := helpers.GetAwsRegion()
	uniqueName := helpers.UniqueResourceName("ddb-prov")

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/dynamodb/provisioned",
		Vars: map[string]interface{}{
			"name":   uniqueName,
			"region": awsRegion,
		},
	})

	defer terraform.Destroy(t, terraformOptions)

	terraform.InitAndApply(t, terraformOptions)

	billingMode := terraform.Output(t, terraformOptions, "billing_mode")
	readTargetArn := terraform.Output(t, terraformOptions, "autoscaling_table_read_target_arn")
	writeTargetArn := terraform.Output(t, terraformOptions, "autoscaling_table_write_target_arn")

	assert.Equal(t, "PROVISIONED", billingMode, "billing_mode should be PROVISIONED")
	require.NotEmpty(t, readTargetArn, "read autoscaling target should be created")
	require.NotEmpty(t, writeTargetArn, "write autoscaling target should be created")

	// Verify the autoscaling targets are registered with Application Auto Scaling.
	readResourceId := "table/" + uniqueName
	readExists := helpers.AppAutoScalingTargetExists(t, readResourceId, awsRegion)
	assert.True(t, readExists, "Application Auto Scaling target for the DynamoDB table should exist")

	policyCount := helpers.GetAppAutoScalingPolicyCount(t, readResourceId, awsRegion)
	assert.GreaterOrEqual(t, policyCount, 2, "Read + write target-tracking policies should be registered")
}
