// This file tests memory firewall policy parsing and authorization semantics.
package service

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"memory/internal/memory/domain"
)

// TestFirewallPolicyAuthorizesReadAndWrite verifies rule matching semantics.
func TestFirewallPolicyAuthorizesReadAndWrite(t *testing.T) {
	policy, err := NormalizeFirewallPolicy(FirewallPolicy{
		Firewalls: []FirewallRule{
			{
				Firewall: domain.FirewallUser,
				Readers:  []string{" Reader ", "reader"},
				Writers:  []string{"Writer"},
			},
		},
	})
	if err != nil {
		t.Fatalf("normalize policy: %v", err)
	}
	if !policy.AllowsRead("reader", domain.FirewallUser) {
		t.Fatal("reader should read user firewall")
	}
	if !policy.AllowsRead("writer", domain.FirewallUser) {
		t.Fatal("writer should read user firewall")
	}
	if policy.AllowsWrite("reader", domain.FirewallUser) {
		t.Fatal("reader should not write user firewall")
	}
	if !policy.AllowsWrite("writer", domain.FirewallUser) {
		t.Fatal("writer should write user firewall")
	}
	if policy.AllowsRead("reader", domain.FirewallProject) {
		t.Fatal("unlisted firewall should default deny")
	}
}

// TestLoadFirewallPolicyFile verifies policy JSON can be loaded from disk.
func TestLoadFirewallPolicyFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "firewalls.json")
	content, err := json.Marshal(FirewallPolicy{
		Firewalls: []FirewallRule{
			{Firewall: domain.Firewall("acme-client"), Readers: []string{"pat"}},
		},
	})
	if err != nil {
		t.Fatalf("marshal policy: %v", err)
	}
	if err := os.WriteFile(path, content, 0o600); err != nil {
		t.Fatalf("write policy: %v", err)
	}
	policy, err := LoadFirewallPolicyFile(path)
	if err != nil {
		t.Fatalf("load policy: %v", err)
	}
	if policy == nil || !policy.AllowsRead("PAT", domain.Firewall("acme-client")) {
		t.Fatalf("policy = %#v, want case-insensitive read grant", policy)
	}
}
