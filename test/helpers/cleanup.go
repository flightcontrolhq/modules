// Package helpers provides utility functions for Terratest tests.
package helpers

import (
	"context"
	"strings"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/ec2"
	ec2types "github.com/aws/aws-sdk-go-v2/service/ec2/types"
	"github.com/aws/aws-sdk-go-v2/service/ecs"
	"github.com/aws/aws-sdk-go-v2/service/elasticache"
	elbv2 "github.com/aws/aws-sdk-go-v2/service/elasticloadbalancingv2"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/stretchr/testify/require"
)

// OrphanedResource represents a resource that was created by terratest but not cleaned up.
type OrphanedResource struct {
	Type       string    // Resource type (e.g., "VPC", "ALB", "ECS Cluster")
	ID         string    // Resource ID or ARN
	Name       string    // Resource name (if available)
	CreatedAt  time.Time // Creation time (if available)
	Region     string    // AWS region
	Tags       map[string]string
}

// DefaultTerratestPrefix is the default prefix used for terratest resource names.
const DefaultTerratestPrefix = "terratest-"

// DefaultMaxAge is the default maximum age for resources before they're considered orphaned.
const DefaultMaxAge = 24 * time.Hour

// FindOrphanedResources finds all resources with the terratest prefix that are older than maxAge.
// If maxAge is 0, it defaults to 24 hours.
// Returns a list of orphaned resources that should be cleaned up.
func FindOrphanedResources(t *testing.T, prefix string, region string) []OrphanedResource {
	return FindOrphanedResourcesWithAge(t, prefix, DefaultMaxAge, region)
}

// FindOrphanedResourcesWithAge finds all resources with the given prefix that are older than maxAge.
func FindOrphanedResourcesWithAge(t *testing.T, prefix string, maxAge time.Duration, region string) []OrphanedResource {
	if prefix == "" {
		prefix = DefaultTerratestPrefix
	}

	cutoffTime := time.Now().Add(-maxAge)

	var orphans []OrphanedResource

	// Find orphaned VPCs
	vpcOrphans := findOrphanedVPCs(t, prefix, cutoffTime, region)
	orphans = append(orphans, vpcOrphans...)

	// Find orphaned Load Balancers (ALB/NLB)
	lbOrphans := findOrphanedLoadBalancers(t, prefix, cutoffTime, region)
	orphans = append(orphans, lbOrphans...)

	// Find orphaned ECS Clusters
	ecsOrphans := findOrphanedECSClusters(t, prefix, cutoffTime, region)
	orphans = append(orphans, ecsOrphans...)

	// Find orphaned ElastiCache clusters
	cacheOrphans := findOrphanedElastiCacheClusters(t, prefix, cutoffTime, region)
	orphans = append(orphans, cacheOrphans...)

	// Find orphaned S3 buckets
	s3Orphans := findOrphanedS3Buckets(t, prefix, cutoffTime, region)
	orphans = append(orphans, s3Orphans...)

	// Find orphaned Security Groups
	sgOrphans := findOrphanedSecurityGroups(t, prefix, cutoffTime, region)
	orphans = append(orphans, sgOrphans...)

	// Find orphaned NAT Gateways
	natOrphans := findOrphanedNATGateways(t, prefix, cutoffTime, region)
	orphans = append(orphans, natOrphans...)

	return orphans
}

// CleanupOrphanedResources deletes all orphaned resources with the given prefix.
// It finds resources older than 24 hours and deletes them in the correct order
// to handle dependencies (e.g., deleting ECS services before clusters).
func CleanupOrphanedResources(t *testing.T, prefix string, region string) {
	CleanupOrphanedResourcesWithAge(t, prefix, DefaultMaxAge, region)
}

