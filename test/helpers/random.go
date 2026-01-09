// Package helpers provides utility functions for Terratest tests.
package helpers

import (
	"fmt"
	"strings"

	"github.com/gruntwork-io/terratest/modules/random"
)

// UniqueResourceName generates a unique resource name with the format "terratest-{prefix}-{uniqueId}".
// The prefix should describe the resource type (e.g., "vpc", "alb", "ecs").
// The unique ID is generated using terratest's random.UniqueId() function.
func UniqueResourceName(prefix string) string {
	return fmt.Sprintf("terratest-%s-%s", prefix, strings.ToLower(random.UniqueId()))
}

// UniqueId returns a random unique identifier using terratest's random.UniqueId().
// This is useful when you need just the unique ID without the terratest prefix.
func UniqueId() string {
	return strings.ToLower(random.UniqueId())
}
