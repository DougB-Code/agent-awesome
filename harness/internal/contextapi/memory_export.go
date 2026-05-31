// This file enforces reviewed cross-domain memory exports at the harness boundary.
package contextapi

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"agentawesome/internal/config/schema"
	"github.com/modelcontextprotocol/go-sdk/mcp"
)

const exportMemoryCopyToolName = "export_memory_copy"

// memoryExportRequest carries one reviewed memory copy request.
type memoryExportRequest struct {
	SourceDomain   string   `json:"source_domain"`
	TargetDomain   string   `json:"target_domain"`
	SourceMemoryID string   `json:"source_memory_id"`
	SourceEvidence string   `json:"source_evidence_id"`
	Title          string   `json:"title"`
	Content        string   `json:"content"`
	Kind           string   `json:"kind"`
	DomainID       string   `json:"domain_id"`
	Firewall       string   `json:"firewall"`
	Sensitivity    string   `json:"sensitivity"`
	Subjects       []string `json:"subjects"`
	Topics         []string `json:"topics"`
	EntityNames    []string `json:"entity_names"`
	IdempotencyKey string   `json:"idempotency_key"`
}

// memoryExportEvent records the harness policy decision for callers.
type memoryExportEvent struct {
	ID             string `json:"id"`
	Kind           string `json:"kind"`
	Severity       string `json:"severity"`
	Title          string `json:"title"`
	Detail         string `json:"detail"`
	SourceDomain   string `json:"source_domain"`
	TargetDomain   string `json:"target_domain"`
	SourceMemoryID string `json:"source_memory_id"`
	Approved       bool   `json:"approved"`
	CreatedAt      string `json:"created_at"`
}

// exportMemoryCopy validates domain flow policy and writes a reviewed copy.
func (s *Server) exportMemoryCopy(ctx context.Context, arguments map[string]any) (map[string]any, error) {
	if s.tools == nil {
		return nil, fmt.Errorf("memory policy is not configured")
	}
	req, err := decodeMemoryExportRequest(arguments)
	if err != nil {
		return nil, err
	}
	memory := s.tools.Memory
	req.TargetDomain = defaultedTargetDomain(req.TargetDomain, memory.DefaultWriteDomain)
	if req.SourceDomain == "" {
		return nil, fmt.Errorf("source_domain is required")
	}
	if req.SourceMemoryID == "" {
		return nil, fmt.Errorf("source_memory_id is required")
	}
	if strings.TrimSpace(req.Content) == "" {
		return nil, fmt.Errorf("content is required")
	}
	if req.SourceDomain == req.TargetDomain {
		event := newMemoryExportEvent("skipped_export", "info", "Export not needed", "source and target memory domains are the same", req, false)
		return memoryExportResult(false, event, nil), nil
	}
	if _, ok := memoryDomainByID(memory.ReadDomains, req.SourceDomain); !ok {
		event := newMemoryExportEvent("blocked_export", "warning", "Export blocked", "source memory domain is not readable by the active profile", req, false)
		return memoryExportResult(false, event, nil), nil
	}
	if !containsString(memory.WriteDomains, req.TargetDomain) {
		event := newMemoryExportEvent("blocked_export", "warning", "Export blocked", "target memory domain is not writable by the active profile", req, false)
		return memoryExportResult(false, event, nil), nil
	}
	if !memoryFlowAllowed(memory, req.SourceDomain, req.TargetDomain) {
		event := newMemoryExportEvent("blocked_export", "warning", "Export blocked", "memory domain flow is not allowed", req, false)
		return memoryExportResult(false, event, nil), nil
	}
	targetServer, err := memoryDomainServerForTool(s.tools, "save_memory_candidate", req.TargetDomain)
	if err != nil {
		return nil, err
	}
	session, err := connectMCP(ctx, targetServer)
	if err != nil {
		return nil, fmt.Errorf("%s: %w", targetServer.Name, err)
	}
	defer session.Close()
	capture, err := callMCPTool(ctx, session, "save_memory_candidate", memoryExportCapturePayload(memory.Actor, req))
	if err != nil {
		event := newMemoryExportEvent("failed_export", "error", "Export failed", err.Error(), req, false)
		return memoryExportResult(false, event, nil), nil
	}
	event := newMemoryExportEvent("approved_export", "review", "Reviewed memory copy exported", req.SourceDomain+" -> "+req.TargetDomain, req, true)
	return memoryExportResult(true, event, capture), nil
}

