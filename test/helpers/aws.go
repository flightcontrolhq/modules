// Package helpers provides utility functions for Terratest tests.
package helpers

import (
	"context"
	"os"
	"testing"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/ec2"
	"github.com/aws/aws-sdk-go-v2/service/ec2/types"
	elbv2 "github.com/aws/aws-sdk-go-v2/service/elasticloadbalancingv2"
	elbv2types "github.com/aws/aws-sdk-go-v2/service/elasticloadbalancingv2/types"
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

// GetNatGatewayState returns the state of a NAT Gateway.
// Returns the state as a string (pending, failed, available, deleting, deleted).
func GetNatGatewayState(t *testing.T, natGatewayId string, region string) types.NatGatewayState {
	client := getEC2Client(t, region)

	input := &ec2.DescribeNatGatewaysInput{
		NatGatewayIds: []string{natGatewayId},
	}

	result, err := client.DescribeNatGateways(context.TODO(), input)
	require.NoError(t, err, "Failed to describe NAT Gateway %s", natGatewayId)
	require.Len(t, result.NatGateways, 1, "Expected exactly one NAT Gateway with ID %s", natGatewayId)

	return result.NatGateways[0].State
}

// NatGatewayExists checks if a NAT Gateway with the given ID exists in the specified region.
func NatGatewayExists(t *testing.T, natGatewayId string, region string) bool {
	client := getEC2Client(t, region)

	input := &ec2.DescribeNatGatewaysInput{
		NatGatewayIds: []string{natGatewayId},
	}

	result, err := client.DescribeNatGateways(context.TODO(), input)
	if err != nil {
		return false
	}

	return len(result.NatGateways) > 0
}

// RouteTableHasNatGatewayRoute checks if a route table has a route to a NAT Gateway.
// It looks for a route with destination 0.0.0.0/0 pointing to a NAT Gateway.
func RouteTableHasNatGatewayRoute(t *testing.T, routeTableId string, region string) bool {
	client := getEC2Client(t, region)

	input := &ec2.DescribeRouteTablesInput{
		RouteTableIds: []string{routeTableId},
	}

	result, err := client.DescribeRouteTables(context.TODO(), input)
	require.NoError(t, err, "Failed to describe route table %s", routeTableId)
	require.Len(t, result.RouteTables, 1, "Expected exactly one route table with ID %s", routeTableId)

	for _, route := range result.RouteTables[0].Routes {
		// Check for default route (0.0.0.0/0) pointing to a NAT Gateway
		if route.DestinationCidrBlock != nil && *route.DestinationCidrBlock == "0.0.0.0/0" {
			if route.NatGatewayId != nil && *route.NatGatewayId != "" {
				return true
			}
		}
	}

	return false
}

// getELBv2Client creates an ELBv2 client for the specified region.
func getELBv2Client(t *testing.T, region string) *elbv2.Client {
	cfg, err := config.LoadDefaultConfig(context.TODO(), config.WithRegion(region))
	require.NoError(t, err, "Failed to load AWS config")
	return elbv2.NewFromConfig(cfg)
}

// GetLoadBalancerState returns the state of an Application Load Balancer.
// Returns the state code (active, provisioning, active_impaired, failed).
func GetLoadBalancerState(t *testing.T, albArn string, region string) elbv2types.LoadBalancerStateEnum {
	client := getELBv2Client(t, region)

	input := &elbv2.DescribeLoadBalancersInput{
		LoadBalancerArns: []string{albArn},
	}

	result, err := client.DescribeLoadBalancers(context.TODO(), input)
	require.NoError(t, err, "Failed to describe load balancer %s", albArn)
	require.Len(t, result.LoadBalancers, 1, "Expected exactly one load balancer with ARN %s", albArn)

	return result.LoadBalancers[0].State.Code
}

// LoadBalancerExists checks if a load balancer with the given ARN exists.
func LoadBalancerExists(t *testing.T, albArn string, region string) bool {
	client := getELBv2Client(t, region)

	input := &elbv2.DescribeLoadBalancersInput{
		LoadBalancerArns: []string{albArn},
	}

	result, err := client.DescribeLoadBalancers(context.TODO(), input)
	if err != nil {
		return false
	}

	return len(result.LoadBalancers) > 0
}

// SecurityGroupExists checks if a security group with the given ID exists.
func SecurityGroupExists(t *testing.T, securityGroupId string, region string) bool {
	client := getEC2Client(t, region)

	input := &ec2.DescribeSecurityGroupsInput{
		GroupIds: []string{securityGroupId},
	}

	result, err := client.DescribeSecurityGroups(context.TODO(), input)
	if err != nil {
		return false
	}

	return len(result.SecurityGroups) > 0
}

// SecurityGroupHasIngressRule checks if a security group has an ingress rule for the specified port.
// It checks for TCP rules that allow traffic on the given port.
func SecurityGroupHasIngressRule(t *testing.T, securityGroupId string, port int32, region string) bool {
	client := getEC2Client(t, region)

	input := &ec2.DescribeSecurityGroupRulesInput{
		Filters: []types.Filter{
			{
				Name:   stringPtr("group-id"),
				Values: []string{securityGroupId},
			},
		},
	}

	result, err := client.DescribeSecurityGroupRules(context.TODO(), input)
	require.NoError(t, err, "Failed to describe security group rules for %s", securityGroupId)

	for _, rule := range result.SecurityGroupRules {
		// Check for ingress rules (not egress)
		if rule.IsEgress != nil && *rule.IsEgress {
			continue
		}

		// Check if the rule allows traffic on the specified port
		if rule.FromPort != nil && rule.ToPort != nil {
			if *rule.FromPort <= port && port <= *rule.ToPort {
				// Check for TCP protocol (-1 means all protocols, 6 is TCP)
				if rule.IpProtocol != nil && (*rule.IpProtocol == "tcp" || *rule.IpProtocol == "-1" || *rule.IpProtocol == "6") {
					return true
				}
			}
		}
	}

	return false
}

// stringPtr returns a pointer to the given string.
func stringPtr(s string) *string {
	return &s
}

// GetListenerProtocol returns the protocol of a listener (HTTP, HTTPS, etc.).
func GetListenerProtocol(t *testing.T, listenerArn string, region string) elbv2types.ProtocolEnum {
	client := getELBv2Client(t, region)

	input := &elbv2.DescribeListenersInput{
		ListenerArns: []string{listenerArn},
	}

	result, err := client.DescribeListeners(context.TODO(), input)
	require.NoError(t, err, "Failed to describe listener %s", listenerArn)
	require.Len(t, result.Listeners, 1, "Expected exactly one listener with ARN %s", listenerArn)

	return result.Listeners[0].Protocol
}

// GetListenerPort returns the port of a listener.
func GetListenerPort(t *testing.T, listenerArn string, region string) int32 {
	client := getELBv2Client(t, region)

	input := &elbv2.DescribeListenersInput{
		ListenerArns: []string{listenerArn},
	}

	result, err := client.DescribeListeners(context.TODO(), input)
	require.NoError(t, err, "Failed to describe listener %s", listenerArn)
	require.Len(t, result.Listeners, 1, "Expected exactly one listener with ARN %s", listenerArn)

	if result.Listeners[0].Port != nil {
		return *result.Listeners[0].Port
	}
	return 0
}

// ListenerHasRedirectAction checks if a listener has a redirect action as its default action.
// Returns true if the listener has a redirect action, and the redirect status code and target port.
func ListenerHasRedirectAction(t *testing.T, listenerArn string, region string) (bool, string, string) {
	client := getELBv2Client(t, region)

	input := &elbv2.DescribeListenersInput{
		ListenerArns: []string{listenerArn},
	}

	result, err := client.DescribeListeners(context.TODO(), input)
	require.NoError(t, err, "Failed to describe listener %s", listenerArn)
	require.Len(t, result.Listeners, 1, "Expected exactly one listener with ARN %s", listenerArn)

	for _, action := range result.Listeners[0].DefaultActions {
		if action.Type == elbv2types.ActionTypeEnumRedirect && action.RedirectConfig != nil {
			statusCode := ""
			port := ""
			if action.RedirectConfig.StatusCode != "" {
				statusCode = string(action.RedirectConfig.StatusCode)
			}
			if action.RedirectConfig.Port != nil {
				port = *action.RedirectConfig.Port
			}
			return true, statusCode, port
		}
	}

	return false, "", ""
}

// ListenerExists checks if a listener with the given ARN exists.
func ListenerExists(t *testing.T, listenerArn string, region string) bool {
	client := getELBv2Client(t, region)

	input := &elbv2.DescribeListenersInput{
		ListenerArns: []string{listenerArn},
	}

	result, err := client.DescribeListeners(context.TODO(), input)
	if err != nil {
		return false
	}

	return len(result.Listeners) > 0
}
