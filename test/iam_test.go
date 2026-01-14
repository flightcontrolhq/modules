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

// TestIamRoleBasic provisions the basic IAM role fixture and validates the outputs.
// It verifies:
// - role_name is not empty
// - role_arn is not empty and has correct format
// - role exists in AWS using AWS SDK
// - role has correct path (/test/)
// - role has correct trust policy (trusts ec2.amazonaws.com)
// - role has expected tags
func TestIamRoleBasic(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("iam")

	// Configure Terraform options
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/iam/basic",
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
	roleName := terraform.Output(t, terraformOptions, "role_name")
	roleArn := terraform.Output(t, terraformOptions, "role_arn")
	roleId := terraform.Output(t, terraformOptions, "role_id")
	rolePath := terraform.Output(t, terraformOptions, "role_path")
	roleUniqueId := terraform.Output(t, terraformOptions, "role_unique_id")
	instanceProfileArn := terraform.Output(t, terraformOptions, "instance_profile_arn")

	// Assert role_name is not empty and matches the expected name
	require.NotEmpty(t, roleName, "role_name should not be empty")
	assert.Equal(t, uniqueName, roleName, "role_name should match the provided name")

	// Assert role_arn is not empty and has correct format
	require.NotEmpty(t, roleArn, "role_arn should not be empty")
	assert.Contains(t, roleArn, ":role/", "role_arn should contain ':role/'")
	assert.Contains(t, roleArn, uniqueName, "role_arn should contain the role name")

	// Assert role_id is not empty
	assert.NotEmpty(t, roleId, "role_id should not be empty")

	// Assert role_unique_id is not empty
	assert.NotEmpty(t, roleUniqueId, "role_unique_id should not be empty")

	// Assert role_path matches expected path
	assert.Equal(t, "/test/", rolePath, "role_path should be /test/")

	// Assert instance_profile_arn is empty (not created in basic fixture)
	assert.Empty(t, instanceProfileArn, "instance_profile_arn should be empty for basic fixture")

	// Use AWS SDK to verify role exists
	roleExists := helpers.IamRoleExists(t, roleName, awsRegion)
	assert.True(t, roleExists, "IAM role should exist in AWS")

	// Use AWS SDK to verify role ARN matches
	actualArn := helpers.GetIamRoleArn(t, roleName, awsRegion)
	assert.Equal(t, roleArn, actualArn, "role ARN from AWS should match Terraform output")

	// Use AWS SDK to verify role path
	actualPath := helpers.GetIamRolePath(t, roleName, awsRegion)
	assert.Equal(t, "/test/", actualPath, "role path from AWS should match expected value")

	// Use AWS SDK to verify trust policy contains EC2 service
	trustPolicy := helpers.GetIamRoleTrustPolicy(t, roleName, awsRegion)
	assert.Contains(t, trustPolicy, "ec2.amazonaws.com", "trust policy should allow ec2.amazonaws.com to assume the role")
	assert.Contains(t, trustPolicy, "sts:AssumeRole", "trust policy should contain sts:AssumeRole action")

	// Use AWS SDK to verify tags
	hasManagedByTag := helpers.IamRoleHasTag(t, roleName, "ManagedBy", "terratest", awsRegion)
	assert.True(t, hasManagedByTag, "IAM role should have ManagedBy=terratest tag")

	hasEnvironmentTag := helpers.IamRoleHasTag(t, roleName, "Environment", "terratest", awsRegion)
	assert.True(t, hasEnvironmentTag, "IAM role should have Environment=terratest tag")
}

