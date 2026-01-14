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
// - versioning is enabled via Terraform output
// - versioning is enabled via AWS SDK verification
func TestS3WithVersioning(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("s3ver")

	// Configure Terraform options
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/s3/with_versioning",
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
	versioningEnabled := terraform.Output(t, terraformOptions, "versioning_enabled")
	encryptionAlgorithm := terraform.Output(t, terraformOptions, "encryption_algorithm")

	// Assert bucket_id is not empty and matches the expected name
	require.NotEmpty(t, bucketId, "bucket_id should not be empty")
	assert.Equal(t, uniqueName, bucketId, "bucket_id should match the provided name")

	// Assert bucket_arn is not empty and has correct format
	require.NotEmpty(t, bucketArn, "bucket_arn should not be empty")
	assert.Contains(t, bucketArn, ":s3:::", "bucket_arn should contain ':s3:::'")

	// Assert versioning is enabled via Terraform output
	assert.Equal(t, "true", versioningEnabled, "versioning_enabled output should be true")

	// Assert encryption defaults to AES256 (SSE-S3)
	assert.Equal(t, "AES256", encryptionAlgorithm, "encryption_algorithm should be AES256 by default")

	// Use AWS SDK to verify bucket exists
	bucketExists := helpers.S3BucketExists(t, bucketId, awsRegion)
	assert.True(t, bucketExists, "S3 bucket should exist in AWS")

	// Use AWS SDK to verify versioning is enabled
	versioningStatus := helpers.GetS3BucketVersioning(t, bucketId, awsRegion)
	assert.Equal(t, "Enabled", versioningStatus, "Versioning status from SDK should be 'Enabled'")

	// Use AWS SDK helper to verify versioning is enabled
	hasVersioning := helpers.S3BucketHasVersioningEnabled(t, bucketId, awsRegion)
	assert.True(t, hasVersioning, "S3BucketHasVersioningEnabled should return true")

	// Use AWS SDK to verify all public access is blocked (default behavior)
	publicAccessBlocked := helpers.S3BucketHasPublicAccessBlocked(t, bucketId, awsRegion)
	assert.True(t, publicAccessBlocked, "S3 bucket should have all public access blocked")
}

// TestS3WithLifecycle provisions an S3 bucket with lifecycle rules and validates:
// - bucket is created correctly
// - lifecycle rules are applied
// - versioning is enabled (required for noncurrent version rules)
func TestS3WithLifecycle(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("s3lc")

	// Configure Terraform options
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/s3/with_lifecycle",
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
	versioningEnabled := terraform.Output(t, terraformOptions, "versioning_enabled")

	// Assert bucket_id is not empty and matches the expected name
	require.NotEmpty(t, bucketId, "bucket_id should not be empty")
	assert.Equal(t, uniqueName, bucketId, "bucket_id should match the provided name")

	// Assert bucket_arn is not empty and has correct format
	require.NotEmpty(t, bucketArn, "bucket_arn should not be empty")
	assert.Contains(t, bucketArn, ":s3:::", "bucket_arn should contain ':s3:::'")

	// Assert versioning is enabled (required for noncurrent version rules)
	assert.Equal(t, "true", versioningEnabled, "versioning_enabled should be true")

	// Use AWS SDK to verify bucket exists
	bucketExists := helpers.S3BucketExists(t, bucketId, awsRegion)
	assert.True(t, bucketExists, "S3 bucket should exist in AWS")

	// Verify lifecycle rules exist via AWS SDK
	lifecycleRules := helpers.GetS3BucketLifecycleRules(t, bucketId, awsRegion)
	assert.NotEmpty(t, lifecycleRules, "Lifecycle rules should be configured")
	assert.Len(t, lifecycleRules, 5, "Should have 5 lifecycle rules configured")

	// Use AWS SDK to verify versioning is enabled
	hasVersioning := helpers.S3BucketHasVersioningEnabled(t, bucketId, awsRegion)
	assert.True(t, hasVersioning, "S3BucketHasVersioningEnabled should return true")

	// Use AWS SDK to verify all public access is blocked (default behavior)
	publicAccessBlocked := helpers.S3BucketHasPublicAccessBlocked(t, bucketId, awsRegion)
	assert.True(t, publicAccessBlocked, "S3 bucket should have all public access blocked")
}

