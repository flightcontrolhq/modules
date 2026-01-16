// Package test contains Terratest integration tests for the Terraform modules.
package test

import (
	"testing"

	"github.com/flightcontrolhq/modules/test/helpers"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestAutoscalingBasic provisions the basic Auto Scaling Group fixture.
// It verifies:
// - autoscaling_group_arn is not empty
// - autoscaling_group_name is not empty
// - launch_template_id is not empty
// - Auto Scaling Group exists in AWS
// - Launch template exists in AWS
// - ASG has correct min/max size configuration
// - ASG has a launch template configured
func TestAutoscalingBasic(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("asg")

	// Configure Terraform options
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/autoscaling/basic",
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
	asgArn := terraform.Output(t, terraformOptions, "autoscaling_group_arn")
	asgName := terraform.Output(t, terraformOptions, "autoscaling_group_name")
	launchTemplateId := terraform.Output(t, terraformOptions, "launch_template_id")
	minSize := terraform.Output(t, terraformOptions, "autoscaling_group_min_size")
	maxSize := terraform.Output(t, terraformOptions, "autoscaling_group_max_size")

	// Assert outputs are not empty
	require.NotEmpty(t, asgArn, "autoscaling_group_arn should not be empty")
	require.NotEmpty(t, asgName, "autoscaling_group_name should not be empty")
	require.NotEmpty(t, launchTemplateId, "launch_template_id should not be empty")

	// Verify min/max size from output
	assert.Equal(t, "0", minSize, "min_size should be 0")
	assert.Equal(t, "2", maxSize, "max_size should be 2")

	// Use AWS SDK to verify Auto Scaling Group exists
	asgExists := helpers.AutoScalingGroupExists(t, asgName, awsRegion)
	assert.True(t, asgExists, "Auto Scaling Group should exist in AWS")

	// Use AWS SDK to verify launch template exists
	ltExists := helpers.LaunchTemplateExists(t, launchTemplateId, awsRegion)
	assert.True(t, ltExists, "Launch template should exist in AWS")

	// Verify ASG has a launch template configured
	hasLaunchTemplate := helpers.AutoScalingGroupHasLaunchTemplate(t, asgName, awsRegion)
	assert.True(t, hasLaunchTemplate, "Auto Scaling Group should have a launch template configured")

	// Verify min/max size via AWS SDK
	actualMinSize := helpers.GetAutoScalingGroupMinSize(t, asgName, awsRegion)
	assert.Equal(t, int32(0), actualMinSize, "Auto Scaling Group min_size should be 0")

	actualMaxSize := helpers.GetAutoScalingGroupMaxSize(t, asgName, awsRegion)
	assert.Equal(t, int32(2), actualMaxSize, "Auto Scaling Group max_size should be 2")

	// Verify health check type
	healthCheckType := helpers.GetAutoScalingGroupHealthCheckType(t, asgName, awsRegion)
	assert.Equal(t, "EC2", healthCheckType, "Auto Scaling Group health_check_type should be EC2")
}

// TestAutoscalingWithSpot provisions the Auto Scaling Group fixture with mixed instances policy.
// It verifies:
// - Auto Scaling Group has mixed instances policy configured
// - Launch template exists and is associated
// - ASG exists in AWS with correct configuration
func TestAutoscalingWithSpot(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("asgspot")

	// Configure Terraform options
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/autoscaling/with_spot",
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
	asgArn := terraform.Output(t, terraformOptions, "autoscaling_group_arn")
	asgName := terraform.Output(t, terraformOptions, "autoscaling_group_name")
	launchTemplateId := terraform.Output(t, terraformOptions, "launch_template_id")
	maxSize := terraform.Output(t, terraformOptions, "autoscaling_group_max_size")

	// Assert outputs are not empty
	require.NotEmpty(t, asgArn, "autoscaling_group_arn should not be empty")
	require.NotEmpty(t, asgName, "autoscaling_group_name should not be empty")
	require.NotEmpty(t, launchTemplateId, "launch_template_id should not be empty")

	// Verify max size from output
	assert.Equal(t, "10", maxSize, "max_size should be 10")

	// Use AWS SDK to verify Auto Scaling Group exists
	asgExists := helpers.AutoScalingGroupExists(t, asgName, awsRegion)
	assert.True(t, asgExists, "Auto Scaling Group should exist in AWS")

	// Verify ASG has mixed instances policy
	hasMixedInstancesPolicy := helpers.AutoScalingGroupHasMixedInstancesPolicy(t, asgName, awsRegion)
	assert.True(t, hasMixedInstancesPolicy, "Auto Scaling Group should have mixed instances policy configured")

	// Verify launch template is still associated (via mixed instances policy)
	hasLaunchTemplate := helpers.AutoScalingGroupHasLaunchTemplate(t, asgName, awsRegion)
	assert.True(t, hasLaunchTemplate, "Auto Scaling Group should have a launch template configured via mixed instances policy")

	// Verify launch template ID matches
	actualLtId := helpers.GetAutoScalingGroupLaunchTemplateId(t, asgName, awsRegion)
	assert.Equal(t, launchTemplateId, actualLtId, "Launch template ID should match")
}

// TestAutoscalingWithWarmPool provisions the Auto Scaling Group fixture with warm pool.
// It verifies:
// - Auto Scaling Group has warm pool configured
// - Warm pool state is 'Stopped'
// - ASG exists in AWS with correct configuration
func TestAutoscalingWithWarmPool(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("asgwp")

	// Configure Terraform options
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/autoscaling/with_warm_pool",
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
	asgArn := terraform.Output(t, terraformOptions, "autoscaling_group_arn")
	asgName := terraform.Output(t, terraformOptions, "autoscaling_group_name")
	warmPoolState := terraform.Output(t, terraformOptions, "warm_pool_state")

	// Assert outputs are not empty
	require.NotEmpty(t, asgArn, "autoscaling_group_arn should not be empty")
	require.NotEmpty(t, asgName, "autoscaling_group_name should not be empty")
	require.NotEmpty(t, warmPoolState, "warm_pool_state should not be empty")

	// Verify warm pool state from output
	assert.Equal(t, "Stopped", warmPoolState, "warm_pool_state should be 'Stopped'")

	// Use AWS SDK to verify Auto Scaling Group exists
	asgExists := helpers.AutoScalingGroupExists(t, asgName, awsRegion)
	assert.True(t, asgExists, "Auto Scaling Group should exist in AWS")

	// Verify ASG has warm pool configured
	hasWarmPool := helpers.AutoScalingGroupHasWarmPool(t, asgName, awsRegion)
	assert.True(t, hasWarmPool, "Auto Scaling Group should have warm pool configured")

	// Verify warm pool state via AWS SDK
	actualWarmPoolState := helpers.GetAutoScalingGroupWarmPoolState(t, asgName, awsRegion)
	assert.Equal(t, "Stopped", actualWarmPoolState, "Warm pool state should be 'Stopped'")
}

// TestAutoscalingWithScalingPolicies provisions the Auto Scaling Group fixture with scaling policies.
// It verifies:
// - Auto Scaling Group has scaling policies configured
// - Scheduled actions are created
// - Correct number of policies exist
func TestAutoscalingWithScalingPolicies(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("asgscl")

	// Configure Terraform options
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/autoscaling/with_scaling",
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
	asgArn := terraform.Output(t, terraformOptions, "autoscaling_group_arn")
	asgName := terraform.Output(t, terraformOptions, "autoscaling_group_name")
	scalingPolicyArns := terraform.OutputMap(t, terraformOptions, "scaling_policy_arns")
	scheduleArns := terraform.OutputMap(t, terraformOptions, "schedule_arns")

	// Assert outputs are not empty
	require.NotEmpty(t, asgArn, "autoscaling_group_arn should not be empty")
	require.NotEmpty(t, asgName, "autoscaling_group_name should not be empty")

	// Verify scaling policy outputs
	assert.Len(t, scalingPolicyArns, 3, "Should have 3 scaling policies (1 target tracking + 2 step)")

	// Verify scheduled action outputs
	assert.Len(t, scheduleArns, 3, "Should have 3 scheduled actions")

	// Use AWS SDK to verify Auto Scaling Group exists
	asgExists := helpers.AutoScalingGroupExists(t, asgName, awsRegion)
	assert.True(t, asgExists, "Auto Scaling Group should exist in AWS")

	// Verify scaling policies via AWS SDK
	policyCount := helpers.GetAutoScalingPolicyCount(t, asgName, awsRegion)
	assert.Equal(t, 3, policyCount, "Should have 3 scaling policies")

	// Verify specific policies exist
	hasCpuPolicy := helpers.AutoScalingPolicyExists(t, asgName, "cpu-target-tracking", awsRegion)
	assert.True(t, hasCpuPolicy, "cpu-target-tracking policy should exist")

	hasScaleOutPolicy := helpers.AutoScalingPolicyExists(t, asgName, "step-scale-out", awsRegion)
	assert.True(t, hasScaleOutPolicy, "step-scale-out policy should exist")

	hasScaleInPolicy := helpers.AutoScalingPolicyExists(t, asgName, "step-scale-in", awsRegion)
	assert.True(t, hasScaleInPolicy, "step-scale-in policy should exist")

	// Verify scheduled actions via AWS SDK
	scheduleCount := helpers.GetAutoScalingScheduledActionCount(t, asgName, awsRegion)
	assert.Equal(t, 3, scheduleCount, "Should have 3 scheduled actions")

	// Verify specific scheduled actions exist
	hasMorningSchedule := helpers.AutoScalingScheduledActionExists(t, asgName, "scale-up-weekday-morning", awsRegion)
	assert.True(t, hasMorningSchedule, "scale-up-weekday-morning schedule should exist")

	hasEveningSchedule := helpers.AutoScalingScheduledActionExists(t, asgName, "scale-down-weekday-evening", awsRegion)
	assert.True(t, hasEveningSchedule, "scale-down-weekday-evening schedule should exist")

	hasWeekendSchedule := helpers.AutoScalingScheduledActionExists(t, asgName, "weekend-minimal", awsRegion)
	assert.True(t, hasWeekendSchedule, "weekend-minimal schedule should exist")
}

// TestAutoscalingFull provisions the full Auto Scaling Group fixture with all features.
// It verifies:
// - Auto Scaling Group has all features configured
// - Mixed instances policy exists
// - Warm pool is configured
// - Scaling policies and scheduled actions exist
// - Lifecycle hooks are configured
func TestAutoscalingFull(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("asgfull")

	// Configure Terraform options
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/autoscaling/full",
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
	asgArn := terraform.Output(t, terraformOptions, "autoscaling_group_arn")
	asgName := terraform.Output(t, terraformOptions, "autoscaling_group_name")
	launchTemplateId := terraform.Output(t, terraformOptions, "launch_template_id")
	warmPoolState := terraform.Output(t, terraformOptions, "warm_pool_state")
	scalingPolicyArns := terraform.OutputMap(t, terraformOptions, "scaling_policy_arns")
	lifecycleHookNames := terraform.OutputList(t, terraformOptions, "lifecycle_hook_names")
	scheduleArns := terraform.OutputMap(t, terraformOptions, "schedule_arns")
	healthCheckType := terraform.Output(t, terraformOptions, "autoscaling_group_health_check_type")

	// Assert basic outputs are not empty
	require.NotEmpty(t, asgArn, "autoscaling_group_arn should not be empty")
	require.NotEmpty(t, asgName, "autoscaling_group_name should not be empty")
	require.NotEmpty(t, launchTemplateId, "launch_template_id should not be empty")

	// Verify warm pool
	assert.Equal(t, "Stopped", warmPoolState, "warm_pool_state should be 'Stopped'")

	// Verify scaling policies output count
	assert.Len(t, scalingPolicyArns, 2, "Should have 2 scaling policies")

	// Verify lifecycle hooks output count
	assert.Len(t, lifecycleHookNames, 2, "Should have 2 lifecycle hooks")
	assert.Contains(t, lifecycleHookNames, "launch-hook", "Should have launch-hook")
	assert.Contains(t, lifecycleHookNames, "terminate-hook", "Should have terminate-hook")

	// Verify scheduled actions output count
	assert.Len(t, scheduleArns, 2, "Should have 2 scheduled actions")

	// Verify health check type
	assert.Equal(t, "EC2", healthCheckType, "health_check_type should be EC2")

	// Use AWS SDK to verify Auto Scaling Group exists
	asgExists := helpers.AutoScalingGroupExists(t, asgName, awsRegion)
	assert.True(t, asgExists, "Auto Scaling Group should exist in AWS")

	// Verify mixed instances policy
	hasMixedInstancesPolicy := helpers.AutoScalingGroupHasMixedInstancesPolicy(t, asgName, awsRegion)
	assert.True(t, hasMixedInstancesPolicy, "Auto Scaling Group should have mixed instances policy")

	// Verify warm pool
	hasWarmPool := helpers.AutoScalingGroupHasWarmPool(t, asgName, awsRegion)
	assert.True(t, hasWarmPool, "Auto Scaling Group should have warm pool")

	actualWarmPoolState := helpers.GetAutoScalingGroupWarmPoolState(t, asgName, awsRegion)
	assert.Equal(t, "Stopped", actualWarmPoolState, "Warm pool state should be 'Stopped'")

	// Verify scaling policies
	policyCount := helpers.GetAutoScalingPolicyCount(t, asgName, awsRegion)
	assert.Equal(t, 2, policyCount, "Should have 2 scaling policies")

	hasCpuPolicy := helpers.AutoScalingPolicyExists(t, asgName, "cpu-target-tracking", awsRegion)
	assert.True(t, hasCpuPolicy, "cpu-target-tracking policy should exist")

	hasStepPolicy := helpers.AutoScalingPolicyExists(t, asgName, "memory-scale-out", awsRegion)
	assert.True(t, hasStepPolicy, "memory-scale-out policy should exist")

	// Verify lifecycle hooks
	hookCount := helpers.GetAutoScalingLifecycleHookCount(t, asgName, awsRegion)
	assert.Equal(t, 2, hookCount, "Should have 2 lifecycle hooks")

	hasLaunchHook := helpers.AutoScalingLifecycleHookExists(t, asgName, "launch-hook", awsRegion)
	assert.True(t, hasLaunchHook, "launch-hook should exist")

	hasTerminateHook := helpers.AutoScalingLifecycleHookExists(t, asgName, "terminate-hook", awsRegion)
	assert.True(t, hasTerminateHook, "terminate-hook should exist")

	// Verify scheduled actions
	scheduleCount := helpers.GetAutoScalingScheduledActionCount(t, asgName, awsRegion)
	assert.Equal(t, 2, scheduleCount, "Should have 2 scheduled actions")

	hasWorkdayUpSchedule := helpers.AutoScalingScheduledActionExists(t, asgName, "workday-scale-up", awsRegion)
	assert.True(t, hasWorkdayUpSchedule, "workday-scale-up schedule should exist")

	hasWorkdayDownSchedule := helpers.AutoScalingScheduledActionExists(t, asgName, "workday-scale-down", awsRegion)
	assert.True(t, hasWorkdayDownSchedule, "workday-scale-down schedule should exist")
}