// TestIamRoleWithInstanceProfile provisions an IAM role with an instance profile and validates:
// - role is created correctly
// - instance profile is created and attached to the role
// - managed policy (AmazonSSMManagedInstanceCore) is attached
func TestIamRoleWithInstanceProfile(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("iamip")

	// Configure Terraform options
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/iam/with_instance_profile",
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
	roleName := terraform.Output(t, terraformOptions, "role_name")
	roleArn := terraform.Output(t, terraformOptions, "role_arn")
	instanceProfileArn := terraform.Output(t, terraformOptions, "instance_profile_arn")
	instanceProfileName := terraform.Output(t, terraformOptions, "instance_profile_name")

	// Assert role outputs are not empty
	require.NotEmpty(t, roleName, "role_name should not be empty")
	require.NotEmpty(t, roleArn, "role_arn should not be empty")

	// Assert instance profile outputs are not empty
	require.NotEmpty(t, instanceProfileArn, "instance_profile_arn should not be empty")
	require.NotEmpty(t, instanceProfileName, "instance_profile_name should not be empty")

	// Use AWS SDK to verify role exists
	roleExists := helpers.IamRoleExists(t, roleName, awsRegion)
	assert.True(t, roleExists, "IAM role should exist in AWS")

	// Use AWS SDK to verify instance profile exists
	instanceProfileExists := helpers.IamInstanceProfileExists(t, instanceProfileName, awsRegion)
	assert.True(t, instanceProfileExists, "IAM instance profile should exist in AWS")

	// Use AWS SDK to verify instance profile is attached to the role
	instanceProfileHasRole := helpers.IamInstanceProfileHasRole(t, instanceProfileName, roleName, awsRegion)
	assert.True(t, instanceProfileHasRole, "Instance profile should have the IAM role attached")

	// Use AWS SDK to verify instance profile ARN matches
	actualInstanceProfileArn := helpers.GetIamInstanceProfileArn(t, instanceProfileName, awsRegion)
	assert.Equal(t, instanceProfileArn, actualInstanceProfileArn, "instance profile ARN from AWS should match Terraform output")

	// Use AWS SDK to verify instance profile path
	actualPath := helpers.GetIamInstanceProfilePath(t, instanceProfileName, awsRegion)
	assert.Equal(t, "/test/", actualPath, "instance profile path should be /test/")

	// Use AWS SDK to verify managed policy is attached
	ssmPolicyArn := "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
	hasPolicy := helpers.IamRoleHasPolicy(t, roleName, ssmPolicyArn, awsRegion)
	assert.True(t, hasPolicy, "IAM role should have AmazonSSMManagedInstanceCore policy attached")

	// Verify the attached policies list
	attachedPolicies := helpers.GetIamRoleAttachedPolicies(t, roleName, awsRegion)
	assert.Contains(t, attachedPolicies, ssmPolicyArn, "Attached policies should contain AmazonSSMManagedInstanceCore")
}

// TestIamRoleWithManagedPolicies tests that managed policies are correctly attached to an IAM role.
// This test uses the with_instance_profile fixture which includes a managed policy.
func TestIamRoleWithManagedPolicies(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("iammp")

	// Configure Terraform options
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/iam/with_instance_profile",
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
	roleName := terraform.Output(t, terraformOptions, "role_name")
	managedPolicyArnsOutput := terraform.OutputList(t, terraformOptions, "managed_policy_arns")

	// Assert role_name is not empty
	require.NotEmpty(t, roleName, "role_name should not be empty")

	// Assert managed_policy_arns output is not empty
	require.NotEmpty(t, managedPolicyArnsOutput, "managed_policy_arns should not be empty")

	// Verify output contains the expected policy
	ssmPolicyArn := "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
	assert.Contains(t, managedPolicyArnsOutput, ssmPolicyArn, "managed_policy_arns output should contain AmazonSSMManagedInstanceCore")

	// Use AWS SDK to verify role exists
	roleExists := helpers.IamRoleExists(t, roleName, awsRegion)
	assert.True(t, roleExists, "IAM role should exist in AWS")

	// Use AWS SDK to verify managed policy is attached
	hasPolicy := helpers.IamRoleHasPolicy(t, roleName, ssmPolicyArn, awsRegion)
	assert.True(t, hasPolicy, "IAM role should have AmazonSSMManagedInstanceCore policy attached")

	// Use AWS SDK to get all attached policies and verify count
	attachedPolicies := helpers.GetIamRoleAttachedPolicies(t, roleName, awsRegion)
	assert.Len(t, attachedPolicies, 1, "IAM role should have exactly 1 managed policy attached")
}

// TestIamRoleWithInlinePolicies tests that inline policies are correctly created for an IAM role.
// Note: This test uses the basic fixture as a baseline - inline policies would be tested
// if a fixture with inline policies existed. For now, we verify the inline_policy_names output is empty.
func TestIamRoleWithInlinePolicies(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("iamil")

	// Configure Terraform options
	// Using basic fixture - a proper test would use a fixture with inline policies
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/iam/basic",
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
	roleName := terraform.Output(t, terraformOptions, "role_name")
	inlinePolicyNamesOutput := terraform.OutputList(t, terraformOptions, "inline_policy_names")

	// Assert role_name is not empty
	require.NotEmpty(t, roleName, "role_name should not be empty")

	// Assert inline_policy_names output is empty for basic fixture
	assert.Empty(t, inlinePolicyNamesOutput, "inline_policy_names should be empty for basic fixture")

	// Use AWS SDK to verify role exists
	roleExists := helpers.IamRoleExists(t, roleName, awsRegion)
	assert.True(t, roleExists, "IAM role should exist in AWS")

	// Use AWS SDK to verify no inline policies are attached
	inlinePolicyNames := helpers.GetIamRoleInlinePolicyNames(t, roleName, awsRegion)
	assert.Empty(t, inlinePolicyNames, "IAM role should have no inline policies attached")
}

