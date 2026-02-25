// Package test contains Terratest integration tests for the Terraform modules.
package test

import (
	"testing"

	"github.com/flightcontrolhq/modules/test/helpers"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestLambdaBasic provisions the basic Lambda fixture.
// It verifies:
// - core Lambda outputs are not empty
// - Lambda function exists in AWS
// - runtime, handler, timeout, and role match fixture expectations
// - function URL is created when enabled
func TestLambdaBasic(t *testing.T) {
	t.Parallel()

	awsRegion := helpers.GetAwsRegion()
	uniqueName := helpers.UniqueResourceName("lmb")

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/lambda/basic",
		Vars: map[string]interface{}{
			"name":   uniqueName,
			"region": awsRegion,
		},
	})

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	functionName := terraform.Output(t, terraformOptions, "function_name")
	functionArn := terraform.Output(t, terraformOptions, "function_arn")
	roleArn := terraform.Output(t, terraformOptions, "role_arn")
	functionURL := terraform.Output(t, terraformOptions, "function_url")

	require.NotEmpty(t, functionName, "function_name should not be empty")
	require.NotEmpty(t, functionArn, "function_arn should not be empty")
	require.NotEmpty(t, roleArn, "role_arn should not be empty")
	require.NotEmpty(t, functionURL, "function_url should not be empty when function URL is enabled")

	exists := helpers.LambdaFunctionExists(t, functionName, awsRegion)
	assert.True(t, exists, "Lambda function should exist in AWS")

	runtime := helpers.GetLambdaFunctionRuntime(t, functionName, awsRegion)
	assert.Equal(t, "nodejs20.x", runtime, "Lambda runtime should match fixture")

	handler := helpers.GetLambdaFunctionHandler(t, functionName, awsRegion)
	assert.Equal(t, "index.handler", handler, "Lambda handler should match fixture")

	timeout := helpers.GetLambdaFunctionTimeout(t, functionName, awsRegion)
	assert.Equal(t, int32(10), timeout, "Lambda timeout should match fixture")

	awsRoleArn := helpers.GetLambdaFunctionRole(t, functionName, awsRegion)
	assert.Equal(t, roleArn, awsRoleArn, "Lambda IAM role should match module output")
}