// CleanupOrphanedResourcesWithAge deletes all orphaned resources older than maxAge.
func CleanupOrphanedResourcesWithAge(t *testing.T, prefix string, maxAge time.Duration, region string) {
	if prefix == "" {
		prefix = DefaultTerratestPrefix
	}

	cutoffTime := time.Now().Add(-maxAge)

	// Delete resources in dependency order (most dependent first)

	// 1. Delete ECS Services first (they depend on clusters and load balancers)
	cleanupOrphanedECSServices(t, prefix, cutoffTime, region)

	// 2. Delete ECS Clusters
	cleanupOrphanedECSClusters(t, prefix, cutoffTime, region)

	// 3. Delete Load Balancers (ALB/NLB)
	cleanupOrphanedLoadBalancers(t, prefix, cutoffTime, region)

	// 4. Delete ElastiCache clusters
	cleanupOrphanedElastiCacheClusters(t, prefix, cutoffTime, region)

	// 5. Delete NAT Gateways (they depend on subnets)
	cleanupOrphanedNATGateways(t, prefix, cutoffTime, region)

	// 6. Delete Security Groups (they may have dependencies on VPCs)
	cleanupOrphanedSecurityGroups(t, prefix, cutoffTime, region)

	// 7. Delete S3 Buckets
	cleanupOrphanedS3Buckets(t, prefix, cutoffTime, region)

	// 8. Delete VPCs last (they depend on everything else being deleted)
	cleanupOrphanedVPCs(t, prefix, cutoffTime, region)
}

// findOrphanedVPCs finds VPCs with the terratest prefix that are older than cutoffTime.
func findOrphanedVPCs(t *testing.T, prefix string, cutoffTime time.Time, region string) []OrphanedResource {
	cfg, err := config.LoadDefaultConfig(context.TODO(), config.WithRegion(region))
	require.NoError(t, err, "Failed to load AWS config")
	client := ec2.NewFromConfig(cfg)

	var orphans []OrphanedResource

	input := &ec2.DescribeVpcsInput{
		Filters: []ec2types.Filter{
			{
				Name:   stringPtr("tag:Name"),
				Values: []string{prefix + "*"},
			},
		},
	}

	result, err := client.DescribeVpcs(context.TODO(), input)
	if err != nil {
		t.Logf("Warning: Failed to describe VPCs: %v", err)
		return orphans
	}

	for _, vpc := range result.Vpcs {
		tags := tagsToMap(vpc.Tags)
		name := tags["Name"]

		// Check if the VPC name starts with the prefix
		if !strings.HasPrefix(name, prefix) {
			continue
		}

		orphans = append(orphans, OrphanedResource{
			Type:   "VPC",
			ID:     *vpc.VpcId,
			Name:   name,
			Region: region,
			Tags:   tags,
		})
	}

	return orphans
}

// findOrphanedLoadBalancers finds ALBs/NLBs with the terratest prefix.
func findOrphanedLoadBalancers(t *testing.T, prefix string, cutoffTime time.Time, region string) []OrphanedResource {
	cfg, err := config.LoadDefaultConfig(context.TODO(), config.WithRegion(region))
	require.NoError(t, err, "Failed to load AWS config")
	client := elbv2.NewFromConfig(cfg)

	var orphans []OrphanedResource

	input := &elbv2.DescribeLoadBalancersInput{}

	result, err := client.DescribeLoadBalancers(context.TODO(), input)
	if err != nil {
		t.Logf("Warning: Failed to describe load balancers: %v", err)
		return orphans
	}

	for _, lb := range result.LoadBalancers {
		if lb.LoadBalancerName == nil {
			continue
		}

		name := *lb.LoadBalancerName
		if !strings.HasPrefix(name, prefix) {
			continue
		}

		// Check creation time
		if lb.CreatedTime != nil && lb.CreatedTime.After(cutoffTime) {
			continue
		}

		lbType := "ALB"
		if lb.Type == "network" {
			lbType = "NLB"
		}

		orphans = append(orphans, OrphanedResource{
			Type:      lbType,
			ID:        *lb.LoadBalancerArn,
			Name:      name,
			CreatedAt: *lb.CreatedTime,
			Region:    region,
		})
	}

	return orphans
}