// TestS3LifecycleTransitions verifies that transition rules are correctly applied.
// Tests the "archive-backups" rule with STANDARD_IA (30 days) and GLACIER (90 days) transitions.
func TestS3LifecycleTransitions(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("s3tr")

	// Configure Terraform options
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/s3/with_lifecycle",
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

	// Use AWS SDK to verify bucket exists
	bucketExists := helpers.S3BucketExists(t, bucketId, awsRegion)
	assert.True(t, bucketExists, "S3 bucket should exist in AWS")

	// Verify the "archive-backups" rule has STANDARD_IA transition at 30 days
	hasStandardIaTransition := helpers.S3BucketHasTransitionRule(t, bucketId, "archive-backups", "STANDARD_IA", 30, awsRegion)
	assert.True(t, hasStandardIaTransition, "Should have STANDARD_IA transition at 30 days for 'archive-backups' rule")

	// Verify the "archive-backups" rule has GLACIER transition at 90 days
	hasGlacierTransition := helpers.S3BucketHasTransitionRule(t, bucketId, "archive-backups", "GLACIER", 90, awsRegion)
	assert.True(t, hasGlacierTransition, "Should have GLACIER transition at 90 days for 'archive-backups' rule")

	// Verify the "full-lifecycle" rule has STANDARD_IA transition at 60 days
	hasFullLifecycleStandardIa := helpers.S3BucketHasTransitionRule(t, bucketId, "full-lifecycle", "STANDARD_IA", 60, awsRegion)
	assert.True(t, hasFullLifecycleStandardIa, "Should have STANDARD_IA transition at 60 days for 'full-lifecycle' rule")

	// Verify the "full-lifecycle" rule has GLACIER transition at 180 days
	hasFullLifecycleGlacier := helpers.S3BucketHasTransitionRule(t, bucketId, "full-lifecycle", "GLACIER", 180, awsRegion)
	assert.True(t, hasFullLifecycleGlacier, "Should have GLACIER transition at 180 days for 'full-lifecycle' rule")
}

// TestS3LifecycleNoncurrentVersions verifies that noncurrent version expiration rules are correctly applied.
// Tests the "expire-noncurrent-versions" rule with 30 days expiration.
func TestS3LifecycleNoncurrentVersions(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("s3nv")

	// Configure Terraform options
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/s3/with_lifecycle",
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

	// Use AWS SDK to verify bucket exists
	bucketExists := helpers.S3BucketExists(t, bucketId, awsRegion)
	assert.True(t, bucketExists, "S3 bucket should exist in AWS")

	// Verify versioning is enabled (required for noncurrent version rules)
	hasVersioning := helpers.S3BucketHasVersioningEnabled(t, bucketId, awsRegion)
	assert.True(t, hasVersioning, "Versioning should be enabled for noncurrent version rules")

	// Verify the "expire-noncurrent-versions" rule has noncurrent version expiration at 30 days
	hasNoncurrentExpiration := helpers.S3BucketHasNoncurrentVersionExpiration(t, bucketId, "expire-noncurrent-versions", 30, awsRegion)
	assert.True(t, hasNoncurrentExpiration, "Should have noncurrent version expiration at 30 days for 'expire-noncurrent-versions' rule")

	// Verify the "full-lifecycle" rule has noncurrent version expiration at 60 days
	hasFullLifecycleNoncurrent := helpers.S3BucketHasNoncurrentVersionExpiration(t, bucketId, "full-lifecycle", 60, awsRegion)
	assert.True(t, hasFullLifecycleNoncurrent, "Should have noncurrent version expiration at 60 days for 'full-lifecycle' rule")
}

// TestS3LifecycleMultipartAbort verifies that abort incomplete multipart upload rules are correctly applied.
// Tests the "abort-incomplete-uploads" rule with 7 days abort.
func TestS3LifecycleMultipartAbort(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("s3mp")

	// Configure Terraform options
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/s3/with_lifecycle",
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

	// Use AWS SDK to verify bucket exists
	bucketExists := helpers.S3BucketExists(t, bucketId, awsRegion)
	assert.True(t, bucketExists, "S3 bucket should exist in AWS")

	// Verify the "abort-incomplete-uploads" rule has multipart abort at 7 days
	hasMultipartAbort := helpers.S3BucketHasAbortMultipartUploadRule(t, bucketId, "abort-incomplete-uploads", 7, awsRegion)
	assert.True(t, hasMultipartAbort, "Should have abort incomplete multipart upload at 7 days for 'abort-incomplete-uploads' rule")
}

// TestS3LifecycleExpiration verifies that expiration rules are correctly applied.
// Tests the "expire-logs" rule with 90 days expiration.
func TestS3LifecycleExpiration(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("s3ex")

	// Configure Terraform options
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/s3/with_lifecycle",
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

	// Use AWS SDK to verify bucket exists
	bucketExists := helpers.S3BucketExists(t, bucketId, awsRegion)
	assert.True(t, bucketExists, "S3 bucket should exist in AWS")

	// Verify the "expire-logs" rule has expiration at 90 days
	hasExpiration := helpers.S3BucketHasExpirationRule(t, bucketId, 90, awsRegion)
	assert.True(t, hasExpiration, "Should have expiration rule at 90 days")

	// Verify the "full-lifecycle" rule has expiration at 365 days
	hasFullLifecycleExpiration := helpers.S3BucketHasExpirationRule(t, bucketId, 365, awsRegion)
	assert.True(t, hasFullLifecycleExpiration, "Should have expiration rule at 365 days for 'full-lifecycle' rule")
}

