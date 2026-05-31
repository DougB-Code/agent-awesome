// This file tests Runtime Target service behavior.
package targets

import (
	"context"
	"path/filepath"
	"testing"
	"time"
)

// TestRegisterLocalTargetPersistsCapabilityInventory verifies local auto-registration.
func TestRegisterLocalTargetPersistsCapabilityInventory(t *testing.T) {
	ctx := context.Background()
	store, err := OpenStore(ctx, filepath.Join(t.TempDir(), "targets.db"))
	if err != nil {
		t.Fatalf("OpenStore() error = %v", err)
	}
	defer store.Close()
	service := NewService(store)

	target, err := service.RegisterLocalTarget(ctx, LocalRegistration{
		Version:      "test-version",
		Capabilities: []string{"command:go_test_all", "runbook_action:data.assert", "command:go_test_all"},
	})
	if err != nil {
		t.Fatalf("RegisterLocalTarget() error = %v", err)
	}
	if target.ID != LocalTargetID || target.Name != "This computer" {
		t.Fatalf("target identity = %#v, want local This computer", target)
	}
	if target.Status != TargetStatusHealthy {
		t.Fatalf("target status = %q, want healthy", target.Status)
	}
	if got, want := target.Capabilities, []string{"command:go_test_all", "runbook_action:data.assert"}; !equalStrings(got, want) {
		t.Fatalf("capabilities = %#v, want %#v", got, want)
	}

	secretRefCount := 2
	updated, err := service.UpdateTarget(ctx, LocalTargetID, TargetUpdateRequest{
		AllowedCodebaseIDs: []string{"agent_awesome", "agent_awesome", "other"},
		SecretRefCount:     &secretRefCount,
	})
	if err != nil {
		t.Fatalf("UpdateTarget() error = %v", err)
	}
	if got, want := updated.AllowedCodebaseIDs, []string{"agent_awesome", "other"}; !equalStrings(got, want) {
		t.Fatalf("allowed codebases = %#v, want %#v", got, want)
	}
	metadata, err := service.SecretMetadata(ctx, LocalTargetID)
	if err != nil {
		t.Fatalf("SecretMetadata() error = %v", err)
	}
	if metadata.Count != 2 {
		t.Fatalf("secret count = %d, want 2", metadata.Count)
	}
}

// TestTargetHealthAndLogs verifies status routes have backing data.
func TestTargetHealthAndLogs(t *testing.T) {
	ctx := context.Background()
	store, err := OpenStore(ctx, filepath.Join(t.TempDir(), "targets.db"))
	if err != nil {
		t.Fatalf("OpenStore() error = %v", err)
	}
	defer store.Close()
	service := NewService(store)
	if _, err := service.RegisterLocalTarget(ctx, LocalRegistration{Version: "test"}); err != nil {
		t.Fatalf("RegisterLocalTarget() error = %v", err)
	}

	health, err := service.Health(ctx, LocalTargetID)
	if err != nil {
		t.Fatalf("Health() error = %v", err)
	}
	if health.Status != TargetStatusHealthy || health.CheckedAt == "" {
		t.Fatalf("health = %#v, want healthy with checked timestamp", health)
	}
	logs, err := service.Logs(ctx, LocalTargetID)
	if err != nil {
		t.Fatalf("Logs() error = %v", err)
	}
	if len(logs) == 0 || logs[0].Message != "local target heartbeat" {
		t.Fatalf("logs = %#v, want heartbeat log", logs)
	}
}

// TestPairingTokenRegistersPairedTarget verifies signed scoped target pairing.
func TestPairingTokenRegistersPairedTarget(t *testing.T) {
	ctx := context.Background()
	store, err := OpenStore(ctx, filepath.Join(t.TempDir(), "targets.db"))
	if err != nil {
		t.Fatalf("OpenStore() error = %v", err)
	}
	defer store.Close()
	service := NewService(store)

	invite, err := service.IssuePairingToken(ctx, PairingTokenRequest{
		Name:               "Build laptop",
		Kind:               TargetKindLAN,
		AllowedCodebaseIDs: []string{"agent_awesome"},
		Capabilities:       []string{"command:go_test_all"},
		SecretRefCount:     1,
		ExpiresInSeconds:   60,
	})
	if err != nil {
		t.Fatalf("IssuePairingToken() error = %v", err)
	}
	if invite.Token == "" || invite.TargetID == "" || invite.ExpiresAt == "" {
		t.Fatalf("invite = %#v, want token, target id, and expiry", invite)
	}
	target, err := service.RegisterPairedTarget(ctx, PairedRegistration{
		Token:        invite.Token,
		Version:      "test-version",
		Capabilities: []string{"mcp:sourcecontrol"},
		OS:           "linux/amd64",
		Hostname:     "build-laptop",
	})
	if err != nil {
		t.Fatalf("RegisterPairedTarget() error = %v", err)
	}
	if target.ID != invite.TargetID || target.Kind != TargetKindLAN || target.Name != "Build laptop" {
		t.Fatalf("target = %#v, want paired target identity", target)
	}
	if got, want := target.AllowedCodebaseIDs, []string{"agent_awesome"}; !equalStrings(got, want) {
		t.Fatalf("allowed codebases = %#v, want %#v", got, want)
	}
	if got, want := target.Capabilities, []string{"command:go_test_all", "mcp:sourcecontrol"}; !equalStrings(got, want) {
		t.Fatalf("capabilities = %#v, want %#v", got, want)
	}
	if _, err := service.RegisterPairedTarget(ctx, PairedRegistration{Token: invite.Token + "x"}); err == nil {
		t.Fatalf("RegisterPairedTarget() tampered token error = nil, want error")
	}
	expiredToken, err := service.signPairingPayload(ctx, pairingTokenPayload{
		TargetID:      "lan_expired",
		Name:          "Expired laptop",
		Kind:          TargetKindLAN,
		ExpiresAtUnix: time.Now().UTC().Add(-time.Minute).Unix(),
	})
	if err != nil {
		t.Fatalf("signPairingPayload() error = %v", err)
	}
	if _, err := service.RegisterPairedTarget(ctx, PairedRegistration{Token: expiredToken}); err == nil {
		t.Fatalf("RegisterPairedTarget() expired token error = nil, want error")
	}
}

// equalStrings compares string slices without pulling extra test helpers.
func equalStrings(left []string, right []string) bool {
	if len(left) != len(right) {
		return false
	}
	for index := range left {
		if left[index] != right[index] {
			return false
		}
	}
	return true
}