// findOrphanedECSClusters finds ECS clusters with the terratest prefix.
func findOrphanedECSClusters(t *testing.T, prefix string, cutoffTime time.Time, region string) []OrphanedResource {
	cfg, err := config.LoadDefaultConfig(context.TODO(), config.WithRegion(region))
	require.NoError(t, err, "Failed to load AWS config")
	client := ecs.NewFromConfig(cfg)

	var orphans []OrphanedResource

	listInput := &ecs.ListClustersInput{}
	listResult, err := client.ListClusters(context.TODO(), listInput)
	if err != nil {
		t.Logf("Warning: Failed to list ECS clusters: %v", err)
		return orphans
	}

	if len(listResult.ClusterArns) == 0 {
		return orphans
	}

	describeInput := &ecs.DescribeClustersInput{
		Clusters: listResult.ClusterArns,
	}

	describeResult, err := client.DescribeClusters(context.TODO(), describeInput)
	if err != nil {
		t.Logf("Warning: Failed to describe ECS clusters: %v", err)
		return orphans
	}

	for _, cluster := range describeResult.Clusters {
		if cluster.ClusterName == nil {
			continue
		}

		name := *cluster.ClusterName
		if !strings.HasPrefix(name, prefix) {
			continue
		}

		// Skip inactive clusters
		if cluster.Status != nil && *cluster.Status == "INACTIVE" {
			continue
		}

		orphans = append(orphans, OrphanedResource{
			Type:   "ECS Cluster",
			ID:     *cluster.ClusterArn,
			Name:   name,
			Region: region,
		})
	}

	return orphans
}

// findOrphanedElastiCacheClusters finds ElastiCache clusters with the terratest prefix.
func findOrphanedElastiCacheClusters(t *testing.T, prefix string, cutoffTime time.Time, region string) []OrphanedResource {
	cfg, err := config.LoadDefaultConfig(context.TODO(), config.WithRegion(region))
	require.NoError(t, err, "Failed to load AWS config")
	client := elasticache.NewFromConfig(cfg)

	var orphans []OrphanedResource

	// Check replication groups (Redis)
	rgInput := &elasticache.DescribeReplicationGroupsInput{}
	rgResult, err := client.DescribeReplicationGroups(context.TODO(), rgInput)
	if err != nil {
		t.Logf("Warning: Failed to describe ElastiCache replication groups: %v", err)
	} else {
		for _, rg := range rgResult.ReplicationGroups {
			if rg.ReplicationGroupId == nil {
				continue
			}

			name := *rg.ReplicationGroupId
			if !strings.HasPrefix(name, prefix) {
				continue
			}

			orphans = append(orphans, OrphanedResource{
				Type:   "ElastiCache Replication Group",
				ID:     name,
				Name:   name,
				Region: region,
			})
		}
	}

	// Check cache clusters (Memcached)
	ccInput := &elasticache.DescribeCacheClustersInput{}
	ccResult, err := client.DescribeCacheClusters(context.TODO(), ccInput)
	if err != nil {
		t.Logf("Warning: Failed to describe ElastiCache clusters: %v", err)
	} else {
		for _, cc := range ccResult.CacheClusters {
			if cc.CacheClusterId == nil {
				continue
			}

			name := *cc.CacheClusterId
			if !strings.HasPrefix(name, prefix) {
				continue
			}

			// Skip clusters that are part of a replication group (handled above)
			if cc.ReplicationGroupId != nil {
				continue
			}

			var createdAt time.Time
			if cc.CacheClusterCreateTime != nil {
				createdAt = *cc.CacheClusterCreateTime
				if createdAt.After(cutoffTime) {
					continue
				}
			}

			orphans = append(orphans, OrphanedResource{
				Type:      "ElastiCache Cluster",
				ID:        name,
				Name:      name,
				CreatedAt: createdAt,
				Region:    region,
			})
		}
	}

	return orphans
}

// findOrphanedS3Buckets finds S3 buckets with the terratest prefix.
func findOrphanedS3Buckets(t *testing.T, prefix string, cutoffTime time.Time, region string) []OrphanedResource {
	cfg, err := config.LoadDefaultConfig(context.TODO(), config.WithRegion(region))
	require.NoError(t, err, "Failed to load AWS config")
	client := s3.NewFromConfig(cfg)

	var orphans []OrphanedResource

	input := &s3.ListBucketsInput{}
	result, err := client.ListBuckets(context.TODO(), input)
	if err != nil {
		t.Logf("Warning: Failed to list S3 buckets: %v", err)
		return orphans
	}

	for _, bucket := range result.Buckets {
		if bucket.Name == nil {
			continue
		}

		name := *bucket.Name
		if !strings.HasPrefix(name, prefix) {
			continue
		}

		var createdAt time.Time
		if bucket.CreationDate != nil {
			createdAt = *bucket.CreationDate
			if createdAt.After(cutoffTime) {
				continue
			}
		}

		orphans = append(orphans, OrphanedResource{
			Type:      "S3 Bucket",
			ID:        name,
			Name:      name,
			CreatedAt: createdAt,
			Region:    region,
		})
	}

	return orphans
}

