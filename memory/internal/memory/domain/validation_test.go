// This file tests memory domain request normalization and validation.
package domain

import "testing"

// TestNormalizeCaptureRequestDefaults verifies safe write defaults.
func TestNormalizeCaptureRequestDefaults(t *testing.T) {
	req, err := NormalizeCaptureRequest(CaptureRequest{Content: " remember this ", IdempotencyKey: " key "})
	if err != nil {
		t.Fatalf("normalize capture: %v", err)
	}
	if req.Kind != KindDocument {
		t.Fatalf("kind = %q, want %q", req.Kind, KindDocument)
	}
	if req.Firewall != FirewallUser {
		t.Fatalf("firewall = %q, want %q", req.Firewall, FirewallUser)
	}
	if req.TrustLevel != TrustSourceOriginal {
		t.Fatalf("trust = %q, want %q", req.TrustLevel, TrustSourceOriginal)
	}
	if req.Sensitivity != SensitivityPrivate {
		t.Fatalf("sensitivity = %q, want %q", req.Sensitivity, SensitivityPrivate)
	}
	if req.IdempotencyKey != "key" {
		t.Fatalf("idempotency key = %q, want trimmed key", req.IdempotencyKey)
	}
}

// TestNormalizeCaptureRequestRejectsInvalidVocabulary verifies controlled terms.
func TestNormalizeCaptureRequestRejectsInvalidVocabulary(t *testing.T) {
	_, err := NormalizeCaptureRequest(CaptureRequest{Content: "x", Kind: Kind("unsupported_blob")})
	if err == nil {
		t.Fatal("expected invalid kind error")
	}
	if _, err := NormalizeCaptureRequest(CaptureRequest{Content: "x", Firewall: Firewall("bad firewall!")}); err == nil {
		t.Fatal("expected invalid firewall error")
	}
	req, err := NormalizeCaptureRequest(CaptureRequest{Content: "x", Firewall: Firewall("acme-client")})
	if err != nil {
		t.Fatalf("custom firewall rejected: %v", err)
	}
	if req.Firewall != Firewall("acme-client") {
		t.Fatalf("firewall = %q, want custom firewall", req.Firewall)
	}
}

// TestNormalizeRetrievalQuerySensitivityDefault verifies restricted records are explicit.
func TestNormalizeRetrievalQuerySensitivityDefault(t *testing.T) {
	query, err := NormalizeRetrievalQuery(RetrievalQuery{})
	if err != nil {
		t.Fatalf("normalize query: %v", err)
	}
	for _, sensitivity := range query.AllowedSensitivities {
		if sensitivity == SensitivityRestricted {
			t.Fatal("restricted sensitivity should not be included by default")
		}
	}
}

// TestNormalizeRetrievalQueryDefaultsAndRejectsInvalidFilters verifies read safety.
func TestNormalizeRetrievalQueryDefaultsAndRejectsInvalidFilters(t *testing.T) {
	query, err := NormalizeRetrievalQuery(RetrievalQuery{
		Actor:                "  user  ",
		Topics:               []string{" Reporting ", "reporting"},
		AllowedSensitivities: []Sensitivity{SensitivityPublic},
		Limit:                250,
	})
	if err != nil {
		t.Fatalf("normalize query: %v", err)
	}
	if query.Actor != "user" || query.Firewall != FirewallUser {
		t.Fatalf("actor/firewall = %q/%q, want user/%q", query.Actor, query.Firewall, FirewallUser)
	}
	if query.Firewall != FirewallUser {
		t.Fatalf("firewall = %q, want %q", query.Firewall, FirewallUser)
	}
	if query.IncludeGlobal {
		t.Fatal("include_global should default to false")
	}
	if len(query.Topics) != 1 || query.Topics[0] != "reporting" {
		t.Fatalf("topics = %#v, want normalized reporting", query.Topics)
	}
	if query.Limit != 20 {
		t.Fatalf("limit = %d, want default 20", query.Limit)
	}
	if _, err := NormalizeRetrievalQuery(RetrievalQuery{Kinds: []Kind{Kind("bad")}}); err == nil {
		t.Fatal("expected invalid kind error")
	}
	if _, err := NormalizeRetrievalQuery(RetrievalQuery{AllowedSensitivities: []Sensitivity{Sensitivity("secret")}}); err == nil {
		t.Fatal("expected invalid sensitivity error")
	}
	query, err = NormalizeRetrievalQuery(RetrievalQuery{Firewall: Firewall("acme-client")})
	if err != nil {
		t.Fatalf("retrieval firewall rejected: %v", err)
	}
	if query.Firewall != Firewall("acme-client") {
		t.Fatalf("retrieval firewall = %q, want acme-client", query.Firewall)
	}
}

