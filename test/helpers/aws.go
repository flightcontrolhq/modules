// Package helpers provides utility functions for Terratest tests.
package helpers

import (
	"context"
	"os"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/ec2"
	"github.com/aws/aws-sdk-go-v2/service/ec2/types"
	"github.com/aws/aws-sdk-go-v2/service/ecs"
	ecstypes "github.com/aws/aws-sdk-go-v2/service/ecs/types"
	"github.com/aws/aws-sdk-go-v2/service/elasticache"
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

// getECSClient creates an ECS client for the specified region.
func getECSClient(t *testing.T, region string) *ecs.Client {
	cfg, err := config.LoadDefaultConfig(context.TODO(), config.WithRegion(region))
	require.NoError(t, err, "Failed to load AWS config")
	return ecs.NewFromConfig(cfg)
}

// EcsClusterExists checks if an ECS cluster with the given ARN exists.
func EcsClusterExists(t *testing.T, clusterArn string, region string) bool {
	client := getECSClient(t, region)

	input := &ecs.DescribeClustersInput{
		Clusters: []string{clusterArn},
	}

	result, err := client.DescribeClusters(context.TODO(), input)
	if err != nil {
		return false
	}

	// Check that the cluster exists and is not in INACTIVE status
	for _, cluster := range result.Clusters {
		if cluster.ClusterArn != nil && *cluster.ClusterArn == clusterArn {
			return cluster.Status != nil && *cluster.Status != "INACTIVE"
		}
	}

	return false
}

// GetEcsClusterStatus returns the status of an ECS cluster.
// Common statuses: ACTIVE, PROVISIONING, DEPROVISIONING, FAILED, INACTIVE.
func GetEcsClusterStatus(t *testing.T, clusterArn string, region string) string {
	client := getECSClient(t, region)

	input := &ecs.DescribeClustersInput{
		Clusters: []string{clusterArn},
	}

	result, err := client.DescribeClusters(context.TODO(), input)
	require.NoError(t, err, "Failed to describe ECS cluster %s", clusterArn)
	require.Len(t, result.Clusters, 1, "Expected exactly one ECS cluster with ARN %s", clusterArn)

	if result.Clusters[0].Status != nil {
		return *result.Clusters[0].Status
	}
	return ""
}

// GetEcsClusterCapacityProviders returns the list of capacity providers attached to an ECS cluster.
func GetEcsClusterCapacityProviders(t *testing.T, clusterArn string, region string) []string {
	client := getECSClient(t, region)

	input := &ecs.DescribeClustersInput{
		Clusters: []string{clusterArn},
	}

	result, err := client.DescribeClusters(context.TODO(), input)
	require.NoError(t, err, "Failed to describe ECS cluster %s", clusterArn)
	require.Len(t, result.Clusters, 1, "Expected exactly one ECS cluster with ARN %s", clusterArn)

	return result.Clusters[0].CapacityProviders
}

// EcsClusterHasCapacityProvider checks if an ECS cluster has a specific capacity provider attached.
func EcsClusterHasCapacityProvider(t *testing.T, clusterArn string, capacityProviderName string, region string) bool {
	capacityProviders := GetEcsClusterCapacityProviders(t, clusterArn, region)

	for _, cp := range capacityProviders {
		if cp == capacityProviderName {
			return true
		}
	}

	return false
}

// GetEcsClusterDefaultCapacityProviderStrategy returns the default capacity provider strategy for a cluster.
func GetEcsClusterDefaultCapacityProviderStrategy(t *testing.T, clusterArn string, region string) []ecstypes.CapacityProviderStrategyItem {
	client := getECSClient(t, region)

	input := &ecs.DescribeClustersInput{
		Clusters: []string{clusterArn},
	}

	result, err := client.DescribeClusters(context.TODO(), input)
	require.NoError(t, err, "Failed to describe ECS cluster %s", clusterArn)
	require.Len(t, result.Clusters, 1, "Expected exactly one ECS cluster with ARN %s", clusterArn)

	return result.Clusters[0].DefaultCapacityProviderStrategy
}

// TargetGroupExists checks if a target group with the given ARN exists.
func TargetGroupExists(t *testing.T, targetGroupArn string, region string) bool {
	client := getELBv2Client(t, region)

	input := &elbv2.DescribeTargetGroupsInput{
		TargetGroupArns: []string{targetGroupArn},
	}

	result, err := client.DescribeTargetGroups(context.TODO(), input)
	if err != nil {
		return false
	}

	return len(result.TargetGroups) > 0
}

// GetTargetGroupTargetType returns the target type of a target group (instance, ip, lambda, alb).
func GetTargetGroupTargetType(t *testing.T, targetGroupArn string, region string) elbv2types.TargetTypeEnum {
	client := getELBv2Client(t, region)

	input := &elbv2.DescribeTargetGroupsInput{
		TargetGroupArns: []string{targetGroupArn},
	}

	result, err := client.DescribeTargetGroups(context.TODO(), input)
	require.NoError(t, err, "Failed to describe target group %s", targetGroupArn)
	require.Len(t, result.TargetGroups, 1, "Expected exactly one target group with ARN %s", targetGroupArn)

	return result.TargetGroups[0].TargetType
}

// GetTargetGroupProtocol returns the protocol of a target group (HTTP, HTTPS, TCP, etc.).
func GetTargetGroupProtocol(t *testing.T, targetGroupArn string, region string) elbv2types.ProtocolEnum {
	client := getELBv2Client(t, region)

	input := &elbv2.DescribeTargetGroupsInput{
		TargetGroupArns: []string{targetGroupArn},
	}

	result, err := client.DescribeTargetGroups(context.TODO(), input)
	require.NoError(t, err, "Failed to describe target group %s", targetGroupArn)
	require.Len(t, result.TargetGroups, 1, "Expected exactly one target group with ARN %s", targetGroupArn)

	return result.TargetGroups[0].Protocol
}

// GetTargetGroupPort returns the port of a target group.
func GetTargetGroupPort(t *testing.T, targetGroupArn string, region string) int32 {
	client := getELBv2Client(t, region)

	input := &elbv2.DescribeTargetGroupsInput{
		TargetGroupArns: []string{targetGroupArn},
	}

	result, err := client.DescribeTargetGroups(context.TODO(), input)
	require.NoError(t, err, "Failed to describe target group %s", targetGroupArn)
	require.Len(t, result.TargetGroups, 1, "Expected exactly one target group with ARN %s", targetGroupArn)

	if result.TargetGroups[0].Port != nil {
		return *result.TargetGroups[0].Port
	}
	return 0
}

// EcsServiceExists checks if an ECS service with the given name exists in the specified cluster.
func EcsServiceExists(t *testing.T, clusterArn string, serviceName string, region string) bool {
	client := getECSClient(t, region)

	input := &ecs.DescribeServicesInput{
		Cluster:  &clusterArn,
		Services: []string{serviceName},
	}

	result, err := client.DescribeServices(context.TODO(), input)
	if err != nil {
		return false
	}

	// Check that the service exists and is not in INACTIVE status
	for _, service := range result.Services {
		if service.ServiceName != nil && *service.ServiceName == serviceName {
			return service.Status != nil && *service.Status != "INACTIVE"
		}
	}

	return false
}

// GetEcsServiceStatus returns the status of an ECS service.
// Common statuses: ACTIVE, DRAINING, INACTIVE.
func GetEcsServiceStatus(t *testing.T, clusterArn string, serviceName string, region string) string {
	client := getECSClient(t, region)

	input := &ecs.DescribeServicesInput{
		Cluster:  &clusterArn,
		Services: []string{serviceName},
	}

	result, err := client.DescribeServices(context.TODO(), input)
	require.NoError(t, err, "Failed to describe ECS service %s", serviceName)
	require.Len(t, result.Services, 1, "Expected exactly one ECS service with name %s", serviceName)

	if result.Services[0].Status != nil {
		return *result.Services[0].Status
	}
	return ""
}

// GetEcsServiceDesiredCount returns the desired count of an ECS service.
func GetEcsServiceDesiredCount(t *testing.T, clusterArn string, serviceName string, region string) int32 {
	client := getECSClient(t, region)

	input := &ecs.DescribeServicesInput{
		Cluster:  &clusterArn,
		Services: []string{serviceName},
	}

	result, err := client.DescribeServices(context.TODO(), input)
	require.NoError(t, err, "Failed to describe ECS service %s", serviceName)
	require.Len(t, result.Services, 1, "Expected exactly one ECS service with name %s", serviceName)

	return result.Services[0].DesiredCount
}

// GetEcsServiceRunningCount returns the running count of an ECS service.
func GetEcsServiceRunningCount(t *testing.T, clusterArn string, serviceName string, region string) int32 {
	client := getECSClient(t, region)

	input := &ecs.DescribeServicesInput{
		Cluster:  &clusterArn,
		Services: []string{serviceName},
	}

	result, err := client.DescribeServices(context.TODO(), input)
	require.NoError(t, err, "Failed to describe ECS service %s", serviceName)
	require.Len(t, result.Services, 1, "Expected exactly one ECS service with name %s", serviceName)

	return result.Services[0].RunningCount
}

// WaitForEcsServiceRunningCount waits for an ECS service to reach the expected running count.
// It retries up to maxRetries times with retryInterval seconds between each retry.
// Returns true if the service reached the expected running count, false otherwise.
func WaitForEcsServiceRunningCount(t *testing.T, clusterArn string, serviceName string, expectedCount int32, maxRetries int, retryIntervalSeconds int, region string) bool {
	client := getECSClient(t, region)

	for i := 0; i < maxRetries; i++ {
		input := &ecs.DescribeServicesInput{
			Cluster:  &clusterArn,
			Services: []string{serviceName},
		}

		result, err := client.DescribeServices(context.TODO(), input)
		if err != nil {
			t.Logf("Retry %d/%d: Failed to describe ECS service %s: %v", i+1, maxRetries, serviceName, err)
			continue
		}

		if len(result.Services) == 1 {
			runningCount := result.Services[0].RunningCount
			t.Logf("Retry %d/%d: ECS service %s running count: %d (expected: %d)", i+1, maxRetries, serviceName, runningCount, expectedCount)
			if runningCount == expectedCount {
				return true
			}
		}

		if i < maxRetries-1 {
			t.Logf("Waiting %d seconds before next retry...", retryIntervalSeconds)
			time.Sleep(time.Duration(retryIntervalSeconds) * time.Second)
		}
	}

	return false
}

// GetEcsServiceLoadBalancers returns the load balancer configurations attached to an ECS service.
func GetEcsServiceLoadBalancers(t *testing.T, clusterArn string, serviceName string, region string) []ecstypes.LoadBalancer {
	client := getECSClient(t, region)

	input := &ecs.DescribeServicesInput{
		Cluster:  &clusterArn,
		Services: []string{serviceName},
	}

	result, err := client.DescribeServices(context.TODO(), input)
	require.NoError(t, err, "Failed to describe ECS service %s", serviceName)
	require.Len(t, result.Services, 1, "Expected exactly one ECS service with name %s", serviceName)

	return result.Services[0].LoadBalancers
}

// EcsServiceHasTargetGroup checks if an ECS service is registered with a specific target group.
func EcsServiceHasTargetGroup(t *testing.T, clusterArn string, serviceName string, targetGroupArn string, region string) bool {
	loadBalancers := GetEcsServiceLoadBalancers(t, clusterArn, serviceName, region)

	for _, lb := range loadBalancers {
		if lb.TargetGroupArn != nil && *lb.TargetGroupArn == targetGroupArn {
			return true
		}
	}

	return false
}

// GetTargetGroupHealthCounts returns the count of healthy and unhealthy targets in a target group.
func GetTargetGroupHealthCounts(t *testing.T, targetGroupArn string, region string) (healthy int, unhealthy int, total int) {
	client := getELBv2Client(t, region)

	input := &elbv2.DescribeTargetHealthInput{
		TargetGroupArn: &targetGroupArn,
	}

	result, err := client.DescribeTargetHealth(context.TODO(), input)
	require.NoError(t, err, "Failed to describe target health for target group %s", targetGroupArn)

	for _, targetHealth := range result.TargetHealthDescriptions {
		total++
		if targetHealth.TargetHealth != nil {
			switch targetHealth.TargetHealth.State {
			case elbv2types.TargetHealthStateEnumHealthy:
				healthy++
			case elbv2types.TargetHealthStateEnumUnhealthy:
				unhealthy++
			}
		}
	}

	return healthy, unhealthy, total
}

// WaitForTargetGroupHealthyTargets waits for a target group to have at least minHealthy healthy targets.
// It retries up to maxRetries times with retryInterval seconds between each retry.
// Returns true if the target group has at least minHealthy healthy targets, false otherwise.
func WaitForTargetGroupHealthyTargets(t *testing.T, targetGroupArn string, minHealthy int, maxRetries int, retryIntervalSeconds int, region string) bool {
	for i := 0; i < maxRetries; i++ {
		healthy, unhealthy, total := GetTargetGroupHealthCounts(t, targetGroupArn, region)
		t.Logf("Retry %d/%d: Target group has %d healthy, %d unhealthy, %d total targets (need at least %d healthy)",
			i+1, maxRetries, healthy, unhealthy, total, minHealthy)

		if healthy >= minHealthy {
			return true
		}

		if i < maxRetries-1 {
			t.Logf("Waiting %d seconds before next retry...", retryIntervalSeconds)
			time.Sleep(time.Duration(retryIntervalSeconds) * time.Second)
		}
	}

	return false
}

// TargetGroupHasRegisteredTargets checks if a target group has any registered targets.
func TargetGroupHasRegisteredTargets(t *testing.T, targetGroupArn string, region string) bool {
	_, _, total := GetTargetGroupHealthCounts(t, targetGroupArn, region)
	return total > 0
}

// getElastiCacheClient creates an ElastiCache client for the specified region.
func getElastiCacheClient(t *testing.T, region string) *elasticache.Client {
	cfg, err := config.LoadDefaultConfig(context.TODO(), config.WithRegion(region))
	require.NoError(t, err, "Failed to load AWS config")
	return elasticache.NewFromConfig(cfg)
}

// ElastiCacheReplicationGroupExists checks if an ElastiCache replication group with the given ID exists.
func ElastiCacheReplicationGroupExists(t *testing.T, replicationGroupId string, region string) bool {
	client := getElastiCacheClient(t, region)

	input := &elasticache.DescribeReplicationGroupsInput{
		ReplicationGroupId: &replicationGroupId,
	}

	result, err := client.DescribeReplicationGroups(context.TODO(), input)
	if err != nil {
		return false
	}

	return len(result.ReplicationGroups) > 0
}

// GetElastiCacheReplicationGroupStatus returns the status of an ElastiCache replication group.
// Common statuses: creating, available, modifying, deleting, create-failed, snapshotting.
func GetElastiCacheReplicationGroupStatus(t *testing.T, replicationGroupId string, region string) string {
	client := getElastiCacheClient(t, region)

	input := &elasticache.DescribeReplicationGroupsInput{
		ReplicationGroupId: &replicationGroupId,
	}

	result, err := client.DescribeReplicationGroups(context.TODO(), input)
	require.NoError(t, err, "Failed to describe ElastiCache replication group %s", replicationGroupId)
	require.Len(t, result.ReplicationGroups, 1, "Expected exactly one replication group with ID %s", replicationGroupId)

	if result.ReplicationGroups[0].Status != nil {
		return *result.ReplicationGroups[0].Status
	}
	return ""
}

// GetRouteTableNatGatewayId returns the NAT Gateway ID from a route table's default route (0.0.0.0/0).
// Returns an empty string if no NAT Gateway route is found.
func GetRouteTableNatGatewayId(t *testing.T, routeTableId string, region string) string {
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
				return *route.NatGatewayId
			}
		}
	}

	return ""
}
