// Package helpers provides utility functions for Terratest tests.
package helpers

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

// HasTag checks if the given tags map contains a specific key-value pair.
func HasTag(tags map[string]string, key, value string) bool {
	if tags == nil {
		return false
	}
	tagValue, exists := tags[key]
	return exists && tagValue == value
}

// ValidateRequiredTags checks if all required tag keys are present in the tags map.
// Returns true if all required tags are present, false otherwise.
// It logs assertion failures for each missing tag but does not fail the test.
func ValidateRequiredTags(t *testing.T, tags map[string]string, required []string) bool {
	if tags == nil {
		t.Log("Tags map is nil")
		return false
	}

	allPresent := true
	for _, key := range required {
		if _, exists := tags[key]; !exists {
			assert.Fail(t, "Missing required tag", "Tag '%s' is required but not present", key)
			allPresent = false
		}
	}
	return allPresent
}

// ValidateTerratestTags checks that the standard Terratest tags are present.
// It verifies that Environment=terratest and ManagedBy=terratest are set.
// This function uses assertions that will fail the test if tags are missing or incorrect.
func ValidateTerratestTags(t *testing.T, tags map[string]string) {
	assert.NotNil(t, tags, "Tags map should not be nil")

	assert.True(t, HasTag(tags, "Environment", "terratest"),
		"Expected tag Environment=terratest, got Environment=%s", tags["Environment"])

	assert.True(t, HasTag(tags, "ManagedBy", "terratest"),
		"Expected tag ManagedBy=terratest, got ManagedBy=%s", tags["ManagedBy"])
}
