// This file tests model-facing create_task argument normalization.
package toolargs

import (
	"encoding/json"
	"testing"
)

// TestDecodeCreateTaskRequestCoercesLegacyModelMetadata verifies tolerant scalar parsing.
func TestDecodeCreateTaskRequestCoercesLegacyModelMetadata(t *testing.T) {
	payload, err := json.Marshal(map[string]any{
		"title":            "Buy Milk",
		"description":      "Purchase milk.",
		"status":           "pending",
		"priority":         "medium",
		"energy_required":  1,
		"effort":           5,
		"urgency":          "low",
		"value":            10,
		"estimate_minutes": 10,
	})
	if err != nil {
		t.Fatalf("marshal payload: %v", err)
	}

	req, err := DecodeCreateTaskRequest(payload)
	if err != nil {
		t.Fatalf("decode create task request: %v", err)
	}

	if req.Title != "Buy Milk" || req.Description != "Purchase milk." {
		t.Fatalf("task text = %q/%q, want decoded title and description", req.Title, req.Description)
	}
	if req.Status != "open" || req.Priority != "normal" {
		t.Fatalf("status/priority = %q/%q, want open/normal", req.Status, req.Priority)
	}
	if req.EnergyRequired != "1" || req.Urgency != 0.25 || req.Value != 1 {
		t.Fatalf("metadata = energy %q urgency %.2f value %.2f, want coerced values", req.EnergyRequired, req.Urgency, req.Value)
	}
}

// TestDecodeCreateTaskRequestRecoversMalformedKeys verifies model-emitted field keys are repaired.
func TestDecodeCreateTaskRequestRecoversMalformedKeys(t *testing.T) {
	payload, err := json.Marshal(map[string]any{
		`title:<|"|>Buy milk<|"|>`:                         nil,
		`description:<|"|>Buy milk<|"|>`:                   nil,
		`idempotency_key:<|"|>agent_awesome:session:<|"|>`: nil,
	})
	if err != nil {
		t.Fatalf("marshal payload: %v", err)
	}

	req, err := DecodeCreateTaskRequest(payload)
	if err != nil {
		t.Fatalf("decode create task request: %v", err)
	}

	if req.Title != "Buy milk" || req.Description != "Buy milk" {
		t.Fatalf("task text = %q/%q, want recovered fields", req.Title, req.Description)
	}
	if req.IdempotencyKey != "agent_awesome:session:" {
		t.Fatalf("idempotency key = %q, want recovered key", req.IdempotencyKey)
	}
}
