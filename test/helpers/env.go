// Package helpers provides shared helper functions for Terratest tests.
package helpers

import (
	"os"
	"path/filepath"
	"runtime"

	"github.com/joho/godotenv"
)

// init automatically loads environment variables from .env.test file
// when the test package is initialized. This runs before any tests execute.
func init() {
	LoadEnvFile()
}

// LoadEnvFile attempts to load environment variables from .env.test file.
// It looks for the file in the test directory (parent of helpers/).
// If the file doesn't exist, it silently continues (allowing CI/CD to use
// environment variables directly).
func LoadEnvFile() {
	// Get the directory where this source file is located
	_, currentFile, _, ok := runtime.Caller(0)
	if !ok {
		return
	}

	// Navigate from helpers/ to test/ directory
	helpersDir := filepath.Dir(currentFile)
	testDir := filepath.Dir(helpersDir)

	// Try to load .env.test from the test directory
	envFile := filepath.Join(testDir, ".env.test")
	if _, err := os.Stat(envFile); err == nil {
		_ = godotenv.Load(envFile)
	}
}

// GetEnvOrDefault returns the value of an environment variable or a default value.
func GetEnvOrDefault(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

// RequireEnv returns the value of an environment variable or panics if not set.
func RequireEnv(key string) string {
	value := os.Getenv(key)
	if value == "" {
		panic("Required environment variable not set: " + key)
	}
	return value
}
