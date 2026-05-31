// This file defines the AA runbook envelope data model.
package envelope

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"strings"
	"time"
)

const (
	// BodyKindObject identifies JSON object envelope bodies.
	BodyKindObject = "object"
	// BodyKindArray identifies JSON array envelope bodies.
	BodyKindArray = "array"
	// BodyKindText identifies plain text envelope bodies.
	BodyKindText = "text"
	// BodyKindTable identifies tabular envelope bodies.
	BodyKindTable = "table"
	// BodyKindFile identifies a single file artifact envelope body.
	BodyKindFile = "file"
	// BodyKindFiles identifies multiple file artifact envelope bodies.
	BodyKindFiles = "files"
	// BodyKindBinary identifies opaque binary envelope bodies.
	BodyKindBinary = "binary"
	// BodyKindEmpty identifies an intentionally empty envelope body.
	BodyKindEmpty = "empty"
)

const (
	// StatusSucceeded reports that a node completed normally.
	StatusSucceeded = "succeeded"
	// StatusFailed reports that a node failed.
	StatusFailed = "failed"
	// StatusNeedsInput reports that a node is waiting for external input.
	StatusNeedsInput = "needs_input"
	// StatusCancelled reports that a node was cancelled.
	StatusCancelled = "cancelled"
	// StatusSkipped reports that a conditional branch was not active.
	StatusSkipped = "skipped"
)

const envelopeSchemaRef = "aa.runbook.envelope.v1"

// Envelope is the universal runbook node input and output carrier.
type Envelope struct {
	Meta        Metadata       `json:"meta" yaml:"meta"`
	Body        Body           `json:"body" yaml:"body"`
	Facets      map[string]any `json:"facets,omitempty" yaml:"facets,omitempty"`
	Artifacts   []ArtifactRef  `json:"artifacts,omitempty" yaml:"artifacts,omitempty"`
	Variables   map[string]any `json:"variables,omitempty" yaml:"variables,omitempty"`
	Diagnostics []Diagnostic   `json:"diagnostics,omitempty" yaml:"diagnostics,omitempty"`
	Control     Control        `json:"control" yaml:"control"`
}

// Metadata stores provenance-neutral execution identifiers.
type Metadata struct {
	SchemaRef       string           `json:"schema_ref" yaml:"schema_ref"`
	RunbookRunID   string           `json:"runbook_run_id,omitempty" yaml:"runbook_run_id,omitempty"`
	NodeRunID       string           `json:"node_run_id,omitempty" yaml:"node_run_id,omitempty"`
	CorrelationID   string           `json:"correlation_id,omitempty" yaml:"correlation_id,omitempty"`
	CausationID     string           `json:"causation_id,omitempty" yaml:"causation_id,omitempty"`
	TenantID        string           `json:"tenant_id,omitempty" yaml:"tenant_id,omitempty"`
	UserID          string           `json:"user_id,omitempty" yaml:"user_id,omitempty"`
	Attempt         int              `json:"attempt,omitempty" yaml:"attempt,omitempty"`
	CreatedAt       string           `json:"created_at" yaml:"created_at"`
	SecurityContext map[string]any   `json:"security_context,omitempty" yaml:"security_context,omitempty"`
	Provenance      []ProvenanceItem `json:"provenance,omitempty" yaml:"provenance,omitempty"`
}

// Body stores the native value carried by an envelope.
type Body struct {
	Kind  string `json:"kind" yaml:"kind"`
	Value any    `json:"value,omitempty" yaml:"value,omitempty"`
}

// ArtifactRef stores a durable file or binary reference.
type ArtifactRef struct {
	ID        string `json:"id,omitempty" yaml:"id,omitempty"`
	MediaType string `json:"media_type,omitempty" yaml:"media_type,omitempty"`
	Name      string `json:"name,omitempty" yaml:"name,omitempty"`
	Size      int64  `json:"size,omitempty" yaml:"size,omitempty"`
	URI       string `json:"uri,omitempty" yaml:"uri,omitempty"`
	Digest    string `json:"digest,omitempty" yaml:"digest,omitempty"`
}

// Diagnostic records validation, mapping, policy, or execution messages.
type Diagnostic struct {
	Severity string `json:"severity,omitempty" yaml:"severity,omitempty"`
	Code     string `json:"code,omitempty" yaml:"code,omitempty"`
	Path     string `json:"path,omitempty" yaml:"path,omitempty"`
	Message  string `json:"message" yaml:"message"`
}

