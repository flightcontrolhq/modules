// Package test contains Terratest integration tests for the Terraform modules.
package test

import (
	"testing"

	"github.com/flightcontrolhq/modules/test/helpers"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestCloudFrontBasic provisions the basic CloudFront fixture.
// It verifies:
// - distribution outputs are not empty
// - CloudFront distribution exists in AWS
// - distribution status is a valid deployment state
func TestCloudFrontBasic(t *testing.T) {
	t.Parallel()

	awsRegion := helpers.GetAwsRegion()
	uniqueName := helpers.UniqueResourceName("cfd")

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/cloudfront/basic",
		Vars: map[string]interface{}{
			"name":   uniqueName,
			"region": awsRegion,
		},
	})

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	distributionID := terraform.Output(t, terraformOptions, "distribution_id")
	distributionArn := terraform.Output(t, terraformOptions, "distribution_arn")
	distributionDomainName := terraform.Output(t, terraformOptions, "distribution_domain_name")
	distributionStatus := terraform.Output(t, terraformOptions, "distribution_status")

	require.NotEmpty(t, distributionID, "distribution_id should not be empty")
	require.NotEmpty(t, distributionArn, "distribution_arn should not be empty")
	require.NotEmpty(t, distributionDomainName, "distribution_domain_name should not be empty")
	require.NotEmpty(t, distributionStatus, "distribution_status should not be empty")

	exists := helpers.CloudFrontDistributionExists(t, distributionID, awsRegion)
	assert.True(t, exists, "CloudFront distribution should exist in AWS")

	awsStatus := helpers.GetCloudFrontDistributionStatus(t, distributionID, awsRegion)
	assert.Contains(t, []string{"InProgress", "Deployed"}, awsStatus, "CloudFront distribution should be in a valid deployment state")
}
