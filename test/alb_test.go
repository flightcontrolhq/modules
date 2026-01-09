// Package test contains Terratest integration tests for the Terraform modules.
package test

import (
	"testing"

	"github.com/flightcontrolhq/modules/test/helpers"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestAlbBasic provisions the basic ALB fixture and validates the outputs.
// It verifies:
// - alb_dns_name is not empty
// - ALB is in 'active' state using AWS SDK
// - Security group exists with correct inbound rules (port 80 for HTTP)
func TestAlbBasic(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("alb")

	// Configure Terraform options
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/alb/basic",
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
	albArn := terraform.Output(t, terraformOptions, "alb_arn")
	albDnsName := terraform.Output(t, terraformOptions, "alb_dns_name")
	securityGroupId := terraform.Output(t, terraformOptions, "security_group_id")
	httpListenerArn := terraform.Output(t, terraformOptions, "http_listener_arn")

	// Assert alb_dns_name is not empty
	require.NotEmpty(t, albDnsName, "alb_dns_name should not be empty")

	// Assert alb_arn is not empty
	require.NotEmpty(t, albArn, "alb_arn should not be empty")

	// Assert http_listener_arn is not empty
	assert.NotEmpty(t, httpListenerArn, "http_listener_arn should not be empty")

	// Assert security_group_id is not empty
	require.NotEmpty(t, securityGroupId, "security_group_id should not be empty")

	// Use AWS SDK to verify ALB exists
	albExists := helpers.LoadBalancerExists(t, albArn, awsRegion)
	assert.True(t, albExists, "ALB should exist in AWS")

	// Use AWS SDK to verify ALB is in 'active' state
	albState := helpers.GetLoadBalancerState(t, albArn, awsRegion)
	assert.Equal(t, "active", string(albState), "ALB should be in 'active' state")

	// Use AWS SDK to verify security group exists
	sgExists := helpers.SecurityGroupExists(t, securityGroupId, awsRegion)
	assert.True(t, sgExists, "Security group should exist in AWS")

	// Use AWS SDK to verify security group has HTTP inbound rule (port 80)
	hasHttpRule := helpers.SecurityGroupHasIngressRule(t, securityGroupId, 80, awsRegion)
	assert.True(t, hasHttpRule, "Security group should have inbound rule for HTTP (port 80)")
}

// TestAlbWithHttps provisions the ALB fixture with HTTPS enabled and validates:
// - HTTPS listener exists on port 443
// - HTTP to HTTPS redirect is configured
// - Security group has HTTPS inbound rule (port 443)
func TestAlbWithHttps(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("alb-https")

	// Configure Terraform options
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/alb/with_https",
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
	albArn := terraform.Output(t, terraformOptions, "alb_arn")
	albDnsName := terraform.Output(t, terraformOptions, "alb_dns_name")
	securityGroupId := terraform.Output(t, terraformOptions, "security_group_id")
	httpListenerArn := terraform.Output(t, terraformOptions, "http_listener_arn")
	httpsListenerArn := terraform.Output(t, terraformOptions, "https_listener_arn")

	// Assert basic outputs are not empty
	require.NotEmpty(t, albArn, "alb_arn should not be empty")
	require.NotEmpty(t, albDnsName, "alb_dns_name should not be empty")
	require.NotEmpty(t, securityGroupId, "security_group_id should not be empty")
	require.NotEmpty(t, httpListenerArn, "http_listener_arn should not be empty")
	require.NotEmpty(t, httpsListenerArn, "https_listener_arn should not be empty")

	// Use AWS SDK to verify ALB exists and is active
	albExists := helpers.LoadBalancerExists(t, albArn, awsRegion)
	assert.True(t, albExists, "ALB should exist in AWS")

	albState := helpers.GetLoadBalancerState(t, albArn, awsRegion)
	assert.Equal(t, "active", string(albState), "ALB should be in 'active' state")

	// Verify HTTPS listener exists and is on port 443
	httpsListenerExists := helpers.ListenerExists(t, httpsListenerArn, awsRegion)
	assert.True(t, httpsListenerExists, "HTTPS listener should exist in AWS")

	httpsProtocol := helpers.GetListenerProtocol(t, httpsListenerArn, awsRegion)
	assert.Equal(t, "HTTPS", string(httpsProtocol), "HTTPS listener should have HTTPS protocol")

	httpsPort := helpers.GetListenerPort(t, httpsListenerArn, awsRegion)
	assert.Equal(t, int32(443), httpsPort, "HTTPS listener should be on port 443")

	// Verify HTTP listener has redirect action to HTTPS
	hasRedirect, statusCode, targetPort := helpers.ListenerHasRedirectAction(t, httpListenerArn, awsRegion)
	assert.True(t, hasRedirect, "HTTP listener should have redirect action")
	assert.Equal(t, "HTTP_301", statusCode, "HTTP redirect should use 301 status code")
	assert.Equal(t, "443", targetPort, "HTTP redirect should target port 443")

	// Verify security group has HTTPS inbound rule (port 443)
	hasHttpsRule := helpers.SecurityGroupHasIngressRule(t, securityGroupId, 443, awsRegion)
	assert.True(t, hasHttpsRule, "Security group should have inbound rule for HTTPS (port 443)")
}

// TestAlbWithAccessLogs provisions the ALB fixture with access logs enabled and validates:
// - S3 bucket for logs is created
// - S3 bucket has encryption enabled
// - S3 bucket has public access blocked
// - S3 bucket has lifecycle rule with correct retention days
// - ALB attribute access_logs.s3.enabled is true
func TestAlbWithAccessLogs(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("alb-logs")

	// Configure Terraform options
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/alb/with_access_logs",
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
	albArn := terraform.Output(t, terraformOptions, "alb_arn")
	albDnsName := terraform.Output(t, terraformOptions, "alb_dns_name")
	securityGroupId := terraform.Output(t, terraformOptions, "security_group_id")
	accessLogsBucketName := terraform.Output(t, terraformOptions, "access_logs_bucket_name")
	accessLogsBucketArn := terraform.Output(t, terraformOptions, "access_logs_bucket_arn")

	// Assert basic outputs are not empty
	require.NotEmpty(t, albArn, "alb_arn should not be empty")
	require.NotEmpty(t, albDnsName, "alb_dns_name should not be empty")
	require.NotEmpty(t, securityGroupId, "security_group_id should not be empty")
	require.NotEmpty(t, accessLogsBucketName, "access_logs_bucket_name should not be empty")
	require.NotEmpty(t, accessLogsBucketArn, "access_logs_bucket_arn should not be empty")

	// Use AWS SDK to verify ALB exists and is active
	albExists := helpers.LoadBalancerExists(t, albArn, awsRegion)
	assert.True(t, albExists, "ALB should exist in AWS")

	albState := helpers.GetLoadBalancerState(t, albArn, awsRegion)
	assert.Equal(t, "active", string(albState), "ALB should be in 'active' state")

	// Verify S3 bucket for logs was created
	bucketExists := helpers.S3BucketExists(t, accessLogsBucketName, awsRegion)
	assert.True(t, bucketExists, "S3 bucket for access logs should exist")

	// Verify S3 bucket has server-side encryption enabled
	hasEncryption := helpers.S3BucketHasSSEEncryption(t, accessLogsBucketName, awsRegion)
	assert.True(t, hasEncryption, "S3 bucket should have server-side encryption enabled")

	// Verify S3 bucket has public access blocked
	hasPublicAccessBlocked := helpers.S3BucketHasPublicAccessBlocked(t, accessLogsBucketName, awsRegion)
	assert.True(t, hasPublicAccessBlocked, "S3 bucket should have all public access blocked")

	// Verify S3 bucket has lifecycle rule with correct retention days (30 days as configured in fixture)
	hasExpirationRule := helpers.S3BucketHasExpirationRule(t, accessLogsBucketName, 30, awsRegion)
	assert.True(t, hasExpirationRule, "S3 bucket should have lifecycle rule with 30 day expiration")

	// Verify ALB has access logs enabled
	accessLogsEnabled := helpers.GetLoadBalancerAccessLogsEnabled(t, albArn, awsRegion)
	assert.True(t, accessLogsEnabled, "ALB access_logs.s3.enabled attribute should be true")

	// Verify ALB access logs bucket matches
	actualBucket := helpers.GetLoadBalancerAccessLogsBucket(t, albArn, awsRegion)
	assert.Equal(t, accessLogsBucketName, actualBucket, "ALB access logs bucket should match Terraform output")

	// Verify ALB access logs prefix matches (configured as "alb-logs" in fixture)
	actualPrefix := helpers.GetLoadBalancerAccessLogsPrefix(t, albArn, awsRegion)
	assert.Equal(t, "alb-logs", actualPrefix, "ALB access logs prefix should be 'alb-logs'")
}

// TestAlbWithWaf provisions the ALB fixture with WAF WebACL and validates:
// - WAF WebACL is created and associated with ALB
// - WebACL contains AWS managed rule groups (AWSManagedRulesCommonRuleSet)
// - ALB is in 'active' state
func TestAlbWithWaf(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("alb-waf")

	// Configure Terraform options
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/alb/with_waf",
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
	albArn := terraform.Output(t, terraformOptions, "alb_arn")
	albDnsName := terraform.Output(t, terraformOptions, "alb_dns_name")
	securityGroupId := terraform.Output(t, terraformOptions, "security_group_id")
	webAclArn := terraform.Output(t, terraformOptions, "web_acl_arn")
	webAclName := terraform.Output(t, terraformOptions, "web_acl_name")

	// Assert basic outputs are not empty
	require.NotEmpty(t, albArn, "alb_arn should not be empty")
	require.NotEmpty(t, albDnsName, "alb_dns_name should not be empty")
	require.NotEmpty(t, securityGroupId, "security_group_id should not be empty")
	require.NotEmpty(t, webAclArn, "web_acl_arn should not be empty")
	require.NotEmpty(t, webAclName, "web_acl_name should not be empty")

	// Use AWS SDK to verify ALB exists and is active
	albExists := helpers.LoadBalancerExists(t, albArn, awsRegion)
	assert.True(t, albExists, "ALB should exist in AWS")

	albState := helpers.GetLoadBalancerState(t, albArn, awsRegion)
	assert.Equal(t, "active", string(albState), "ALB should be in 'active' state")

	// Verify WAF WebACL exists
	webAclExists := helpers.WafWebAclExists(t, webAclArn, awsRegion)
	assert.True(t, webAclExists, "WAF WebACL should exist in AWS")

	// Verify WebACL name matches
	actualWebAclName := helpers.GetWafWebAclName(t, webAclArn, awsRegion)
	assert.Equal(t, webAclName, actualWebAclName, "WebACL name should match Terraform output")

	// Verify WebACL has rules (at least 2 managed rule groups)
	ruleCount := helpers.GetWafWebAclRuleCount(t, webAclArn, awsRegion)
	assert.GreaterOrEqual(t, ruleCount, 2, "WebACL should have at least 2 rules (managed rule groups)")

	// Verify WebACL contains AWSManagedRulesCommonRuleSet
	hasCommonRuleSet := helpers.WafWebAclHasManagedRuleGroup(t, webAclArn, "AWSManagedRulesCommonRuleSet", awsRegion)
	assert.True(t, hasCommonRuleSet, "WebACL should contain AWSManagedRulesCommonRuleSet managed rule group")

	// Verify WebACL contains AWSManagedRulesKnownBadInputsRuleSet
	hasBadInputsRuleSet := helpers.WafWebAclHasManagedRuleGroup(t, webAclArn, "AWSManagedRulesKnownBadInputsRuleSet", awsRegion)
	assert.True(t, hasBadInputsRuleSet, "WebACL should contain AWSManagedRulesKnownBadInputsRuleSet managed rule group")

	// Verify WebACL is associated with the ALB
	isAssociated := helpers.WafWebAclIsAssociatedWithResource(t, webAclArn, albArn, awsRegion)
	assert.True(t, isAssociated, "WAF WebACL should be associated with the ALB")

	// Also verify by getting the WebACL for the resource
	associatedWebAclArn := helpers.GetWafWebAclForResource(t, albArn, awsRegion)
	assert.Equal(t, webAclArn, associatedWebAclArn, "WebACL ARN from resource should match expected ARN")
}