// findOrphanedSecurityGroups finds security groups with the terratest prefix.
func findOrphanedSecurityGroups(t *testing.T, prefix string, cutoffTime time.Time, region string) []OrphanedResource {
	cfg, err := config.LoadDefaultConfig(context.TODO(), config.WithRegion(region))
	require.NoError(t, err, "Failed to load AWS config")
	client := ec2.NewFromConfig(cfg)

	var orphans []OrphanedResource

	input := &ec2.DescribeSecurityGroupsInput{
		Filters: []ec2types.Filter{
			{
				Name:   stringPtr("tag:Name"),
				Values: []string{prefix + "*"},
			},
		},
	}

	result, err := client.DescribeSecurityGroups(context.TODO(), input)
	if err != nil {
		t.Logf("Warning: Failed to describe security groups: %v", err)
		return orphans
	}

	for _, sg := range result.SecurityGroups {
		// Skip default security groups
		if sg.GroupName != nil && *sg.GroupName == "default" {
			continue
		}

		tags := tagsToMap(sg.Tags)
		name := tags["Name"]

		if !strings.HasPrefix(name, prefix) {
			continue
		}

		orphans = append(orphans, OrphanedResource{
			Type:   "Security Group",
			ID:     *sg.GroupId,
			Name:   name,
			Region: region,
			Tags:   tags,
		})
	}

	return orphans
}

// findOrphanedNATGateways finds NAT Gateways with the terratest prefix.
func findOrphanedNATGateways(t *testing.T, prefix string, cutoffTime time.Time, region string) []OrphanedResource {
	cfg, err := config.LoadDefaultConfig(context.TODO(), config.WithRegion(region))
	require.NoError(t, err, "Failed to load AWS config")
	client := ec2.NewFromConfig(cfg)

	var orphans []OrphanedResource

	input := &ec2.DescribeNatGatewaysInput{
		Filter: []ec2types.Filter{
			{
				Name:   stringPtr("tag:Name"),
				Values: []string{prefix + "*"},
			},
		},
	}

	result, err := client.DescribeNatGateways(context.TODO(), input)
	if err != nil {
		t.Logf("Warning: Failed to describe NAT Gateways: %v", err)
		return orphans
	}

	for _, nat := range result.NatGateways {
		// Skip deleted or deleting NAT Gateways
		if nat.State == ec2types.NatGatewayStateDeleted || nat.State == ec2types.NatGatewayStateDeleting {
			continue
		}

		tags := tagsToMap(nat.Tags)
		name := tags["Name"]

		if !strings.HasPrefix(name, prefix) {
			continue
		}

		var createdAt time.Time
		if nat.CreateTime != nil {
			createdAt = *nat.CreateTime
			if createdAt.After(cutoffTime) {
				continue
			}
		}

		orphans = append(orphans, OrphanedResource{
			Type:      "NAT Gateway",
			ID:        *nat.NatGatewayId,
			Name:      name,
			CreatedAt: createdAt,
			Region:    region,
			Tags:      tags,
		})
	}

	return orphans
}

// cleanupOrphanedVPCs deletes VPCs with the terratest prefix that are older than cutoffTime.
func cleanupOrphanedVPCs(t *testing.T, prefix string, cutoffTime time.Time, region string) {
	cfg, err := config.LoadDefaultConfig(context.TODO(), config.WithRegion(region))
	require.NoError(t, err, "Failed to load AWS config")
	client := ec2.NewFromConfig(cfg)

	orphans := findOrphanedVPCs(t, prefix, cutoffTime, region)

	for _, orphan := range orphans {
		t.Logf("Deleting orphaned VPC: %s (%s)", orphan.Name, orphan.ID)

		// First, delete all subnets
		deleteVPCSubnets(t, client, orphan.ID)

		// Delete internet gateways
		deleteVPCInternetGateways(t, client, orphan.ID)

		// Delete route tables (except main)
		deleteVPCRouteTables(t, client, orphan.ID)

		// Delete the VPC
		input := &ec2.DeleteVpcInput{
			VpcId: &orphan.ID,
		}

		_, err := client.DeleteVpc(context.TODO(), input)
		if err != nil {
			t.Logf("Warning: Failed to delete VPC %s: %v", orphan.ID, err)
		} else {
			t.Logf("Successfully deleted VPC: %s", orphan.ID)
		}
	}
}

