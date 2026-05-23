// This file tests shared HTTP JSON request helpers.
package httpjson

import (
	"errors"
	"net/http/httptest"
	"strings"
	"testing"
)

// TestDecodeBoundedRejectsTrailingJSONValue verifies malformed multi-value
// request bodies are rejected instead of partially decoded.
func TestDecodeBoundedRejectsTrailingJSONValue(t *testing.T) {
	req := httptest.NewRequest("POST", "/", strings.NewReader(`{"name":"ok"}{"name":"ignored"}`))
	rec := httptest.NewRecorder()
	var target struct {
		Name string `json:"name"`
	}

	err := DecodeBounded(rec, req, 1<<20, &target)
	if err == nil {
		t.Fatalf("DecodeBounded() error = nil, want trailing value error")
	}
	if !strings.Contains(err.Error(), "only one JSON value") {
		t.Fatalf("DecodeBounded() error = %v, want single-value error", err)
	}
}

// TestDecodeBoundedAllowsTrailingWhitespace verifies valid JSON bodies can keep
// insignificant whitespace after the single value.
func TestDecodeBoundedAllowsTrailingWhitespace(t *testing.T) {
	req := httptest.NewRequest("POST", "/", strings.NewReader("{\"name\":\"ok\"}\n\t "))
	rec := httptest.NewRecorder()
	var target struct {
		Name string `json:"name"`
	}

	if err := DecodeBounded(rec, req, 1<<20, &target); err != nil {
		t.Fatalf("DecodeBounded() error = %v", err)
	}
	if target.Name != "ok" {
		t.Fatalf("target.Name = %q, want ok", target.Name)
	}
}

// TestDecodeBoundedReportsPayloadTooLarge verifies the helper preserves the
// exported sentinel for oversized request bodies.
func TestDecodeBoundedReportsPayloadTooLarge(t *testing.T) {
	req := httptest.NewRequest("POST", "/", strings.NewReader(`{"name":"too-large"}`))
	rec := httptest.NewRecorder()
	var target struct {
		Name string `json:"name"`
	}

	err := DecodeBounded(rec, req, 8, &target)
	if !errors.Is(err, ErrPayloadTooLarge) {
		t.Fatalf("DecodeBounded() error = %v, want ErrPayloadTooLarge", err)
	}
}
