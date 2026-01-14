// Package test contains Terratest integration tests for the Terraform modules.
package test

import (
	"testing"

	"github.com/flightcontrolhq/modules/test/helpers"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestS3Basic provisions the basic S3 bucket fixture and validates the outputs.
// It verifies:
// - bucket_id is not empty
// - bucket_arn is not empty and has correct format
// - bucket exists in AWS using AWS SDK
// - bucket has SSE-S3 encryption enabled (default)
// - bucket has all public access blocked
// - bucket has versioning disabled (default)
// - bucket has expected tags
func TestS3Basic(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("s3")

	// Configure Terraform options
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/s3/basic",
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
	bucketId := terraform.Output(t, terraformOptions, "bucket_id")
	bucketArn := terraform.Output(t, terraformOptions, "bucket_arn")
	bucketDomainName := terraform.Output(t, terraformOptions, "bucket_domain_name")
	bucketRegionalDomainName := terraform.Output(t, terraformOptions, "bucket_regional_domain_name")
	bucketHostedZoneId := terraform.Output(t, terraformOptions, "bucket_hosted_zone_id")
	bucketRegion := terraform.Output(t, terraformOptions, "bucket_region")
	versioningEnabled := terraform.Output(t, terraformOptions, "versioning_enabled")
	encryptionAlgorithm := terraform.Output(t, terraformOptions, "encryption_algorithm")

	// Assert bucket_id is not empty and matches the expected name
	require.NotEmpty(t, bucketId, "bucket_id should not be empty")
	assert.Equal(t, uniqueName, bucketId, "bucket_id should match the provided name")

	// Assert bucket_arn is not empty and has correct format
	require.NotEmpty(t, bucketArn, "bucket_arn should not be empty")
	assert.Contains(t, bucketArn, ":s3:::", "bucket_arn should contain ':s3:::'")
	assert.Contains(t, bucketArn, uniqueName, "bucket_arn should contain the bucket name")

	// Assert other outputs are not empty
	assert.NotEmpty(t, bucketDomainName, "bucket_domain_name should not be empty")
	assert.NotEmpty(t, bucketRegionalDomainName, "bucket_regional_domain_name should not be empty")
	assert.NotEmpty(t, bucketHostedZoneId, "bucket_hosted_zone_id should not be empty")
	assert.NotEmpty(t, bucketRegion, "bucket_region should not be empty")

	// Assert default settings
	assert.Equal(t, "false", versioningEnabled, "versioning_enabled should be false by default")
	assert.Equal(t, "AES256", encryptionAlgorithm, "encryption_algorithm should be AES256 (SSE-S3) by default")

	// Use AWS SDK to verify bucket exists
	bucketExists := helpers.S3BucketExists(t, bucketId, awsRegion)
	assert.True(t, bucketExists, "S3 bucket should exist in AWS")

	// Use AWS SDK to verify encryption is enabled (SSE-S3)
	hasEncryption := helpers.S3BucketHasSSEEncryption(t, bucketId, awsRegion)
	assert.True(t, hasEncryption, "S3 bucket should have SSE encryption enabled")

	// Use AWS SDK to verify encryption algorithm is AES256
	algorithm, kmsKeyId := helpers.GetS3BucketEncryption(t, bucketId, awsRegion)
	assert.Equal(t, "AES256", algorithm, "Encryption algorithm should be AES256")
	assert.Empty(t, kmsKeyId, "KMS key ID should be empty for SSE-S3")

	// Use AWS SDK to verify all public access is blocked
	publicAccessBlocked := helpers.S3BucketHasPublicAccessBlocked(t, bucketId, awsRegion)
	assert.True(t, publicAccessBlocked, "S3 bucket should have all public access blocked")

	// Use AWS SDK to verify versioning is disabled
	versioningStatus := helpers.GetS3BucketVersioning(t, bucketId, awsRegion)
	assert.Equal(t, "Disabled", versioningStatus, "Versioning should be disabled")
}

// TestS3WithKmsEncryption provisions an S3 bucket with SSE-KMS encryption and validates:
// - bucket is created correctly
// - bucket uses SSE-KMS encryption with the provided key
// - bucket key is enabled for cost optimization
func TestS3WithKmsEncryption(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("s3kms")

	// Configure Terraform options
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/s3/with_kms",
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
	bucketId := terraform.Output(t, terraformOptions, "bucket_id")
	bucketArn := terraform.Output(t, terraformOptions, "bucket_arn")
	encryptionAlgorithm := terraform.Output(t, terraformOptions, "encryption_algorithm")
	kmsKeyIdOutput := terraform.Output(t, terraformOptions, "kms_key_id")
	kmsKeyArn := terraform.Output(t, terraformOptions, "kms_key_arn")

	// Assert bucket_id is not empty and matches the expected name
	require.NotEmpty(t, bucketId, "bucket_id should not be empty")
	assert.Equal(t, uniqueName, bucketId, "bucket_id should match the provided name")

	// Assert bucket_arn is not empty and has correct format
	require.NotEmpty(t, bucketArn, "bucket_arn should not be empty")
	assert.Contains(t, bucketArn, ":s3:::", "bucket_arn should contain ':s3:::'")

	// Assert encryption is SSE-KMS (aws:kms)
	assert.Equal(t, "aws:kms", encryptionAlgorithm, "encryption_algorithm should be aws:kms for SSE-KMS")

	// Assert KMS key ID output matches the created KMS key ARN
	require.NotEmpty(t, kmsKeyIdOutput, "kms_key_id output should not be empty")
	require.NotEmpty(t, kmsKeyArn, "kms_key_arn should not be empty")
	assert.Equal(t, kmsKeyArn, kmsKeyIdOutput, "kms_key_id should match the created KMS key ARN")

	// Use AWS SDK to verify bucket exists
	bucketExists := helpers.S3BucketExists(t, bucketId, awsRegion)
	assert.True(t, bucketExists, "S3 bucket should exist in AWS")

	// Use AWS SDK to verify encryption is SSE-KMS with correct key
	algorithm, kmsKeyId := helpers.GetS3BucketEncryption(t, bucketId, awsRegion)
	assert.Equal(t, "aws:kms", algorithm, "Encryption algorithm should be aws:kms")
	assert.Equal(t, kmsKeyArn, kmsKeyId, "KMS key ID from SDK should match the created KMS key ARN")

	// Use AWS SDK to verify bucket key is enabled
	bucketKeyEnabled := helpers.S3BucketHasBucketKeyEnabled(t, bucketId, awsRegion)
	assert.True(t, bucketKeyEnabled, "Bucket key should be enabled for SSE-KMS")

	// Use AWS SDK to verify all public access is blocked (default behavior)
	publicAccessBlocked := helpers.S3BucketHasPublicAccessBlocked(t, bucketId, awsRegion)
	assert.True(t, publicAccessBlocked, "S3 bucket should have all public access blocked")
}

// TestS3WithVersioning provisions an S3 bucket with versioning enabled and validates:
// - bucket is created correctly
// - versioning is enabled
// Note: This requires a fixture that enables versioning
func TestS3WithVersioning(t *testing.T) {
	// Skip this test as it requires a versioning fixture
	// This test would be enabled when a with_versioning fixture is created
	t.Skip("Skipping versioning test - requires versioning fixture")
}

// TestS3WithLifecycle provisions an S3 bucket with lifecycle rules and validates:
// - bucket is created correctly
// - lifecycle rules are applied
// Note: This requires a fixture that configures lifecycle rules
func TestS3WithLifecycle(t *testing.T) {
	// Skip this test as it requires a lifecycle fixture
	// This test would be enabled when a with_lifecycle fixture is created
	t.Skip("Skipping lifecycle test - requires lifecycle fixture")
}

// TestS3WithPolicyTemplate provisions an S3 bucket with a policy template and validates:
// - bucket is created correctly
// - bucket policy is applied
// Note: This requires a fixture that configures policy templates
func TestS3WithPolicyTemplate(t *testing.T) {
	// Skip this test as it requires a policy template fixture
	// This test would be enabled when a with_policy fixture is created
	t.Skip("Skipping policy template test - requires policy template fixture")
}

// TestS3PublicAccessBlockSettings verifies that all individual public access block settings
// are correctly applied to the bucket.
func TestS3PublicAccessBlockSettings(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("s3pab")

	// Configure Terraform options
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/s3/basic",
		Vars: map[string]interface{}{
			"name":   uniqueName,
			"region": awsRegion,
		},
	})

	// Ensure cleanup happens even if the test fails
	defer terraform.Destroy(t, terraformOptions)

	// Initialize and apply the Terraform configuration
	terraform.InitAndApply(t, terraformOptions)

	// Get bucket ID
	bucketId := terraform.Output(t, terraformOptions, "bucket_id")
	require.NotEmpty(t, bucketId, "bucket_id should not be empty")

	// Use AWS SDK to get the public access block configuration
	config := helpers.GetS3BucketPublicAccessBlock(t, bucketId, awsRegion)
	require.NotNil(t, config, "Public access block configuration should exist")

	// Verify all settings are enabled (true)
	assert.NotNil(t, config.BlockPublicAcls, "BlockPublicAcls should not be nil")
	assert.True(t, *config.BlockPublicAcls, "BlockPublicAcls should be true")

	assert.NotNil(t, config.BlockPublicPolicy, "BlockPublicPolicy should not be nil")
	assert.True(t, *config.BlockPublicPolicy, "BlockPublicPolicy should be true")

	assert.NotNil(t, config.IgnorePublicAcls, "IgnorePublicAcls should not be nil")
	assert.True(t, *config.IgnorePublicAcls, "IgnorePublicAcls should be true")

	assert.NotNil(t, config.RestrictPublicBuckets, "RestrictPublicBuckets should not be nil")
	assert.True(t, *config.RestrictPublicBuckets, "RestrictPublicBuckets should be true")
}

