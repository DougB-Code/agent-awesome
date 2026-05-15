// This file tests model-facing create_task argument normalization.
package toolargs

import (
	"encoding/json"
	"testing"
)

// TestDecodeCreateTaskRequestReadsModelPayload verifies the create_task schema fields.
func TestDecodeCreateTaskRequestReadsModelPayload(t *testing.T) {
	payload, err := json.Marshal(map[string]any{
		"title":           "Buy Milk",
		"description":     "Purchase milk.",
		"priority":        "medium",
		"topics":          []string{"Errands", "errands"},
		"idempotency_key": "buy-milk",
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
	if req.Priority != "normal" {
		t.Fatalf("priority = %q, want normal", req.Priority)
	}
	if len(req.Topics) != 1 || req.Topics[0] != "errands" {
		t.Fatalf("topics = %#v, want normalized errands", req.Topics)
	}
	if req.IdempotencyKey != "buy-milk" {
		t.Fatalf("idempotency key = %q, want buy-milk", req.IdempotencyKey)
	}
}