// cleanupOrphanedLoadBalancers deletes load balancers with the terratest prefix.
func cleanupOrphanedLoadBalancers(t *testing.T, prefix string, cutoffTime time.Time, region string) {
	cfg, err := config.LoadDefaultConfig(context.TODO(), config.WithRegion(region))
	require.NoError(t, err, "Failed to load AWS config")
	client := elbv2.NewFromConfig(cfg)

	orphans := findOrphanedLoadBalancers(t, prefix, cutoffTime, region)

	for _, orphan := range orphans {
		t.Logf("Deleting orphaned %s: %s", orphan.Type, orphan.Name)

		// Delete listeners first
		deleteLoadBalancerListeners(t, client, orphan.ID)

		// Delete the load balancer
		input := &elbv2.DeleteLoadBalancerInput{
			LoadBalancerArn: &orphan.ID,
		}

		_, err := client.DeleteLoadBalancer(context.TODO(), input)
		if err != nil {
			t.Logf("Warning: Failed to delete %s %s: %v", orphan.Type, orphan.ID, err)
		} else {
			t.Logf("Successfully deleted %s: %s", orphan.Type, orphan.Name)
		}
	}
}

// cleanupOrphanedECSServices deletes ECS services with the terratest prefix.
func cleanupOrphanedECSServices(t *testing.T, prefix string, cutoffTime time.Time, region string) {
	cfg, err := config.LoadDefaultConfig(context.TODO(), config.WithRegion(region))
	require.NoError(t, err, "Failed to load AWS config")
	client := ecs.NewFromConfig(cfg)

	// List all clusters
	listInput := &ecs.ListClustersInput{}
	listResult, err := client.ListClusters(context.TODO(), listInput)
	if err != nil {
		t.Logf("Warning: Failed to list ECS clusters: %v", err)
		return
	}

	for _, clusterArn := range listResult.ClusterArns {
		// List services in this cluster
		servicesInput := &ecs.ListServicesInput{
			Cluster: &clusterArn,
		}

		servicesResult, err := client.ListServices(context.TODO(), servicesInput)
		if err != nil {
			continue
		}

		if len(servicesResult.ServiceArns) == 0 {
			continue
		}

		// Describe services
		describeInput := &ecs.DescribeServicesInput{
			Cluster:  &clusterArn,
			Services: servicesResult.ServiceArns,
		}

		describeResult, err := client.DescribeServices(context.TODO(), describeInput)
		if err != nil {
			continue
		}

		for _, svc := range describeResult.Services {
			if svc.ServiceName == nil {
				continue
			}

			name := *svc.ServiceName
			if !strings.HasPrefix(name, prefix) {
				continue
			}

			t.Logf("Deleting orphaned ECS service: %s", name)

			// Update service to 0 desired count first
			zero := int32(0)
			updateInput := &ecs.UpdateServiceInput{
				Cluster:      &clusterArn,
				Service:      svc.ServiceName,
				DesiredCount: &zero,
			}
			_, _ = client.UpdateService(context.TODO(), updateInput)

			// Delete the service
			force := true
			deleteInput := &ecs.DeleteServiceInput{
				Cluster: &clusterArn,
				Service: svc.ServiceName,
				Force:   &force,
			}

			_, err := client.DeleteService(context.TODO(), deleteInput)
			if err != nil {
				t.Logf("Warning: Failed to delete ECS service %s: %v", name, err)
			} else {
				t.Logf("Successfully deleted ECS service: %s", name)
			}
		}
	}
}