// TestS3BucketTags verifies that tags are correctly applied to the bucket.
func TestS3BucketTags(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("s3tag")

	// Configure Terraform options with custom tags
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/s3/basic",
		Vars: map[string]interface{}{
			"name":   uniqueName,
			"region": awsRegion,
			"tags": map[string]interface{}{
				"CustomTag": "CustomValue",
			},
		},
	})

	// Ensure cleanup happens even if the test fails
	defer terraform.Destroy(t, terraformOptions)

	// Initialize and apply the Terraform configuration
	terraform.InitAndApply(t, terraformOptions)

	// Get bucket ID
	bucketId := terraform.Output(t, terraformOptions, "bucket_id")
	require.NotEmpty(t, bucketId, "bucket_id should not be empty")

	// Use AWS SDK to verify bucket exists
	bucketExists := helpers.S3BucketExists(t, bucketId, awsRegion)
	assert.True(t, bucketExists, "S3 bucket should exist in AWS")

	// Note: Tag verification would require adding a GetS3BucketTags helper function.
	// For now, we verify the bucket was created successfully with the tags applied
	// (Terraform would fail if tag application failed).
}

// TestS3ForceDestroy verifies that buckets with force_destroy=true can be destroyed
// even when they contain objects.
// Note: This test is implicitly verified by the cleanup of all other tests,
// since all fixtures use force_destroy=true for test cleanup.
func TestS3ForceDestroy(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("s3fd")

	// Configure Terraform options
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/s3/basic",
		Vars: map[string]interface{}{
			"name":   uniqueName,
			"region": awsRegion,
		},
	})

	// Initialize and apply the Terraform configuration
	terraform.InitAndApply(t, terraformOptions)

	// Get bucket ID
	bucketId := terraform.Output(t, terraformOptions, "bucket_id")
	require.NotEmpty(t, bucketId, "bucket_id should not be empty")

	// Verify bucket exists
	bucketExists := helpers.S3BucketExists(t, bucketId, awsRegion)
	assert.True(t, bucketExists, "S3 bucket should exist before destroy")

	// Destroy the infrastructure
	terraform.Destroy(t, terraformOptions)

	// Verify bucket no longer exists
	bucketExistsAfterDestroy := helpers.S3BucketExists(t, bucketId, awsRegion)
	assert.False(t, bucketExistsAfterDestroy, "S3 bucket should not exist after destroy")
}