// decodeMemoryExportRequest converts untyped JSON arguments into a strict request.
func decodeMemoryExportRequest(arguments map[string]any) (memoryExportRequest, error) {
	var req memoryExportRequest
	raw, err := json.Marshal(arguments)
	if err != nil {
		return req, fmt.Errorf("encode export arguments: %w", err)
	}
	if err := json.Unmarshal(raw, &req); err != nil {
		return req, fmt.Errorf("decode export arguments: %w", err)
	}
	req.SourceDomain = strings.TrimSpace(req.SourceDomain)
	req.TargetDomain = strings.TrimSpace(req.TargetDomain)
	req.SourceMemoryID = strings.TrimSpace(req.SourceMemoryID)
	req.SourceEvidence = strings.TrimSpace(req.SourceEvidence)
	req.Title = strings.TrimSpace(req.Title)
	req.Content = strings.TrimSpace(req.Content)
	req.Kind = strings.TrimSpace(req.Kind)
	req.DomainID = strings.TrimSpace(req.DomainID)
	req.Firewall = strings.TrimSpace(req.Firewall)
	req.Sensitivity = strings.TrimSpace(req.Sensitivity)
	req.IdempotencyKey = strings.TrimSpace(req.IdempotencyKey)
	return req, nil
}

// defaultedTargetDomain resolves the configured default export destination.
func defaultedTargetDomain(target string, fallback string) string {
	if strings.TrimSpace(target) != "" {
		return strings.TrimSpace(target)
	}
	return strings.TrimSpace(fallback)
}

// memoryFlowAllowed checks same-domain or explicitly configured information flow.
func memoryFlowAllowed(memory schema.Memory, source string, target string) bool {
	if source == target {
		return true
	}
	for _, flow := range memory.AllowedFlows {
		if strings.TrimSpace(flow.From) == source && strings.TrimSpace(flow.To) == target {
			return true
		}
	}
	return false
}

// memoryExportCapturePayload builds the destination-domain capture request.
func memoryExportCapturePayload(actor string, req memoryExportRequest) map[string]any {
	title := req.Title
	if title == "" {
		title = "Reviewed memory copy"
	}
	kind := req.Kind
	if kind == "" {
		kind = "summary"
	}
	domainID := req.DomainID
	if domainID == "" {
		domainID = req.Firewall
	}
	if domainID == "" {
		domainID = req.TargetDomain
	}
	sensitivity := req.Sensitivity
	if sensitivity == "" {
		sensitivity = "private"
	}
	idempotencyKey := req.IdempotencyKey
	if idempotencyKey == "" {
		idempotencyKey = "agent_awesome_declassification:" + req.SourceDomain + ":" + req.TargetDomain + ":" + req.SourceMemoryID + ":" + time.Now().UTC().Format("20060102T150405.000000000Z")
	}
	return map[string]any{
		"actor":        strings.TrimSpace(actor),
		"content":      req.Content,
		"title":        title,
		"media_type":   "text/plain",
		"kind":         kind,
		"domain_id":    domainID,
		"trust_level":  "user_asserted",
		"sensitivity":  sensitivity,
		"subjects":     req.Subjects,
		"topics":       req.Topics,
		"entity_names": req.EntityNames,
		"source": map[string]any{
			"system": "agent_awesome_declassification",
			"id":     memoryExportSourceID(req),
		},
		"idempotency_key": idempotencyKey,
	}
}

// memoryExportSourceID builds the auditable source id for the reviewed copy.
func memoryExportSourceID(req memoryExportRequest) string {
	parts := []string{req.SourceDomain, req.SourceMemoryID}
	if req.SourceEvidence != "" {
		parts = append(parts, req.SourceEvidence)
	}
	return strings.Join(parts, ":")
}

// newMemoryExportEvent builds a deterministic response event for UI review.
func newMemoryExportEvent(kind string, severity string, title string, detail string, req memoryExportRequest, approved bool) map[string]any {
	now := time.Now().UTC()
	event := memoryExportEvent{
		ID:             "memory-safety-" + now.Format("20060102T150405.000000000Z"),
		Kind:           kind,
		Severity:       severity,
		Title:          title,
		Detail:         detail,
		SourceDomain:   req.SourceDomain,
		TargetDomain:   req.TargetDomain,
		SourceMemoryID: req.SourceMemoryID,
		Approved:       approved,
		CreatedAt:      now.Format(time.RFC3339Nano),
	}
	raw, _ := json.Marshal(event)
	var out map[string]any
	_ = json.Unmarshal(raw, &out)
	return out
}

// memoryExportResult returns a stable structured response for all decisions.
func memoryExportResult(exported bool, event map[string]any, capture any) map[string]any {
	result := map[string]any{
		"exported":     exported,
		"safety_event": event,
	}
	if capture != nil {
		result["capture"] = capture
	}
	return result
}

// callMCPTool invokes one MCP tool and returns structured content.
func callMCPTool(ctx context.Context, session *mcp.ClientSession, name string, arguments map[string]any) (any, error) {
	result, err := session.CallTool(ctx, &mcp.CallToolParams{
		Name:      name,
		Arguments: arguments,
	})
	if err != nil {
		return nil, err
	}
	if result == nil {
		return nil, fmt.Errorf("%s returned an empty MCP result", name)
	}
	if result.IsError {
		return nil, fmt.Errorf("%s returned an MCP tool error", name)
	}
	if result.StructuredContent != nil {
		return result.StructuredContent, nil
	}
	return map[string]any{"content": result.Content}, nil
}