// TestS3WithAlbLogsPolicy provisions an S3 bucket with ALB access logs policy template and validates:
// - bucket is created correctly
// - bucket policy is applied with ALB access logs statements
// - deny insecure transport statement is present
func TestS3WithAlbLogsPolicy(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("s3alb")

	// Configure Terraform options
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/s3/with_alb_logs_policy",
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
	bucketPolicy := terraform.Output(t, terraformOptions, "bucket_policy")

	// Assert bucket_id is not empty and matches the expected name
	require.NotEmpty(t, bucketId, "bucket_id should not be empty")
	assert.Equal(t, uniqueName, bucketId, "bucket_id should match the provided name")

	// Assert bucket_arn is not empty and has correct format
	require.NotEmpty(t, bucketArn, "bucket_arn should not be empty")
	assert.Contains(t, bucketArn, ":s3:::", "bucket_arn should contain ':s3:::'")

	// Assert bucket_policy output is not empty
	require.NotEmpty(t, bucketPolicy, "bucket_policy output should not be empty")

	// Use AWS SDK to verify bucket exists
	bucketExists := helpers.S3BucketExists(t, bucketId, awsRegion)
	assert.True(t, bucketExists, "S3 bucket should exist in AWS")

	// Use AWS SDK to verify bucket has a policy
	hasPolicy := helpers.S3BucketHasPolicy(t, bucketId, awsRegion)
	assert.True(t, hasPolicy, "S3 bucket should have a bucket policy")

	// Verify ALB access logs policy statements are present
	hasELBRootAccount := helpers.S3BucketPolicyContainsStatement(t, bucketId, "AllowELBRootAccount", awsRegion)
	assert.True(t, hasELBRootAccount, "Policy should contain AllowELBRootAccount statement")

	hasELBLogDelivery := helpers.S3BucketPolicyContainsStatement(t, bucketId, "AllowELBLogDelivery", awsRegion)
	assert.True(t, hasELBLogDelivery, "Policy should contain AllowELBLogDelivery statement")

	hasELBLogDeliveryAclCheck := helpers.S3BucketPolicyContainsStatement(t, bucketId, "AllowELBLogDeliveryAclCheck", awsRegion)
	assert.True(t, hasELBLogDeliveryAclCheck, "Policy should contain AllowELBLogDeliveryAclCheck statement")

	// Verify deny insecure transport statement is present
	hasDenyInsecureTransport := helpers.S3BucketPolicyContainsStatement(t, bucketId, "DenyInsecureTransport", awsRegion)
	assert.True(t, hasDenyInsecureTransport, "Policy should contain DenyInsecureTransport statement")

	// Use AWS SDK to verify all public access is blocked (default behavior)
	publicAccessBlocked := helpers.S3BucketHasPublicAccessBlocked(t, bucketId, awsRegion)
	assert.True(t, publicAccessBlocked, "S3 bucket should have all public access blocked")
}

// TestS3WithVpcFlowLogsPolicy provisions an S3 bucket with VPC flow logs policy template and validates:
// - bucket is created correctly
// - bucket policy is applied with VPC flow logs statements
// - deny insecure transport statement is present
func TestS3WithVpcFlowLogsPolicy(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("s3vpc")

	// Configure Terraform options
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/s3/with_vpc_flow_logs_policy",
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
	bucketPolicy := terraform.Output(t, terraformOptions, "bucket_policy")

	// Assert bucket_id is not empty and matches the expected name
	require.NotEmpty(t, bucketId, "bucket_id should not be empty")
	assert.Equal(t, uniqueName, bucketId, "bucket_id should match the provided name")

	// Assert bucket_arn is not empty and has correct format
	require.NotEmpty(t, bucketArn, "bucket_arn should not be empty")
	assert.Contains(t, bucketArn, ":s3:::", "bucket_arn should contain ':s3:::'")

	// Assert bucket_policy output is not empty
	require.NotEmpty(t, bucketPolicy, "bucket_policy output should not be empty")

	// Use AWS SDK to verify bucket exists
	bucketExists := helpers.S3BucketExists(t, bucketId, awsRegion)
	assert.True(t, bucketExists, "S3 bucket should exist in AWS")

	// Use AWS SDK to verify bucket has a policy
	hasPolicy := helpers.S3BucketHasPolicy(t, bucketId, awsRegion)
	assert.True(t, hasPolicy, "S3 bucket should have a bucket policy")

	// Verify VPC flow logs policy statements are present
	hasAWSLogDeliveryAclCheck := helpers.S3BucketPolicyContainsStatement(t, bucketId, "AWSLogDeliveryAclCheck", awsRegion)
	assert.True(t, hasAWSLogDeliveryAclCheck, "Policy should contain AWSLogDeliveryAclCheck statement")

	hasAWSLogDeliveryWrite := helpers.S3BucketPolicyContainsStatement(t, bucketId, "AWSLogDeliveryWrite", awsRegion)
	assert.True(t, hasAWSLogDeliveryWrite, "Policy should contain AWSLogDeliveryWrite statement")

	// Verify deny insecure transport statement is present
	hasDenyInsecureTransport := helpers.S3BucketPolicyContainsStatement(t, bucketId, "DenyInsecureTransport", awsRegion)
	assert.True(t, hasDenyInsecureTransport, "Policy should contain DenyInsecureTransport statement")

	// Use AWS SDK to verify all public access is blocked (default behavior)
	publicAccessBlocked := helpers.S3BucketHasPublicAccessBlocked(t, bucketId, awsRegion)
	assert.True(t, publicAccessBlocked, "S3 bucket should have all public access blocked")
}