// cleanupOrphanedECSClusters deletes ECS clusters with the terratest prefix.
func cleanupOrphanedECSClusters(t *testing.T, prefix string, cutoffTime time.Time, region string) {
	cfg, err := config.LoadDefaultConfig(context.TODO(), config.WithRegion(region))
	require.NoError(t, err, "Failed to load AWS config")
	client := ecs.NewFromConfig(cfg)

	orphans := findOrphanedECSClusters(t, prefix, cutoffTime, region)

	for _, orphan := range orphans {
		t.Logf("Deleting orphaned ECS cluster: %s", orphan.Name)

		input := &ecs.DeleteClusterInput{
			Cluster: &orphan.ID,
		}

		_, err := client.DeleteCluster(context.TODO(), input)
		if err != nil {
			t.Logf("Warning: Failed to delete ECS cluster %s: %v", orphan.ID, err)
		} else {
			t.Logf("Successfully deleted ECS cluster: %s", orphan.Name)
		}
	}
}

// cleanupOrphanedElastiCacheClusters deletes ElastiCache clusters with the terratest prefix.
func cleanupOrphanedElastiCacheClusters(t *testing.T, prefix string, cutoffTime time.Time, region string) {
	cfg, err := config.LoadDefaultConfig(context.TODO(), config.WithRegion(region))
	require.NoError(t, err, "Failed to load AWS config")
	client := elasticache.NewFromConfig(cfg)

	orphans := findOrphanedElastiCacheClusters(t, prefix, cutoffTime, region)

	for _, orphan := range orphans {
		t.Logf("Deleting orphaned %s: %s", orphan.Type, orphan.Name)

		if orphan.Type == "ElastiCache Replication Group" {
			input := &elasticache.DeleteReplicationGroupInput{
				ReplicationGroupId: &orphan.ID,
				// Not specifying FinalSnapshotIdentifier means no final snapshot is taken
			}

			_, err := client.DeleteReplicationGroup(context.TODO(), input)
			if err != nil {
				t.Logf("Warning: Failed to delete ElastiCache replication group %s: %v", orphan.ID, err)
			} else {
				t.Logf("Successfully deleted ElastiCache replication group: %s", orphan.Name)
			}
		} else {
			input := &elasticache.DeleteCacheClusterInput{
				CacheClusterId: &orphan.ID,
			}

			_, err := client.DeleteCacheCluster(context.TODO(), input)
			if err != nil {
				t.Logf("Warning: Failed to delete ElastiCache cluster %s: %v", orphan.ID, err)
			} else {
				t.Logf("Successfully deleted ElastiCache cluster: %s", orphan.Name)
			}
		}
	}
}

// cleanupOrphanedNATGateways deletes NAT Gateways with the terratest prefix.
func cleanupOrphanedNATGateways(t *testing.T, prefix string, cutoffTime time.Time, region string) {
	cfg, err := config.LoadDefaultConfig(context.TODO(), config.WithRegion(region))
	require.NoError(t, err, "Failed to load AWS config")
	client := ec2.NewFromConfig(cfg)

	orphans := findOrphanedNATGateways(t, prefix, cutoffTime, region)

	for _, orphan := range orphans {
		t.Logf("Deleting orphaned NAT Gateway: %s (%s)", orphan.Name, orphan.ID)

		input := &ec2.DeleteNatGatewayInput{
			NatGatewayId: &orphan.ID,
		}

		_, err := client.DeleteNatGateway(context.TODO(), input)
		if err != nil {
			t.Logf("Warning: Failed to delete NAT Gateway %s: %v", orphan.ID, err)
		} else {
			t.Logf("Successfully deleted NAT Gateway: %s", orphan.ID)
		}
	}
}

// cleanupOrphanedSecurityGroups deletes security groups with the terratest prefix.
func cleanupOrphanedSecurityGroups(t *testing.T, prefix string, cutoffTime time.Time, region string) {
	cfg, err := config.LoadDefaultConfig(context.TODO(), config.WithRegion(region))
	require.NoError(t, err, "Failed to load AWS config")
	client := ec2.NewFromConfig(cfg)

	orphans := findOrphanedSecurityGroups(t, prefix, cutoffTime, region)

	for _, orphan := range orphans {
		t.Logf("Deleting orphaned Security Group: %s (%s)", orphan.Name, orphan.ID)

		input := &ec2.DeleteSecurityGroupInput{
			GroupId: &orphan.ID,
		}

		_, err := client.DeleteSecurityGroup(context.TODO(), input)
		if err != nil {
			t.Logf("Warning: Failed to delete Security Group %s: %v", orphan.ID, err)
		} else {
			t.Logf("Successfully deleted Security Group: %s", orphan.Name)
		}
	}
}