// TestNormalizeGraphQueryRequestDefaultsAndRejectsInvalidPolicy verifies graph reads are policy-bound.
func TestNormalizeGraphQueryRequestDefaultsAndRejectsInvalidPolicy(t *testing.T) {
	req, err := NormalizeGraphQueryRequest(GraphQueryRequest{Actor: "  user  ", Query: " FIND task "})
	if err != nil {
		t.Fatalf("normalize graph query: %v", err)
	}
	if req.Actor != "user" || req.Query != "FIND task" || req.Firewall != FirewallUser {
		t.Fatalf("graph query request = %#v, want trimmed actor/query and user firewall", req)
	}
	if req.Firewall != FirewallUser {
		t.Fatalf("graph query firewall = %q, want %q", req.Firewall, FirewallUser)
	}
	if req.IncludeGlobal {
		t.Fatal("graph include_global should default to false")
	}
	for _, sensitivity := range req.AllowedSensitivities {
		if sensitivity == SensitivityRestricted {
			t.Fatal("restricted sensitivity should not be included by default")
		}
	}
	if _, err := NormalizeGraphQueryRequest(GraphQueryRequest{Query: "FIND task", Firewall: Firewall("bad firewall!")}); err == nil {
		t.Fatal("expected invalid firewall error")
	}
	if _, err := NormalizeGraphQueryRequest(GraphQueryRequest{Query: "FIND task", AllowedSensitivities: []Sensitivity{Sensitivity("secret")}}); err == nil {
		t.Fatal("expected invalid sensitivity error")
	}
	req, err = NormalizeGraphQueryRequest(GraphQueryRequest{Query: "FIND task", Firewall: Firewall("client-a")})
	if err != nil {
		t.Fatalf("graph firewall rejected: %v", err)
	}
	if req.Firewall != Firewall("client-a") {
		t.Fatalf("graph firewall = %q, want client-a", req.Firewall)
	}
}

// TestNormalizeRepairRequestRejectsInvalidFields verifies memory repair validation.
func TestNormalizeRepairRequestRejectsInvalidFields(t *testing.T) {
	if _, err := NormalizeRepairRequest(RepairRequest{}); err == nil {
		t.Fatal("expected missing memory id error")
	}
	kind := Kind("bad")
	if _, err := NormalizeRepairRequest(RepairRequest{MemoryID: "mem_1", Kind: &kind}); err == nil {
		t.Fatal("expected invalid repair kind error")
	}
	status := StatusArchived
	req, err := NormalizeRepairRequest(RepairRequest{
		Actor:    "  steward  ",
		MemoryID: "mem_1",
		Status:   &status,
		Topics:   []string{" Fixed ", "fixed"},
	})
	if err != nil {
		t.Fatalf("normalize repair: %v", err)
	}
	if req.Actor != "steward" || len(req.Topics) != 1 || req.Topics[0] != "fixed" {
		t.Fatalf("repair request = %#v, want trimmed actor and normalized topic", req)
	}
}

// TestNormalizeCorrectionRequestRequiresTargetAndText verifies correction validation.
func TestNormalizeCorrectionRequestRequiresTargetAndText(t *testing.T) {
	if _, err := NormalizeCorrectionRequest(CorrectionRequest{Text: "fix"}); err == nil {
		t.Fatal("expected missing memory id error")
	}
	if _, err := NormalizeCorrectionRequest(CorrectionRequest{MemoryID: "mem_1", Text: "  "}); err == nil {
		t.Fatal("expected missing correction text error")
	}
	req, err := NormalizeCorrectionRequest(CorrectionRequest{MemoryID: "mem_1", Text: "  fixed fact  "})
	if err != nil {
		t.Fatalf("normalize correction: %v", err)
	}
	if req.Actor != "agent" || req.Firewall != FirewallUser || req.Text != "fixed fact" {
		t.Fatalf("correction request = %#v, want defaults and trimmed text", req)
	}
	req, err = NormalizeCorrectionRequest(CorrectionRequest{MemoryID: "mem_1", Firewall: Firewall("client-a"), Text: "fixed"})
	if err != nil {
		t.Fatalf("correction firewall rejected: %v", err)
	}
	if req.Firewall != Firewall("client-a") {
		t.Fatalf("correction firewall = %q, want client-a", req.Firewall)
	}
}

// TestNormalizeRefreshPageRequestRequiresSupportedTarget verifies page validation.
func TestNormalizeRefreshPageRequestRequiresSupportedTarget(t *testing.T) {
	if _, err := NormalizeRefreshPageRequest(RefreshPageRequest{}); err == nil {
		t.Fatal("expected missing page target error")
	}
	if _, err := NormalizeRefreshPageRequest(RefreshPageRequest{Kind: KindDocument, Title: "doc"}); err == nil {
		t.Fatal("expected unsupported page kind error")
	}
	req, err := NormalizeRefreshPageRequest(RefreshPageRequest{Kind: KindTimeline, Topic: " reporting "})
	if err != nil {
		t.Fatalf("normalize refresh: %v", err)
	}
	if req.Actor != "agent" || req.Firewall != FirewallUser || req.Topic != "reporting" {
		t.Fatalf("refresh request = %#v, want defaults and trimmed topic", req)
	}
	req, err = NormalizeRefreshPageRequest(RefreshPageRequest{Kind: KindTimeline, Firewall: Firewall("client-a"), Topic: "reporting"})
	if err != nil {
		t.Fatalf("refresh firewall rejected: %v", err)
	}
	if req.Firewall != Firewall("client-a") {
		t.Fatalf("refresh firewall = %q, want client-a", req.Firewall)
	}
}
