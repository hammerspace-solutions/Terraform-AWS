package test

import (
	"os"
	"testing"

	"github.com/stretchr/testify/require"
)

// getRequiredEnvVar reads a required environment variable and fails the test if it's not set.
// This helper is now centralized here to be used by all tests in the package.
func getRequiredEnvVar(t *testing.T, key string) string {
	value, found := os.LookupEnv(key)
	require.True(t, found, "Environment variable '%s' must be set for this test", key)
	return value
}