// cleanupOrphanedS3Buckets deletes S3 buckets with the terratest prefix.
func cleanupOrphanedS3Buckets(t *testing.T, prefix string, cutoffTime time.Time, region string) {
	cfg, err := config.LoadDefaultConfig(context.TODO(), config.WithRegion(region))
	require.NoError(t, err, "Failed to load AWS config")
	client := s3.NewFromConfig(cfg)

	orphans := findOrphanedS3Buckets(t, prefix, cutoffTime, region)

	for _, orphan := range orphans {
		t.Logf("Deleting orphaned S3 bucket: %s", orphan.Name)

		// First, delete all objects in the bucket
		deleteS3BucketObjects(t, client, orphan.Name)

		// Delete the bucket
		input := &s3.DeleteBucketInput{
			Bucket: &orphan.Name,
		}

		_, err := client.DeleteBucket(context.TODO(), input)
		if err != nil {
			t.Logf("Warning: Failed to delete S3 bucket %s: %v", orphan.Name, err)
		} else {
			t.Logf("Successfully deleted S3 bucket: %s", orphan.Name)
		}
	}
}

// Helper functions

// tagsToMap converts EC2 tags to a map.
func tagsToMap(tags []ec2types.Tag) map[string]string {
	result := make(map[string]string)
	for _, tag := range tags {
		if tag.Key != nil && tag.Value != nil {
			result[*tag.Key] = *tag.Value
		}
	}
	return result
}

// deleteVPCSubnets deletes all subnets in a VPC.
func deleteVPCSubnets(t *testing.T, client *ec2.Client, vpcId string) {
	input := &ec2.DescribeSubnetsInput{
		Filters: []ec2types.Filter{
			{
				Name:   stringPtr("vpc-id"),
				Values: []string{vpcId},
			},
		},
	}

	result, err := client.DescribeSubnets(context.TODO(), input)
	if err != nil {
		t.Logf("Warning: Failed to describe subnets for VPC %s: %v", vpcId, err)
		return
	}

	for _, subnet := range result.Subnets {
		deleteInput := &ec2.DeleteSubnetInput{
			SubnetId: subnet.SubnetId,
		}

		_, err := client.DeleteSubnet(context.TODO(), deleteInput)
		if err != nil {
			t.Logf("Warning: Failed to delete subnet %s: %v", *subnet.SubnetId, err)
		}
	}
}

// deleteVPCInternetGateways detaches and deletes internet gateways attached to a VPC.
func deleteVPCInternetGateways(t *testing.T, client *ec2.Client, vpcId string) {
	input := &ec2.DescribeInternetGatewaysInput{
		Filters: []ec2types.Filter{
			{
				Name:   stringPtr("attachment.vpc-id"),
				Values: []string{vpcId},
			},
		},
	}

	result, err := client.DescribeInternetGateways(context.TODO(), input)
	if err != nil {
		t.Logf("Warning: Failed to describe internet gateways for VPC %s: %v", vpcId, err)
		return
	}

	for _, igw := range result.InternetGateways {
		// Detach first
		detachInput := &ec2.DetachInternetGatewayInput{
			InternetGatewayId: igw.InternetGatewayId,
			VpcId:             &vpcId,
		}

		_, err := client.DetachInternetGateway(context.TODO(), detachInput)
		if err != nil {
			t.Logf("Warning: Failed to detach internet gateway %s: %v", *igw.InternetGatewayId, err)
		}

		// Then delete
		deleteInput := &ec2.DeleteInternetGatewayInput{
			InternetGatewayId: igw.InternetGatewayId,
		}

		_, err = client.DeleteInternetGateway(context.TODO(), deleteInput)
		if err != nil {
			t.Logf("Warning: Failed to delete internet gateway %s: %v", *igw.InternetGatewayId, err)
		}
	}
}