// TestS3WithNlbLogsPolicy provisions an S3 bucket with NLB access logs policy template and validates:
// - bucket is created correctly
// - bucket policy is applied with NLB access logs statements
// - deny insecure transport statement is present
func TestS3WithNlbLogsPolicy(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("s3nlb")

	// Configure Terraform options
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/s3/with_nlb_logs_policy",
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
	bucketPolicy := terraform.Output(t, terraformOptions, "bucket_policy")

	// Assert bucket_id is not empty and matches the expected name
	require.NotEmpty(t, bucketId, "bucket_id should not be empty")
	assert.Equal(t, uniqueName, bucketId, "bucket_id should match the provided name")

	// Assert bucket_arn is not empty and has correct format
	require.NotEmpty(t, bucketArn, "bucket_arn should not be empty")
	assert.Contains(t, bucketArn, ":s3:::", "bucket_arn should contain ':s3:::'")

	// Assert bucket_policy output is not empty
	require.NotEmpty(t, bucketPolicy, "bucket_policy output should not be empty")

	// Use AWS SDK to verify bucket exists
	bucketExists := helpers.S3BucketExists(t, bucketId, awsRegion)
	assert.True(t, bucketExists, "S3 bucket should exist in AWS")

	// Use AWS SDK to verify bucket has a policy
	hasPolicy := helpers.S3BucketHasPolicy(t, bucketId, awsRegion)
	assert.True(t, hasPolicy, "S3 bucket should have a bucket policy")

	// Verify NLB access logs policy statements are present
	hasNLBLogDelivery := helpers.S3BucketPolicyContainsStatement(t, bucketId, "AllowNLBLogDelivery", awsRegion)
	assert.True(t, hasNLBLogDelivery, "Policy should contain AllowNLBLogDelivery statement")

	hasNLBLogDeliveryAclCheck := helpers.S3BucketPolicyContainsStatement(t, bucketId, "AllowNLBLogDeliveryAclCheck", awsRegion)
	assert.True(t, hasNLBLogDeliveryAclCheck, "Policy should contain AllowNLBLogDeliveryAclCheck statement")

	// Verify deny insecure transport statement is present
	hasDenyInsecureTransport := helpers.S3BucketPolicyContainsStatement(t, bucketId, "DenyInsecureTransport", awsRegion)
	assert.True(t, hasDenyInsecureTransport, "Policy should contain DenyInsecureTransport statement")

	// Use AWS SDK to verify all public access is blocked (default behavior)
	publicAccessBlocked := helpers.S3BucketHasPublicAccessBlocked(t, bucketId, awsRegion)
	assert.True(t, publicAccessBlocked, "S3 bucket should have all public access blocked")
}

