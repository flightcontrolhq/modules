// Package helpers provides utility functions for Terratest tests.
package helpers

import (
	"context"
	"os"
	"testing"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/ec2"
	"github.com/aws/aws-sdk-go-v2/service/ec2/types"
	"github.com/stretchr/testify/require"
)

// GetAwsRegion returns the AWS region to use for tests.
// It reads the AWS_REGION environment variable, defaulting to "us-east-1" if not set.
func GetAwsRegion() string {
	region := os.Getenv("AWS_REGION")
	if region == "" {
		return "us-east-1"
	}
	return region
}

// getEC2Client creates an EC2 client for the specified region.
func getEC2Client(t *testing.T, region string) *ec2.Client {
	cfg, err := config.LoadDefaultConfig(context.TODO(), config.WithRegion(region))
	require.NoError(t, err, "Failed to load AWS config")
	return ec2.NewFromConfig(cfg)
}

// VpcExists checks if a VPC with the given ID exists in the specified region.
func VpcExists(t *testing.T, vpcId string, region string) bool {
	client := getEC2Client(t, region)

	input := &ec2.DescribeVpcsInput{
		VpcIds: []string{vpcId},
	}

	result, err := client.DescribeVpcs(context.TODO(), input)
	if err != nil {
		// If the VPC doesn't exist, AWS returns an error
		return false
	}

	return len(result.Vpcs) > 0
}

// SubnetsExist checks if all the given subnet IDs exist in the specified region.
func SubnetsExist(t *testing.T, subnetIds []string, region string) bool {
	if len(subnetIds) == 0 {
		return false
	}

	client := getEC2Client(t, region)

	input := &ec2.DescribeSubnetsInput{
		SubnetIds: subnetIds,
	}

	result, err := client.DescribeSubnets(context.TODO(), input)
	if err != nil {
		// If any subnet doesn't exist, AWS returns an error
		return false
	}

	// Verify we got back all the subnets we asked for
	return len(result.Subnets) == len(subnetIds)
}

// GetVpcCidr returns the primary CIDR block for the specified VPC.
// It fails the test if the VPC doesn't exist or has no CIDR block.
func GetVpcCidr(t *testing.T, vpcId string, region string) string {
	client := getEC2Client(t, region)

	input := &ec2.DescribeVpcsInput{
		VpcIds: []string{vpcId},
	}

	result, err := client.DescribeVpcs(context.TODO(), input)
	require.NoError(t, err, "Failed to describe VPC %s", vpcId)
	require.Len(t, result.Vpcs, 1, "Expected exactly one VPC with ID %s", vpcId)

	vpc := result.Vpcs[0]
	require.NotNil(t, vpc.CidrBlock, "VPC %s has no CIDR block", vpcId)

	return *vpc.CidrBlock
}

// GetVpcState returns the state of the specified VPC.
func GetVpcState(t *testing.T, vpcId string, region string) types.VpcState {
	client := getEC2Client(t, region)

	input := &ec2.DescribeVpcsInput{
		VpcIds: []string{vpcId},
	}

	result, err := client.DescribeVpcs(context.TODO(), input)
	require.NoError(t, err, "Failed to describe VPC %s", vpcId)
	require.Len(t, result.Vpcs, 1, "Expected exactly one VPC with ID %s", vpcId)

	return result.Vpcs[0].State
}
