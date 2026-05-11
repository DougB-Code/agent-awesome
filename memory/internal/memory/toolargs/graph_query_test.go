// This file tests graph query tool intent guards.
package toolargs

import (
	"strings"
	"testing"

	"memory/internal/memory/domain"
)

// TestEnsureReadOnlyGraphQueryRejectsMutation verifies read tools cannot write.
func TestEnsureReadOnlyGraphQueryRejectsMutation(t *testing.T) {
	err := EnsureReadOnlyGraphQuery(domain.GraphQueryRequest{Query: `INSERT NODE task SET title = "Review"`})
	if err == nil || !strings.Contains(err.Error(), "read-only") {
		t.Fatalf("error = %v, want read-only guidance", err)
	}
}

// TestEnsureMutatingGraphQueryRejectsRead verifies mutation tools cannot read.
func TestEnsureMutatingGraphQueryRejectsRead(t *testing.T) {
	err := EnsureMutatingGraphQuery(domain.GraphQueryRequest{Query: "FIND task RETURN id LIMIT 1"})
	if err == nil || !strings.Contains(err.Error(), "INSERT, SET, or DELETE") {
		t.Fatalf("error = %v, want mutation guidance", err)
	}
}