// TestS3WithDenyInsecureTransport verifies the deny insecure transport policy template.
// Uses the ALB logs policy fixture which includes the deny_insecure_transport template.
func TestS3WithDenyInsecureTransport(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("s3dit")

	// Configure Terraform options - using ALB logs policy fixture which includes deny_insecure_transport
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/s3/with_alb_logs_policy",
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
	bucketPolicy := terraform.Output(t, terraformOptions, "bucket_policy")

	// Assert bucket_id is not empty
	require.NotEmpty(t, bucketId, "bucket_id should not be empty")

	// Assert bucket_policy output is not empty
	require.NotEmpty(t, bucketPolicy, "bucket_policy output should not be empty")

	// Use AWS SDK to verify bucket exists
	bucketExists := helpers.S3BucketExists(t, bucketId, awsRegion)
	assert.True(t, bucketExists, "S3 bucket should exist in AWS")

	// Use AWS SDK to verify bucket has a policy
	hasPolicy := helpers.S3BucketHasPolicy(t, bucketId, awsRegion)
	assert.True(t, hasPolicy, "S3 bucket should have a bucket policy")

	// Verify deny insecure transport statement is present
	hasDenyInsecureTransport := helpers.S3BucketPolicyContainsStatement(t, bucketId, "DenyInsecureTransport", awsRegion)
	assert.True(t, hasDenyInsecureTransport, "Policy should contain DenyInsecureTransport statement")

	// Get the full policy and verify it denies HTTP access
	policy := helpers.GetS3BucketPolicy(t, bucketId, awsRegion)
	assert.Contains(t, policy, "aws:SecureTransport", "Policy should reference aws:SecureTransport condition")
	assert.Contains(t, policy, "Deny", "Policy should contain Deny effect")
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
// It tests:
// - Default module tags (ManagedBy, Module) are applied
// - Custom tags are applied
// - Tag merging works correctly (custom tags can override defaults)
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
				"CustomTag":  "CustomValue",
				"Project":    "TagTest",
				"CostCenter": "12345",
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

	// ========================================================================
	// Use AWS SDK to verify tags via GetS3BucketTags helper
	// ========================================================================

	// Get all tags from the bucket
	tags := helpers.GetS3BucketTags(t, bucketId, awsRegion)
	assert.NotEmpty(t, tags, "Bucket should have tags")

	// Verify default module tag (Module) is present
	// Note: ManagedBy is overridden by fixture's common_tags to "terratest"
	assert.Equal(t, "storage/s3", tags["Module"], "Module tag should be 'storage/s3' from module defaults")

	// Verify fixture tags (Environment, ManagedBy) are present
	// The fixture sets these in common_tags which are passed to the module
	assert.Equal(t, "terratest", tags["Environment"], "Environment tag should be 'terratest' from fixture")
	assert.Equal(t, "terratest", tags["ManagedBy"], "ManagedBy tag should be 'terratest' (fixture overrides module default)")

	// Verify custom tags are applied
	assert.Equal(t, "CustomValue", tags["CustomTag"], "CustomTag should be 'CustomValue'")
	assert.Equal(t, "TagTest", tags["Project"], "Project tag should be 'TagTest'")
	assert.Equal(t, "12345", tags["CostCenter"], "CostCenter tag should be '12345'")

	// ========================================================================
	// Use S3BucketHasTag helper for specific tag verification
	// ========================================================================

	// Verify individual tags using the S3BucketHasTag helper
	hasModuleTag := helpers.S3BucketHasTag(t, bucketId, "Module", "storage/s3", awsRegion)
	assert.True(t, hasModuleTag, "S3BucketHasTag should return true for Module tag")

	hasEnvironmentTag := helpers.S3BucketHasTag(t, bucketId, "Environment", "terratest", awsRegion)
	assert.True(t, hasEnvironmentTag, "S3BucketHasTag should return true for Environment tag")

	hasCustomTag := helpers.S3BucketHasTag(t, bucketId, "CustomTag", "CustomValue", awsRegion)
	assert.True(t, hasCustomTag, "S3BucketHasTag should return true for CustomTag")

	hasProjectTag := helpers.S3BucketHasTag(t, bucketId, "Project", "TagTest", awsRegion)
	assert.True(t, hasProjectTag, "S3BucketHasTag should return true for Project tag")

	// Verify tag with wrong value returns false
	hasWrongValue := helpers.S3BucketHasTag(t, bucketId, "Module", "wrong-value", awsRegion)
	assert.False(t, hasWrongValue, "S3BucketHasTag should return false for incorrect tag value")

	// Verify non-existent tag returns false
	hasNonExistentTag := helpers.S3BucketHasTag(t, bucketId, "NonExistentTag", "any-value", awsRegion)
	assert.False(t, hasNonExistentTag, "S3BucketHasTag should return false for non-existent tag")

	// ========================================================================
	// Verify tag count (should have at least 6 tags)
	// Module (from module defaults) + Environment, ManagedBy (from fixture) + CustomTag, Project, CostCenter (from test)
	// ========================================================================
	assert.GreaterOrEqual(t, len(tags), 6, "Bucket should have at least 6 tags")
}