// ProvenanceItem records one source contribution to an envelope field.
type ProvenanceItem struct {
	SourceNodeID string `json:"source_node_id,omitempty" yaml:"source_node_id,omitempty"`
	Field        string `json:"field,omitempty" yaml:"field,omitempty"`
	Digest       string `json:"digest,omitempty" yaml:"digest,omitempty"`
	CreatedAt    string `json:"created_at,omitempty" yaml:"created_at,omitempty"`
}

// Control stores deterministic runbook status hints.
type Control struct {
	Status           string `json:"status,omitempty" yaml:"status,omitempty"`
	SuggestedTrigger string `json:"suggested_trigger,omitempty" yaml:"suggested_trigger,omitempty"`
}

// New creates an envelope with normalized metadata and body kind.
func New(runbookRunID string, nodeRunID string, attempt int, bodyValue any) Envelope {
	return Envelope{
		Meta: Metadata{
			SchemaRef:     envelopeSchemaRef,
			RunbookRunID: strings.TrimSpace(runbookRunID),
			NodeRunID:     strings.TrimSpace(nodeRunID),
			CorrelationID: strings.TrimSpace(runbookRunID),
			Attempt:       attempt,
			CreatedAt:     time.Now().UTC().Format(time.RFC3339Nano),
		},
		Body: Body{
			Kind:  BodyKind(bodyValue),
			Value: bodyValue,
		},
		Facets:    map[string]any{},
		Variables: map[string]any{},
		Control:   Control{Status: StatusSucceeded},
	}
}

// Empty creates an empty successful envelope for a node.
func Empty(runbookRunID string, nodeRunID string, attempt int) Envelope {
	env := New(runbookRunID, nodeRunID, attempt, nil)
	env.Body.Kind = BodyKindEmpty
	return env
}

// FromMap decodes a persisted envelope map or wraps a raw map as an object body.
func FromMap(value map[string]any) Envelope {
	if value == nil {
		return Empty("", "", 0)
	}
	if _, ok := value["meta"]; ok {
		raw, err := json.Marshal(value)
		if err == nil {
			var env Envelope
			if json.Unmarshal(raw, &env) == nil && strings.TrimSpace(env.Meta.SchemaRef) != "" {
				env.Normalize()
				return env
			}
		}
	}
	env := New("", "", 0, cloneAny(value))
	env.Control.Status = StatusSucceeded
	return env
}

// FromAny decodes an envelope-like value or wraps a raw value as a body.
func FromAny(value any) Envelope {
	if env, ok := value.(Envelope); ok {
		env.Normalize()
		return env
	}
	if mapped, ok := value.(map[string]any); ok {
		return FromMap(mapped)
	}
	env := New("", "", 0, cloneAny(value))
	env.Control.Status = StatusSucceeded
	return env
}

// NormalizeResult converts an action result into a completed node envelope.
func NormalizeResult(runbookRunID string, nodeRunID string, attempt int, result map[string]any, status string) Envelope {
	env := FromMap(result)
	if strings.TrimSpace(env.Meta.SchemaRef) == "" || env.Meta.SchemaRef != envelopeSchemaRef {
		env = New(runbookRunID, nodeRunID, attempt, cloneAny(result))
	}
	env.Meta.RunbookRunID = strings.TrimSpace(runbookRunID)
	env.Meta.NodeRunID = strings.TrimSpace(nodeRunID)
	env.Meta.Attempt = attempt
	if env.Meta.SchemaRef == "" {
		env.Meta.SchemaRef = envelopeSchemaRef
	}
	if env.Meta.CreatedAt == "" {
		env.Meta.CreatedAt = time.Now().UTC().Format(time.RFC3339Nano)
	}
	if strings.TrimSpace(status) != "" {
		env.Control.Status = strings.TrimSpace(status)
	}
	env.Normalize()
	return env
}

// Normalize fills missing envelope fields with deterministic defaults.
func (e *Envelope) Normalize() {
	if e == nil {
		return
	}
	if strings.TrimSpace(e.Meta.SchemaRef) == "" {
		e.Meta.SchemaRef = envelopeSchemaRef
	}
	if strings.TrimSpace(e.Meta.CreatedAt) == "" {
		e.Meta.CreatedAt = time.Now().UTC().Format(time.RFC3339Nano)
	}
	if strings.TrimSpace(e.Body.Kind) == "" {
		e.Body.Kind = BodyKind(e.Body.Value)
	}
	if e.Facets == nil {
		e.Facets = map[string]any{}
	}
	if e.Variables == nil {
		e.Variables = map[string]any{}
	}
	if strings.TrimSpace(e.Control.Status) == "" {
		e.Control.Status = StatusSucceeded
	}
}

