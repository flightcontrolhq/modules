package test

import (
	"testing"
	"time"

	"github.com/flightcontrolhq/modules/test/helpers"
)

// TestCleanupOrphanedResources finds and deletes all Terratest resources.
// It will delete ALL resources with the "terratest-" prefix regardless of age.
func TestCleanupOrphanedResources(t *testing.T) {
	region := helpers.GetAwsRegion()
	prefix := helpers.DefaultTerratestPrefix

	t.Logf("Starting cleanup of all terratest resources in region %s", region)
	t.Logf("Prefix: %s", prefix)

	// First, find and log all orphaned resources
	orphans := helpers.FindAllOrphanedResources(t, prefix, region)
	t.Logf("Found %d terratest resources", len(orphans))

	for _, orphan := range orphans {
		if orphan.CreatedAt.IsZero() {
			t.Logf("Found %s: %s (%s)", orphan.Type, orphan.Name, orphan.ID)
		} else {
			t.Logf("Found %s: %s (%s) - Created: %s",
				orphan.Type, orphan.Name, orphan.ID, orphan.CreatedAt.Format(time.RFC3339))
		}
	}

	// Now cleanup
	if len(orphans) > 0 {
		t.Log("Starting cleanup...")
		helpers.CleanupAllOrphanedResources(t, prefix, region)
		t.Log("Cleanup complete")
	} else {
		t.Log("No terratest resources found, nothing to clean up")
	}
}

// TestCleanupOrphanedResourcesDryRun finds Terratest resources but does not delete them.
// This is useful for checking what resources would be deleted without actually removing them.
func TestCleanupOrphanedResourcesDryRun(t *testing.T) {
	region := helpers.GetAwsRegion()
	prefix := helpers.DefaultTerratestPrefix

	t.Logf("DRY RUN: Finding terratest resources in region %s", region)
	t.Logf("Prefix: %s", prefix)

	orphans := helpers.FindAllOrphanedResources(t, prefix, region)
	t.Logf("Found %d terratest resources that would be deleted:", len(orphans))

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
		t.Log("No terratest resources found")
	} else {
		t.Logf("\nDRY RUN complete. %d resources would be deleted.", len(orphans))
	}
}