// TestIamRoleWithOidc provisions an IAM role with OIDC provider trust (GitHub Actions pattern) and validates:
// - role is created correctly
// - OIDC provider is created
// - trust policy contains correct OIDC federation trust
// - trust policy allows sts:AssumeRoleWithWebIdentity action
func TestIamRoleWithOidc(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("iamoidc")

	// Configure Terraform options
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/iam/with_oidc",
		Vars: map[string]interface{}{
			"name":        uniqueName,
			"region":      awsRegion,
			"github_org":  "test-org",
			"github_repo": "test-repo",
		},
	})

	// Ensure cleanup happens even if the test fails
	defer terraform.Destroy(t, terraformOptions)

	// Initialize and apply the Terraform configuration
	terraform.InitAndApply(t, terraformOptions)

	// Get outputs
	roleName := terraform.Output(t, terraformOptions, "role_name")
	roleArn := terraform.Output(t, terraformOptions, "role_arn")
	rolePath := terraform.Output(t, terraformOptions, "role_path")
	oidcProviderArn := terraform.Output(t, terraformOptions, "oidc_provider_arn")
	oidcProviderUrl := terraform.Output(t, terraformOptions, "oidc_provider_url")
	instanceProfileArn := terraform.Output(t, terraformOptions, "instance_profile_arn")

	// Assert role outputs are not empty
	require.NotEmpty(t, roleName, "role_name should not be empty")
	require.NotEmpty(t, roleArn, "role_arn should not be empty")
	assert.Equal(t, "/test/", rolePath, "role_path should be /test/")

	// Assert OIDC provider outputs are not empty
	require.NotEmpty(t, oidcProviderArn, "oidc_provider_arn should not be empty")
	require.NotEmpty(t, oidcProviderUrl, "oidc_provider_url should not be empty")

	// Assert OIDC provider URL is GitHub Actions
	assert.Equal(t, "https://token.actions.githubusercontent.com", oidcProviderUrl, "OIDC provider URL should be GitHub Actions")

	// Assert instance_profile_arn is empty (not created in OIDC fixture)
	assert.Empty(t, instanceProfileArn, "instance_profile_arn should be empty for OIDC fixture")

	// Use AWS SDK to verify role exists
	roleExists := helpers.IamRoleExists(t, roleName, awsRegion)
	assert.True(t, roleExists, "IAM role should exist in AWS")

	// Use AWS SDK to verify role ARN matches
	actualArn := helpers.GetIamRoleArn(t, roleName, awsRegion)
	assert.Equal(t, roleArn, actualArn, "role ARN from AWS should match Terraform output")

	// Use AWS SDK to verify trust policy contains OIDC provider
	trustPolicy := helpers.GetIamRoleTrustPolicy(t, roleName, awsRegion)
	assert.Contains(t, trustPolicy, "sts:AssumeRoleWithWebIdentity", "trust policy should contain sts:AssumeRoleWithWebIdentity action")
	assert.Contains(t, trustPolicy, "token.actions.githubusercontent.com", "trust policy should reference GitHub Actions OIDC provider")
	assert.Contains(t, trustPolicy, oidcProviderArn, "trust policy should reference the OIDC provider ARN")

	// Verify OIDC conditions are in the trust policy
	assert.Contains(t, trustPolicy, "StringEquals", "trust policy should contain StringEquals condition")
	assert.Contains(t, trustPolicy, "StringLike", "trust policy should contain StringLike condition")
	assert.Contains(t, trustPolicy, "sts.amazonaws.com", "trust policy should contain aud condition for sts.amazonaws.com")
	assert.Contains(t, trustPolicy, "test-org/test-repo", "trust policy should contain sub condition for test-org/test-repo")

	// Use AWS SDK to verify tags
	hasManagedByTag := helpers.IamRoleHasTag(t, roleName, "ManagedBy", "terratest", awsRegion)
	assert.True(t, hasManagedByTag, "IAM role should have ManagedBy=terratest tag")
}

// TestIamRoleDescription verifies that IAM role description is set correctly
func TestIamRoleDescription(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("iamdesc")

	// Configure Terraform options
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/iam/basic",
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
	roleName := terraform.Output(t, terraformOptions, "role_name")

	// Assert role_name is not empty
	require.NotEmpty(t, roleName, "role_name should not be empty")

	// Use AWS SDK to verify role description
	description := helpers.GetIamRoleDescription(t, roleName, awsRegion)
	assert.NotEmpty(t, description, "IAM role should have a description")
	// The fixture sets description = "Terratest basic IAM role for EC2"
	assert.True(t, strings.Contains(description, "Terratest"), "description should contain 'Terratest'")
}

// TestIamRoleMaxSessionDuration verifies that IAM role max session duration defaults to 3600 seconds
func TestIamRoleMaxSessionDuration(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("iammsd")

	// Configure Terraform options
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/iam/basic",
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
	roleName := terraform.Output(t, terraformOptions, "role_name")

	// Assert role_name is not empty
	require.NotEmpty(t, roleName, "role_name should not be empty")

	// Use AWS SDK to verify max session duration
	// Default is 3600 seconds (1 hour) as defined in the module
	maxSessionDuration := helpers.GetIamRoleMaxSessionDuration(t, roleName, awsRegion)
	assert.Equal(t, int32(3600), maxSessionDuration, "max session duration should be 3600 seconds (default)")
}