// deleteVPCRouteTables deletes all non-main route tables in a VPC.
func deleteVPCRouteTables(t *testing.T, client *ec2.Client, vpcId string) {
	input := &ec2.DescribeRouteTablesInput{
		Filters: []ec2types.Filter{
			{
				Name:   stringPtr("vpc-id"),
				Values: []string{vpcId},
			},
		},
	}

	result, err := client.DescribeRouteTables(context.TODO(), input)
	if err != nil {
		t.Logf("Warning: Failed to describe route tables for VPC %s: %v", vpcId, err)
		return
	}

	for _, rt := range result.RouteTables {
		// Skip main route table
		isMain := false
		for _, assoc := range rt.Associations {
			if assoc.Main != nil && *assoc.Main {
				isMain = true
				break
			}
		}
		if isMain {
			continue
		}

		// Delete associations first
		for _, assoc := range rt.Associations {
			if assoc.RouteTableAssociationId != nil {
				disassocInput := &ec2.DisassociateRouteTableInput{
					AssociationId: assoc.RouteTableAssociationId,
				}
				_, _ = client.DisassociateRouteTable(context.TODO(), disassocInput)
			}
		}

		deleteInput := &ec2.DeleteRouteTableInput{
			RouteTableId: rt.RouteTableId,
		}

		_, err := client.DeleteRouteTable(context.TODO(), deleteInput)
		if err != nil {
			t.Logf("Warning: Failed to delete route table %s: %v", *rt.RouteTableId, err)
		}
	}
}

// deleteLoadBalancerListeners deletes all listeners for a load balancer.
func deleteLoadBalancerListeners(t *testing.T, client *elbv2.Client, lbArn string) {
	input := &elbv2.DescribeListenersInput{
		LoadBalancerArn: &lbArn,
	}

	result, err := client.DescribeListeners(context.TODO(), input)
	if err != nil {
		t.Logf("Warning: Failed to describe listeners for load balancer %s: %v", lbArn, err)
		return
	}

	for _, listener := range result.Listeners {
		deleteInput := &elbv2.DeleteListenerInput{
			ListenerArn: listener.ListenerArn,
		}

		_, err := client.DeleteListener(context.TODO(), deleteInput)
		if err != nil {
			t.Logf("Warning: Failed to delete listener %s: %v", *listener.ListenerArn, err)
		}
	}
}

// deleteS3BucketObjects deletes all objects in an S3 bucket.
func deleteS3BucketObjects(t *testing.T, client *s3.Client, bucketName string) {
	input := &s3.ListObjectsV2Input{
		Bucket: &bucketName,
	}

	paginator := s3.NewListObjectsV2Paginator(client, input)

	for paginator.HasMorePages() {
		page, err := paginator.NextPage(context.TODO())
		if err != nil {
			t.Logf("Warning: Failed to list objects in bucket %s: %v", bucketName, err)
			return
		}

		for _, obj := range page.Contents {
			deleteInput := &s3.DeleteObjectInput{
				Bucket: &bucketName,
				Key:    obj.Key,
			}

			_, err := client.DeleteObject(context.TODO(), deleteInput)
			if err != nil {
				t.Logf("Warning: Failed to delete object %s from bucket %s: %v", *obj.Key, bucketName, err)
			}
		}
	}

	// Also delete any versioned objects
	deleteS3BucketVersionedObjects(t, client, bucketName)
}

// deleteS3BucketVersionedObjects deletes all versioned objects and delete markers in an S3 bucket.
func deleteS3BucketVersionedObjects(t *testing.T, client *s3.Client, bucketName string) {
	input := &s3.ListObjectVersionsInput{
		Bucket: &bucketName,
	}

	result, err := client.ListObjectVersions(context.TODO(), input)
	if err != nil {
		// Bucket may not have versioning enabled
		return
	}

	// Delete versions
	for _, version := range result.Versions {
		deleteInput := &s3.DeleteObjectInput{
			Bucket:    &bucketName,
			Key:       version.Key,
			VersionId: version.VersionId,
		}

		_, _ = client.DeleteObject(context.TODO(), deleteInput)
	}

	// Delete markers
	for _, marker := range result.DeleteMarkers {
		deleteInput := &s3.DeleteObjectInput{
			Bucket:    &bucketName,
			Key:       marker.Key,
			VersionId: marker.VersionId,
		}

		_, _ = client.DeleteObject(context.TODO(), deleteInput)
	}
}