// BodyKind returns the closest envelope body kind for a JSON-like value.
func BodyKind(value any) string {
	switch typed := value.(type) {
	case nil:
		return BodyKindEmpty
	case string:
		return BodyKindText
	case []byte:
		return BodyKindBinary
	case []any:
		return BodyKindArray
	case []map[string]any:
		return BodyKindArray
	case map[string]any:
		if kind, _ := typed["kind"].(string); strings.TrimSpace(kind) == BodyKindTable {
			return BodyKindTable
		}
		return BodyKindObject
	default:
		return BodyKindObject
	}
}

// ToMap returns a JSON-safe map representation of the envelope.
func (e Envelope) ToMap() map[string]any {
	e.Normalize()
	raw, err := json.Marshal(e)
	if err != nil {
		return map[string]any{}
	}
	var out map[string]any
	if err := json.Unmarshal(raw, &out); err != nil {
		return map[string]any{}
	}
	return out
}

// Clone returns a deep copy of the envelope.
func (e Envelope) Clone() Envelope {
	return FromMap(e.ToMap())
}

// AddDiagnostic appends a diagnostic to the envelope.
func (e *Envelope) AddDiagnostic(severity string, code string, path string, message string) {
	if e == nil || strings.TrimSpace(message) == "" {
		return
	}
	e.Diagnostics = append(e.Diagnostics, Diagnostic{
		Severity: strings.TrimSpace(severity),
		Code:     strings.TrimSpace(code),
		Path:     strings.TrimSpace(path),
		Message:  strings.TrimSpace(message),
	})
}

// SetFacet writes a semantic facet value.
func (e *Envelope) SetFacet(name string, value any) {
	if e == nil || strings.TrimSpace(name) == "" {
		return
	}
	e.Normalize()
	e.Facets[strings.TrimSpace(name)] = cloneAny(value)
}

// MergeFrom merges body, facets, artifacts, variables, and diagnostics from another envelope.
func (e *Envelope) MergeFrom(source Envelope, bodyKey string) {
	if e == nil {
		return
	}
	e.Normalize()
	source.Normalize()
	key := strings.TrimSpace(bodyKey)
	if key == "" || key == "input" || key == "body" {
		e.Body = source.Body
	} else {
		object, _ := e.Body.Value.(map[string]any)
		if object == nil {
			object = map[string]any{}
		}
		object[key] = cloneAny(source.Body.Value)
		e.Body = Body{Kind: BodyKindObject, Value: object}
	}
	for name, value := range source.Facets {
		e.Facets[name] = cloneAny(value)
	}
	e.Artifacts = append(e.Artifacts, source.Artifacts...)
	for name, value := range source.Variables {
		e.Variables[name] = cloneAny(value)
	}
	e.Diagnostics = append(e.Diagnostics, source.Diagnostics...)
}

// AddProvenance records source information for a field.
func (e *Envelope) AddProvenance(sourceNodeID string, field string, value any) {
	if e == nil {
		return
	}
	e.Meta.Provenance = append(e.Meta.Provenance, ProvenanceItem{
		SourceNodeID: strings.TrimSpace(sourceNodeID),
		Field:        strings.TrimSpace(field),
		Digest:       Digest(value),
		CreatedAt:    time.Now().UTC().Format(time.RFC3339Nano),
	})
}

// ValidateSize reports whether the serialized envelope exceeds maxBytes.
func (e Envelope) ValidateSize(maxBytes int64) []Diagnostic {
	if maxBytes <= 0 {
		return nil
	}
	data, err := json.Marshal(e)
	if err != nil {
		return []Diagnostic{{Severity: "error", Code: "envelope_encode_failed", Message: err.Error()}}
	}
	if int64(len(data)) <= maxBytes {
		return nil
	}
	return []Diagnostic{{
		Severity: "error",
		Code:     "envelope_too_large",
		Message:  fmt.Sprintf("envelope size %d exceeds limit %d", len(data), maxBytes),
	}}
}

// Digest returns a stable SHA-256 digest for a JSON-like value.
func Digest(value any) string {
	data, err := json.Marshal(value)
	if err != nil {
		data = []byte(fmt.Sprint(value))
	}
	sum := sha256.Sum256(data)
	return "sha256:" + hex.EncodeToString(sum[:])
}

// cloneAny deep copies JSON-like values.
func cloneAny(value any) any {
	data, err := json.Marshal(value)
	if err != nil {
		return value
	}
	var out any
	if err := json.Unmarshal(data, &out); err != nil {
		return value
	}
	return out
}
