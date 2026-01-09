// Package test contains Terratest integration tests for the Terraform modules.
package test

import (
	"testing"

	"github.com/flightcontrolhq/modules/test/helpers"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestVpcBasic provisions the basic VPC fixture and validates the outputs.
// It verifies:
// - vpc_id is not empty
// - public_subnet_ids has 3 elements
// - private_subnet_ids has 3 elements
// - VPC exists in AWS with the correct CIDR block
func TestVpcBasic(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("vpc")

	// Configure Terraform options
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/vpc/basic",
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
	vpcId := terraform.Output(t, terraformOptions, "vpc_id")
	publicSubnetIds := terraform.OutputList(t, terraformOptions, "public_subnet_ids")
	privateSubnetIds := terraform.OutputList(t, terraformOptions, "private_subnet_ids")
	internetGatewayId := terraform.Output(t, terraformOptions, "internet_gateway_id")

	// Assert vpc_id is not empty
	require.NotEmpty(t, vpcId, "vpc_id should not be empty")

	// Assert public_subnet_ids has 3 elements
	assert.Len(t, publicSubnetIds, 3, "public_subnet_ids should have 3 elements")

	// Assert private_subnet_ids has 3 elements
	assert.Len(t, privateSubnetIds, 3, "private_subnet_ids should have 3 elements")

	// Assert internet_gateway_id is not empty
	assert.NotEmpty(t, internetGatewayId, "internet_gateway_id should not be empty")

	// Use AWS SDK to verify VPC exists
	vpcExists := helpers.VpcExists(t, vpcId, awsRegion)
	assert.True(t, vpcExists, "VPC should exist in AWS")

	// Use AWS SDK to verify VPC has correct CIDR
	vpcCidr := helpers.GetVpcCidr(t, vpcId, awsRegion)
	assert.Equal(t, "10.0.0.0/16", vpcCidr, "VPC should have CIDR 10.0.0.0/16")

	// Use AWS SDK to verify all subnets exist
	allSubnetIds := append(publicSubnetIds, privateSubnetIds...)
	subnetsExist := helpers.SubnetsExist(t, allSubnetIds, awsRegion)
	assert.True(t, subnetsExist, "All subnets should exist in AWS")
}

// TestVpcWithNatGateway provisions the VPC with NAT Gateway fixture and validates:
// - NAT gateway is created
// - Private route tables have routes to the NAT gateway
// - NAT gateway is in 'available' state
func TestVpcWithNatGateway(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("vpc-nat")

	// Configure Terraform options
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/vpc/with_nat",
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
	vpcId := terraform.Output(t, terraformOptions, "vpc_id")
	natGatewayIds := terraform.OutputList(t, terraformOptions, "nat_gateway_ids")
	natGatewayPublicIps := terraform.OutputList(t, terraformOptions, "nat_gateway_public_ips")
	privateRouteTableIds := terraform.OutputList(t, terraformOptions, "private_route_table_ids")

	// Assert vpc_id is not empty
	require.NotEmpty(t, vpcId, "vpc_id should not be empty")

	// Assert NAT gateway is created (single_nat_gateway=true means 1 NAT gateway)
	require.Len(t, natGatewayIds, 1, "nat_gateway_ids should have 1 element (single NAT gateway)")
	require.NotEmpty(t, natGatewayIds[0], "nat_gateway_id should not be empty")

	// Assert NAT gateway has a public IP
	require.Len(t, natGatewayPublicIps, 1, "nat_gateway_public_ips should have 1 element")
	require.NotEmpty(t, natGatewayPublicIps[0], "nat_gateway_public_ip should not be empty")

	// Use AWS SDK to verify NAT gateway exists
	natGatewayId := natGatewayIds[0]
	natGatewayExists := helpers.NatGatewayExists(t, natGatewayId, awsRegion)
	assert.True(t, natGatewayExists, "NAT Gateway should exist in AWS")

	// Use AWS SDK to verify NAT gateway is in 'available' state
	natGatewayState := helpers.GetNatGatewayState(t, natGatewayId, awsRegion)
	assert.Equal(t, "available", string(natGatewayState), "NAT Gateway should be in 'available' state")

	// Verify private route tables have routes to the NAT gateway
	require.NotEmpty(t, privateRouteTableIds, "private_route_table_ids should not be empty")
	for _, routeTableId := range privateRouteTableIds {
		hasNatRoute := helpers.RouteTableHasNatGatewayRoute(t, routeTableId, awsRegion)
		assert.True(t, hasNatRoute, "Private route table %s should have a route to NAT Gateway", routeTableId)
	}
}

// TestVpcWithHaNat provisions the full VPC fixture with HA NAT Gateways (one per AZ)
// and validates:
// - 3 NAT gateways are created (one per AZ)
// - Each NAT gateway is in 'available' state
// - Each private subnet routes to its own NAT gateway
func TestVpcWithHaNat(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("vpc-ha-nat")

	// Configure Terraform options
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/vpc/full",
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
	vpcId := terraform.Output(t, terraformOptions, "vpc_id")
	natGatewayIds := terraform.OutputList(t, terraformOptions, "nat_gateway_ids")
	natGatewayPublicIps := terraform.OutputList(t, terraformOptions, "nat_gateway_public_ips")
	privateRouteTableIds := terraform.OutputList(t, terraformOptions, "private_route_table_ids")

	// Assert vpc_id is not empty
	require.NotEmpty(t, vpcId, "vpc_id should not be empty")

	// Assert 3 NAT gateways are created (one per AZ, since single_nat_gateway=false)
	require.Len(t, natGatewayIds, 3, "nat_gateway_ids should have 3 elements (one per AZ)")
	for i, natGatewayId := range natGatewayIds {
		require.NotEmpty(t, natGatewayId, "nat_gateway_id[%d] should not be empty", i)
	}

	// Assert each NAT gateway has a public IP
	require.Len(t, natGatewayPublicIps, 3, "nat_gateway_public_ips should have 3 elements")
	for i, publicIp := range natGatewayPublicIps {
		require.NotEmpty(t, publicIp, "nat_gateway_public_ip[%d] should not be empty", i)
	}

	// Use AWS SDK to verify each NAT gateway exists and is in 'available' state
	for _, natGatewayId := range natGatewayIds {
		natGatewayExists := helpers.NatGatewayExists(t, natGatewayId, awsRegion)
		assert.True(t, natGatewayExists, "NAT Gateway %s should exist in AWS", natGatewayId)

		natGatewayState := helpers.GetNatGatewayState(t, natGatewayId, awsRegion)
		assert.Equal(t, "available", string(natGatewayState), "NAT Gateway %s should be in 'available' state", natGatewayId)
	}

	// Verify we have 3 private route tables (one per AZ)
	require.Len(t, privateRouteTableIds, 3, "private_route_table_ids should have 3 elements (one per AZ)")

	// Verify each private route table routes to a NAT gateway
	// and collect the NAT gateway IDs used by route tables
	natGatewayIdsFromRoutes := make(map[string]bool)
	for _, routeTableId := range privateRouteTableIds {
		hasNatRoute := helpers.RouteTableHasNatGatewayRoute(t, routeTableId, awsRegion)
		assert.True(t, hasNatRoute, "Private route table %s should have a route to NAT Gateway", routeTableId)

		// Get the NAT gateway ID from the route table
		natGatewayId := helpers.GetRouteTableNatGatewayId(t, routeTableId, awsRegion)
		if natGatewayId != "" {
			natGatewayIdsFromRoutes[natGatewayId] = true
		}
	}

	// Verify that each private subnet routes to a different NAT gateway (HA configuration)
	// In HA mode, each route table should point to its own NAT gateway
	assert.Len(t, natGatewayIdsFromRoutes, 3, "Each private route table should route to a different NAT Gateway in HA configuration")
}

// TestVpcWithIPv6 provisions the full VPC fixture with IPv6 enabled and validates:
// - VPC has an IPv6 CIDR block assigned
// - Egress-only internet gateway is created
// - All subnets have IPv6 CIDRs
func TestVpcWithIPv6(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("vpc-ipv6")

	// Configure Terraform options
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/vpc/full",
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
	vpcId := terraform.Output(t, terraformOptions, "vpc_id")
	vpcIpv6CidrBlock := terraform.Output(t, terraformOptions, "vpc_ipv6_cidr_block")
	publicSubnetIds := terraform.OutputList(t, terraformOptions, "public_subnet_ids")
	privateSubnetIds := terraform.OutputList(t, terraformOptions, "private_subnet_ids")
	publicSubnetIpv6Cidrs := terraform.OutputList(t, terraformOptions, "public_subnet_ipv6_cidrs")
	privateSubnetIpv6Cidrs := terraform.OutputList(t, terraformOptions, "private_subnet_ipv6_cidrs")
	egressOnlyIgwId := terraform.Output(t, terraformOptions, "egress_only_internet_gateway_id")

	// Assert vpc_id is not empty
	require.NotEmpty(t, vpcId, "vpc_id should not be empty")

	// Assert VPC has IPv6 CIDR block from Terraform output
	require.NotEmpty(t, vpcIpv6CidrBlock, "vpc_ipv6_cidr_block should not be empty")

	// Use AWS SDK to verify VPC has IPv6 CIDR block
	vpcHasIpv6 := helpers.VpcHasIpv6CidrBlock(t, vpcId, awsRegion)
	assert.True(t, vpcHasIpv6, "VPC should have an IPv6 CIDR block assigned")

	// Verify the IPv6 CIDR from AWS matches the Terraform output
	awsVpcIpv6Cidr := helpers.GetVpcIpv6CidrBlock(t, vpcId, awsRegion)
	assert.Equal(t, vpcIpv6CidrBlock, awsVpcIpv6Cidr, "VPC IPv6 CIDR block should match Terraform output")

	// Assert egress-only internet gateway is created
	require.NotEmpty(t, egressOnlyIgwId, "egress_only_internet_gateway_id should not be empty")

	// Use AWS SDK to verify egress-only internet gateway exists
	eigwExists := helpers.EgressOnlyInternetGatewayExists(t, egressOnlyIgwId, awsRegion)
	assert.True(t, eigwExists, "Egress-only internet gateway should exist in AWS")

	// Assert public subnets have IPv6 CIDRs from Terraform output
	require.Len(t, publicSubnetIpv6Cidrs, 3, "public_subnet_ipv6_cidrs should have 3 elements")
	for i, cidr := range publicSubnetIpv6Cidrs {
		require.NotEmpty(t, cidr, "public_subnet_ipv6_cidr[%d] should not be empty", i)
	}

	// Assert private subnets have IPv6 CIDRs from Terraform output
	require.Len(t, privateSubnetIpv6Cidrs, 3, "private_subnet_ipv6_cidrs should have 3 elements")
	for i, cidr := range privateSubnetIpv6Cidrs {
		require.NotEmpty(t, cidr, "private_subnet_ipv6_cidr[%d] should not be empty", i)
	}

	// Use AWS SDK to verify each public subnet has IPv6 CIDR
	for _, subnetId := range publicSubnetIds {
		subnetHasIpv6 := helpers.SubnetHasIpv6CidrBlock(t, subnetId, awsRegion)
		assert.True(t, subnetHasIpv6, "Public subnet %s should have an IPv6 CIDR block", subnetId)
	}

	// Use AWS SDK to verify each private subnet has IPv6 CIDR
	for _, subnetId := range privateSubnetIds {
		subnetHasIpv6 := helpers.SubnetHasIpv6CidrBlock(t, subnetId, awsRegion)
		assert.True(t, subnetHasIpv6, "Private subnet %s should have an IPv6 CIDR block", subnetId)
	}
}

// TestVpcFlowLogsCloudWatch provisions the full VPC fixture with flow_logs_destination=cloudwatch
// and validates:
// - CloudWatch log group is created
// - VPC flow log is created and attached to the VPC
// - Flow log destination is CloudWatch Logs
// - Flow log is in ACTIVE state
func TestVpcFlowLogsCloudWatch(t *testing.T) {
	t.Parallel()

	// Get AWS region from environment or use default
	awsRegion := helpers.GetAwsRegion()

	// Generate a unique name for this test run
	uniqueName := helpers.UniqueResourceName("vpc-flowlogs")

	// Configure Terraform options
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/vpc/full",
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
	vpcId := terraform.Output(t, terraformOptions, "vpc_id")
	flowLogId := terraform.Output(t, terraformOptions, "flow_log_id")
	flowLogLogGroupName := terraform.Output(t, terraformOptions, "flow_log_cloudwatch_log_group_name")
	flowLogLogGroupArn := terraform.Output(t, terraformOptions, "flow_log_cloudwatch_log_group_arn")

	// Assert vpc_id is not empty
	require.NotEmpty(t, vpcId, "vpc_id should not be empty")

	// Assert flow_log_id is not empty
	require.NotEmpty(t, flowLogId, "flow_log_id should not be empty")

	// Assert CloudWatch log group name is not empty
	require.NotEmpty(t, flowLogLogGroupName, "flow_log_cloudwatch_log_group_name should not be empty")

	// Assert CloudWatch log group ARN is not empty
	require.NotEmpty(t, flowLogLogGroupArn, "flow_log_cloudwatch_log_group_arn should not be empty")

	// Use AWS SDK to verify CloudWatch log group exists
	logGroupExists := helpers.CloudWatchLogGroupExists(t, flowLogLogGroupName, awsRegion)
	assert.True(t, logGroupExists, "CloudWatch log group %s should exist in AWS", flowLogLogGroupName)

	// Use AWS SDK to verify flow log exists
	flowLogExists := helpers.VpcFlowLogExists(t, flowLogId, awsRegion)
	assert.True(t, flowLogExists, "VPC flow log %s should exist in AWS", flowLogId)

	// Use AWS SDK to verify flow log is in ACTIVE state
	flowLogStatus := helpers.GetVpcFlowLogStatus(t, flowLogId, awsRegion)
	assert.Equal(t, "ACTIVE", flowLogStatus, "VPC flow log should be in ACTIVE state")

	// Use AWS SDK to verify flow log is attached to the VPC
	flowLogAttached := helpers.VpcFlowLogIsAttachedToVpc(t, flowLogId, vpcId, awsRegion)
	assert.True(t, flowLogAttached, "VPC flow log should be attached to VPC %s", vpcId)

	// Use AWS SDK to verify flow log destination type is CloudWatch Logs
	flowLogDestType := helpers.GetVpcFlowLogDestinationType(t, flowLogId, awsRegion)
	assert.Equal(t, "cloud-watch-logs", string(flowLogDestType), "VPC flow log destination type should be cloud-watch-logs")
}
