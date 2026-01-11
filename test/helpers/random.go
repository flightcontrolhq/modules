// Package helpers provides utility functions for Terratest tests.
package helpers

import (
	"fmt"
	"strings"

	"github.com/gruntwork-io/terratest/modules/random"
)

// UniqueResourceName generates a unique resource name with the format "tt-{prefix}-{uniqueId}".
// The prefix should describe the resource type (e.g., "vpc", "alb", "ecs").
// The unique ID is generated using terratest's random.UniqueId() function.
// Note: Using "tt-" prefix (instead of "terratest-") to keep names short and comply with
// AWS resource name length limits (e.g., ALB max 32 chars, VPC S3 bucket max 63 chars).
func UniqueResourceName(prefix string) string {
	return fmt.Sprintf("tt-%s-%s", prefix, strings.ToLower(random.UniqueId()))
}

// UniqueId returns a random unique identifier using terratest's random.UniqueId().
// This is useful when you need just the unique ID without the terratest prefix.
func UniqueId() string {
	return strings.ToLower(random.UniqueId())
}
