package test

import (
	"os"
	"strconv"
	"testing"
	"time"

	"github.com/flightcontrolhq/modules/test/helpers"
)

// TestCleanupOrphanedResources finds and deletes orphaned Terratest resources.
// This test is intended to be run by the scheduled cleanup workflow.
// It will delete resources with the "terratest-" prefix that are older than
// CLEANUP_MAX_AGE_HOURS (default 24 hours).
func TestCleanupOrphanedResources(t *testing.T) {
	region := helpers.GetAwsRegion()
	prefix := helpers.DefaultTerratestPrefix
	maxAge := getMaxAge()

	t.Logf("Starting cleanup of orphaned resources in region %s", region)
	t.Logf("Prefix: %s, Max Age: %s", prefix, maxAge)

	// First, find and log all orphaned resources
	orphans := helpers.FindOrphanedResourcesWithAge(t, prefix, maxAge, region)
	t.Logf("Found %d orphaned resources", len(orphans))

	for _, orphan := range orphans {
		t.Logf("Found orphaned %s: %s (%s) - Created: %s",
			orphan.Type, orphan.Name, orphan.ID, orphan.CreatedAt.Format(time.RFC3339))
	}

	// Now cleanup
	if len(orphans) > 0 {
		t.Log("Starting cleanup...")
		helpers.CleanupOrphanedResourcesWithAge(t, prefix, maxAge, region)
		t.Log("Cleanup complete")
	} else {
		t.Log("No orphaned resources found, nothing to clean up")
	}
}

// TestCleanupOrphanedResourcesDryRun finds orphaned Terratest resources but does not delete them.
// This is useful for checking what resources would be deleted without actually removing them.
func TestCleanupOrphanedResourcesDryRun(t *testing.T) {
	region := helpers.GetAwsRegion()
	prefix := helpers.DefaultTerratestPrefix
	maxAge := getMaxAge()

	t.Logf("DRY RUN: Finding orphaned resources in region %s", region)
	t.Logf("Prefix: %s, Max Age: %s", prefix, maxAge)

	orphans := helpers.FindOrphanedResourcesWithAge(t, prefix, maxAge, region)
	t.Logf("Found %d orphaned resources that would be deleted:", len(orphans))

	// Group by type for cleaner output
	byType := make(map[string][]helpers.OrphanedResource)
	for _, orphan := range orphans {
		byType[orphan.Type] = append(byType[orphan.Type], orphan)
	}

	for resourceType, resources := range byType {
		t.Logf("\n=== %s (%d) ===", resourceType, len(resources))
		for _, r := range resources {
			if r.CreatedAt.IsZero() {
				t.Logf("  - %s (%s)", r.Name, r.ID)
			} else {
				t.Logf("  - %s (%s) - Created: %s", r.Name, r.ID, r.CreatedAt.Format(time.RFC3339))
			}
		}
	}

	if len(orphans) == 0 {
		t.Log("No orphaned resources found")
	} else {
		t.Logf("\nDRY RUN complete. %d resources would be deleted.", len(orphans))
	}
}

// getMaxAge returns the max age for orphaned resources from environment variable
// or defaults to 24 hours.
func getMaxAge() time.Duration {
	maxAgeHours := os.Getenv("CLEANUP_MAX_AGE_HOURS")
	if maxAgeHours == "" {
		return helpers.DefaultMaxAge
	}

	hours, err := strconv.Atoi(maxAgeHours)
	if err != nil {
		return helpers.DefaultMaxAge
	}

	return time.Duration(hours) * time.Hour
}