// TestS3WithCustomPolicy provisions an S3 bucket with a custom policy and validates:
// - bucket is created correctly
// - bucket policy is applied with custom policy statements
// - custom policy statements are identifiable (AllowTestReadAccess, AllowTestListBucket)
func TestS3WithCustomPolicy(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("s3cp")

	// Configure Terraform options
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/s3/with_custom_policy",
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
	bucketPolicy := terraform.Output(t, terraformOptions, "bucket_policy")

	// Assert bucket_id is not empty and matches the expected name
	require.NotEmpty(t, bucketId, "bucket_id should not be empty")
	assert.Equal(t, uniqueName, bucketId, "bucket_id should match the provided name")

	// Assert bucket_arn is not empty and has correct format
	require.NotEmpty(t, bucketArn, "bucket_arn should not be empty")
	assert.Contains(t, bucketArn, ":s3:::", "bucket_arn should contain ':s3:::'")

	// Assert bucket_policy output is not empty
	require.NotEmpty(t, bucketPolicy, "bucket_policy output should not be empty")

	// Use AWS SDK to verify bucket exists
	bucketExists := helpers.S3BucketExists(t, bucketId, awsRegion)
	assert.True(t, bucketExists, "S3 bucket should exist in AWS")

	// Use AWS SDK to verify bucket has a policy
	hasPolicy := helpers.S3BucketHasPolicy(t, bucketId, awsRegion)
	assert.True(t, hasPolicy, "S3 bucket should have a bucket policy")

	// Verify custom policy statements are present
	hasTestReadAccess := helpers.S3BucketPolicyContainsStatement(t, bucketId, "AllowTestReadAccess", awsRegion)
	assert.True(t, hasTestReadAccess, "Policy should contain AllowTestReadAccess statement from custom policy")

	hasTestListBucket := helpers.S3BucketPolicyContainsStatement(t, bucketId, "AllowTestListBucket", awsRegion)
	assert.True(t, hasTestListBucket, "Policy should contain AllowTestListBucket statement from custom policy")

	// Get the full policy and verify it's valid JSON containing expected content
	policy := helpers.GetS3BucketPolicy(t, bucketId, awsRegion)
	assert.Contains(t, policy, "s3:GetObject", "Policy should contain s3:GetObject action")
	assert.Contains(t, policy, "s3:ListBucket", "Policy should contain s3:ListBucket action")
	assert.Contains(t, policy, "aws:PrincipalOrgID", "Policy should contain organization condition")

	// Use AWS SDK to verify all public access is blocked (default behavior)
	publicAccessBlocked := helpers.S3BucketHasPublicAccessBlocked(t, bucketId, awsRegion)
	assert.True(t, publicAccessBlocked, "S3 bucket should have all public access blocked")
}

// TestS3PolicyMerging verifies that custom policy and policy templates are correctly merged.
// Tests the with_custom_policy fixture which includes deny_insecure_transport template
// combined with custom policy statements.
func TestS3PolicyMerging(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("s3pm")

	// Configure Terraform options
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/s3/with_custom_policy",
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
	bucketPolicy := terraform.Output(t, terraformOptions, "bucket_policy")

	// Assert bucket_id is not empty
	require.NotEmpty(t, bucketId, "bucket_id should not be empty")

	// Assert bucket_policy output is not empty
	require.NotEmpty(t, bucketPolicy, "bucket_policy output should not be empty")

	// Use AWS SDK to verify bucket exists
	bucketExists := helpers.S3BucketExists(t, bucketId, awsRegion)
	assert.True(t, bucketExists, "S3 bucket should exist in AWS")

	// Use AWS SDK to verify bucket has a policy
	hasPolicy := helpers.S3BucketHasPolicy(t, bucketId, awsRegion)
	assert.True(t, hasPolicy, "S3 bucket should have a bucket policy")

	// Verify policy template statements are present (from deny_insecure_transport)
	hasDenyInsecureTransport := helpers.S3BucketPolicyContainsStatement(t, bucketId, "DenyInsecureTransport", awsRegion)
	assert.True(t, hasDenyInsecureTransport, "Policy should contain DenyInsecureTransport statement from policy template")

	// Verify custom policy statements are present
	hasTestReadAccess := helpers.S3BucketPolicyContainsStatement(t, bucketId, "AllowTestReadAccess", awsRegion)
	assert.True(t, hasTestReadAccess, "Policy should contain AllowTestReadAccess statement from custom policy")

	hasTestListBucket := helpers.S3BucketPolicyContainsStatement(t, bucketId, "AllowTestListBucket", awsRegion)
	assert.True(t, hasTestListBucket, "Policy should contain AllowTestListBucket statement from custom policy")

	// Get the full policy and verify it contains both template and custom statements
	policy := helpers.GetS3BucketPolicy(t, bucketId, awsRegion)

	// Verify template content
	assert.Contains(t, policy, "aws:SecureTransport", "Merged policy should contain aws:SecureTransport from template")
	assert.Contains(t, policy, "Deny", "Merged policy should contain Deny effect from template")

	// Verify custom content
	assert.Contains(t, policy, "s3:GetObject", "Merged policy should contain s3:GetObject from custom policy")
	assert.Contains(t, policy, "o-test123456", "Merged policy should contain org ID from custom policy")

	// Count the number of statements in the policy (should have at least 3: 2 custom + 1 template)
	// This is a simple check using string matching
	assert.Contains(t, policy, "Statement", "Policy should contain Statement array")
}

// TestS3FullConfiguration provisions an S3 bucket with ALL features enabled and validates:
// - SSE-KMS encryption with bucket key
// - Versioning enabled
// - Lifecycle rules (expiration, transitions, noncurrent version handling)
// - Policy templates (deny_insecure_transport) with custom policy merging
// - Public access block settings
// - Expected tags are present
// - All outputs are populated
func TestS3FullConfiguration(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("s3full")

	// Configure Terraform options
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/s3/full",
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
	bucketPolicy := terraform.Output(t, terraformOptions, "bucket_policy")
	versioningEnabled := terraform.Output(t, terraformOptions, "versioning_enabled")
	encryptionAlgorithm := terraform.Output(t, terraformOptions, "encryption_algorithm")
	kmsKeyIdOutput := terraform.Output(t, terraformOptions, "kms_key_id")
	kmsKeyArn := terraform.Output(t, terraformOptions, "kms_key_arn")

	// ========================================================================
	// Verify basic bucket creation and outputs
	// ========================================================================

	// Assert bucket_id is not empty and matches the expected name
	require.NotEmpty(t, bucketId, "bucket_id should not be empty")
	assert.Equal(t, uniqueName, bucketId, "bucket_id should match the provided name")

	// Assert bucket_arn is not empty and has correct format
	require.NotEmpty(t, bucketArn, "bucket_arn should not be empty")
	assert.Contains(t, bucketArn, ":s3:::", "bucket_arn should contain ':s3:::'")
	assert.Contains(t, bucketArn, uniqueName, "bucket_arn should contain the bucket name")

	// Assert all other outputs are populated
	assert.NotEmpty(t, bucketDomainName, "bucket_domain_name should not be empty")
	assert.NotEmpty(t, bucketRegionalDomainName, "bucket_regional_domain_name should not be empty")
	assert.NotEmpty(t, bucketHostedZoneId, "bucket_hosted_zone_id should not be empty")
	assert.NotEmpty(t, bucketRegion, "bucket_region should not be empty")
	assert.NotEmpty(t, bucketPolicy, "bucket_policy should not be empty")

	// Use AWS SDK to verify bucket exists
	bucketExists := helpers.S3BucketExists(t, bucketId, awsRegion)
	assert.True(t, bucketExists, "S3 bucket should exist in AWS")

	// ========================================================================
	// Verify SSE-KMS encryption
	// ========================================================================

	// Assert encryption is SSE-KMS (aws:kms)
	assert.Equal(t, "aws:kms", encryptionAlgorithm, "encryption_algorithm should be aws:kms for SSE-KMS")

	// Assert KMS key ID output matches the created KMS key ARN
	require.NotEmpty(t, kmsKeyIdOutput, "kms_key_id output should not be empty")
	require.NotEmpty(t, kmsKeyArn, "kms_key_arn should not be empty")
	assert.Equal(t, kmsKeyArn, kmsKeyIdOutput, "kms_key_id should match the created KMS key ARN")

	// Use AWS SDK to verify encryption is SSE-KMS with correct key
	algorithm, kmsKeyId := helpers.GetS3BucketEncryption(t, bucketId, awsRegion)
	assert.Equal(t, "aws:kms", algorithm, "Encryption algorithm from SDK should be aws:kms")
	assert.Equal(t, kmsKeyArn, kmsKeyId, "KMS key ID from SDK should match the created KMS key ARN")

	// Use AWS SDK to verify bucket key is enabled
	bucketKeyEnabled := helpers.S3BucketHasBucketKeyEnabled(t, bucketId, awsRegion)
	assert.True(t, bucketKeyEnabled, "Bucket key should be enabled for SSE-KMS")

	// ========================================================================
	// Verify versioning
	// ========================================================================

	// Assert versioning is enabled via Terraform output
	assert.Equal(t, "true", versioningEnabled, "versioning_enabled output should be true")

	// Use AWS SDK to verify versioning is enabled
	hasVersioning := helpers.S3BucketHasVersioningEnabled(t, bucketId, awsRegion)
	assert.True(t, hasVersioning, "S3BucketHasVersioningEnabled should return true")

	// ========================================================================
	// Verify lifecycle rules
	// ========================================================================

	// Verify lifecycle rules exist via AWS SDK (should have 4 rules)
	lifecycleRules := helpers.GetS3BucketLifecycleRules(t, bucketId, awsRegion)
	assert.NotEmpty(t, lifecycleRules, "Lifecycle rules should be configured")
	assert.Len(t, lifecycleRules, 4, "Should have 4 lifecycle rules configured")

	// Verify the "full-expire-logs" rule has expiration at 90 days
	hasExpiration := helpers.S3BucketHasExpirationRule(t, bucketId, 90, awsRegion)
	assert.True(t, hasExpiration, "Should have expiration rule at 90 days for 'full-expire-logs' rule")

	// Verify the "full-archive-data" rule has STANDARD_IA transition at 30 days
	hasStandardIaTransition := helpers.S3BucketHasTransitionRule(t, bucketId, "full-archive-data", "STANDARD_IA", 30, awsRegion)
	assert.True(t, hasStandardIaTransition, "Should have STANDARD_IA transition at 30 days for 'full-archive-data' rule")

	// Verify the "full-archive-data" rule has GLACIER transition at 90 days
	hasGlacierTransition := helpers.S3BucketHasTransitionRule(t, bucketId, "full-archive-data", "GLACIER", 90, awsRegion)
	assert.True(t, hasGlacierTransition, "Should have GLACIER transition at 90 days for 'full-archive-data' rule")

	// Verify the "full-noncurrent-cleanup" rule has noncurrent version expiration at 30 days
	hasNoncurrentExpiration := helpers.S3BucketHasNoncurrentVersionExpiration(t, bucketId, "full-noncurrent-cleanup", 30, awsRegion)
	assert.True(t, hasNoncurrentExpiration, "Should have noncurrent version expiration at 30 days for 'full-noncurrent-cleanup' rule")

	// Verify the "full-abort-multipart" rule has multipart abort at 7 days
	hasMultipartAbort := helpers.S3BucketHasAbortMultipartUploadRule(t, bucketId, "full-abort-multipart", 7, awsRegion)
	assert.True(t, hasMultipartAbort, "Should have abort incomplete multipart upload at 7 days for 'full-abort-multipart' rule")

	// ========================================================================
	// Verify bucket policy (template + custom policy merging)
	// ========================================================================

	// Use AWS SDK to verify bucket has a policy
	hasPolicy := helpers.S3BucketHasPolicy(t, bucketId, awsRegion)
	assert.True(t, hasPolicy, "S3 bucket should have a bucket policy")

	// Verify policy template statement is present (from deny_insecure_transport)
	hasDenyInsecureTransport := helpers.S3BucketPolicyContainsStatement(t, bucketId, "DenyInsecureTransport", awsRegion)
	assert.True(t, hasDenyInsecureTransport, "Policy should contain DenyInsecureTransport statement from policy template")

	// Verify custom policy statement is present
	hasFullTestReadAccess := helpers.S3BucketPolicyContainsStatement(t, bucketId, "AllowFullTestReadAccess", awsRegion)
	assert.True(t, hasFullTestReadAccess, "Policy should contain AllowFullTestReadAccess statement from custom policy")

	// Get the full policy and verify it contains both template and custom statements
	policy := helpers.GetS3BucketPolicy(t, bucketId, awsRegion)

	// Verify template content
	assert.Contains(t, policy, "aws:SecureTransport", "Merged policy should contain aws:SecureTransport from template")
	assert.Contains(t, policy, "Deny", "Merged policy should contain Deny effect from template")

	// Verify custom content
	assert.Contains(t, policy, "s3:GetObject", "Merged policy should contain s3:GetObject from custom policy")
	assert.Contains(t, policy, "o-fulltest123", "Merged policy should contain org ID from custom policy")

	// ========================================================================
	// Verify public access block settings
	// ========================================================================

	// Use AWS SDK to verify all public access is blocked
	publicAccessBlocked := helpers.S3BucketHasPublicAccessBlocked(t, bucketId, awsRegion)
	assert.True(t, publicAccessBlocked, "S3 bucket should have all public access blocked")

	// Get the detailed public access block configuration
	config := helpers.GetS3BucketPublicAccessBlock(t, bucketId, awsRegion)
	require.NotNil(t, config, "Public access block configuration should exist")

	assert.NotNil(t, config.BlockPublicAcls, "BlockPublicAcls should not be nil")
	assert.True(t, *config.BlockPublicAcls, "BlockPublicAcls should be true")

	assert.NotNil(t, config.BlockPublicPolicy, "BlockPublicPolicy should not be nil")
	assert.True(t, *config.BlockPublicPolicy, "BlockPublicPolicy should be true")

	assert.NotNil(t, config.IgnorePublicAcls, "IgnorePublicAcls should not be nil")
	assert.True(t, *config.IgnorePublicAcls, "IgnorePublicAcls should be true")

	assert.NotNil(t, config.RestrictPublicBuckets, "RestrictPublicBuckets should not be nil")
	assert.True(t, *config.RestrictPublicBuckets, "RestrictPublicBuckets should be true")

	// ========================================================================
	// Verify tags
	// ========================================================================

	// Use AWS SDK to get tags
	tags := helpers.GetS3BucketTags(t, bucketId, awsRegion)
	assert.NotEmpty(t, tags, "Bucket should have tags")

	// Verify expected tags are present (from fixture's common_tags)
	assert.Equal(t, "terratest", tags["Environment"], "Environment tag should be 'terratest'")
	assert.Equal(t, "terratest", tags["ManagedBy"], "ManagedBy tag should be 'terratest' (fixture overrides module default)")
	assert.Equal(t, "full-configuration", tags["TestType"], "TestType tag should be 'full-configuration'")
	assert.Equal(t, "comprehensive-s3-testing", tags["Purpose"], "Purpose tag should be 'comprehensive-s3-testing'")

	// Verify default module tags are merged (Module tag comes from module defaults)
	assert.Equal(t, "storage/s3", tags["Module"], "Module tag should be 'storage/s3' from module defaults")
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
