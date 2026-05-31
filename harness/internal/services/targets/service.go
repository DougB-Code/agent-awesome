// This file implements runtime target service launchpad.
package targets

import (
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"os"
	"runtime"
	"sort"
	"strings"
	"time"
)

const (
	// LocalTargetID is the stable id for the current host process.
	LocalTargetID = "local"
	// TargetKindLocal identifies the current local computer.
	TargetKindLocal = "local"
	// TargetKindLAN identifies a paired nearby computer.
	TargetKindLAN = "lan"
	// TargetKindCloud identifies a paired cloud server.
	TargetKindCloud = "cloud"
	// TargetKindManaged identifies a managed runtime server.
	TargetKindManaged = "managed"
	// TargetStatusHealthy means a target heartbeat is current.
	TargetStatusHealthy = "healthy"
)

const (
	defaultPairingTokenSeconds = 900
	maxPairingTokenSeconds     = 86400
)

// Service owns target inventory and health reads.
type Service struct {
	store *Store
}

// NewService creates a target service over durable storage.
func NewService(store *Store) *Service {
	return &Service{store: store}
}

// RegisterLocalTarget upserts the current computer and records a heartbeat log.
func (s *Service) RegisterLocalTarget(ctx context.Context, registration LocalRegistration) (RuntimeTarget, error) {
	if s == nil || s.store == nil {
		return RuntimeTarget{}, fmt.Errorf("runtime target store is not configured")
	}
	hostname, _ := os.Hostname()
	now := timestampNow()
	existing, err := s.store.GetTarget(ctx, LocalTargetID)
	if err != nil && !isNotFound(err) {
		return RuntimeTarget{}, err
	}
	allowedCodebases := existing.AllowedCodebaseIDs
	secretRefCount := existing.SecretRefCount
	createdAt := existing.CreatedAt
	if createdAt == "" {
		createdAt = now
	}
	target := RuntimeTarget{
		ID:                 LocalTargetID,
		Name:               firstNonEmpty(existing.Name, "This computer"),
		Kind:               TargetKindLocal,
		Status:             TargetStatusHealthy,
		Version:            strings.TrimSpace(registration.Version),
		Capabilities:       normalizedStrings(registration.Capabilities),
		AllowedCodebaseIDs: allowedCodebases,
		SecretRefCount:     secretRefCount,
		LastSeenAt:         now,
		CurrentRunCount:    existing.CurrentRunCount,
		OS:                 runtime.GOOS + "/" + runtime.GOARCH,
		Hostname:           strings.TrimSpace(hostname),
		CreatedAt:          createdAt,
		UpdatedAt:          now,
	}
	if err := s.store.UpsertTarget(ctx, target); err != nil {
		return RuntimeTarget{}, err
	}
	_ = s.store.AppendLog(ctx, TargetLogEntry{
		TargetID: LocalTargetID,
		Level:    "info",
		Message:  "local target heartbeat",
	})
	return s.store.GetTarget(ctx, LocalTargetID)
}

// ListTargets returns runtime targets ordered for UI display.
func (s *Service) ListTargets(ctx context.Context) ([]RuntimeTarget, error) {
	if s == nil || s.store == nil {
		return nil, fmt.Errorf("runtime target store is not configured")
	}
	return s.store.ListTargets(ctx)
}

// GetTarget returns one runtime target by id.
func (s *Service) GetTarget(ctx context.Context, id string) (RuntimeTarget, error) {
	if s == nil || s.store == nil {
		return RuntimeTarget{}, fmt.Errorf("runtime target store is not configured")
	}
	return s.store.GetTarget(ctx, strings.TrimSpace(id))
}

// UpdateTarget applies user-editable target metadata.
func (s *Service) UpdateTarget(ctx context.Context, id string, req TargetUpdateRequest) (RuntimeTarget, error) {
	target, err := s.GetTarget(ctx, id)
	if err != nil {
		return RuntimeTarget{}, err
	}
	if strings.TrimSpace(req.Name) != "" {
		target.Name = strings.TrimSpace(req.Name)
	}
	if strings.TrimSpace(req.Status) != "" {
		target.Status = strings.TrimSpace(req.Status)
	}
	if req.AllowedCodebaseIDs != nil {
		target.AllowedCodebaseIDs = normalizedStrings(req.AllowedCodebaseIDs)
	}
	if req.SecretRefCount != nil {
		target.SecretRefCount = *req.SecretRefCount
	}
	target.UpdatedAt = timestampNow()
	if err := s.store.UpsertTarget(ctx, target); err != nil {
		return RuntimeTarget{}, err
	}
	return s.store.GetTarget(ctx, target.ID)
}

// IssuePairingToken creates a signed short-lived invite for another target.
func (s *Service) IssuePairingToken(ctx context.Context, req PairingTokenRequest) (PairingToken, error) {
	if s == nil || s.store == nil {
		return PairingToken{}, fmt.Errorf("runtime target store is not configured")
	}
	kind := strings.TrimSpace(req.Kind)
	if kind == "" {
		kind = TargetKindLAN
	}
	if !pairableTargetKind(kind) {
		return PairingToken{}, fmt.Errorf("target kind %q cannot be paired", kind)
	}
	targetID, err := randomTargetID(kind)
	if err != nil {
		return PairingToken{}, err
	}
	seconds := req.ExpiresInSeconds
	if seconds <= 0 {
		seconds = defaultPairingTokenSeconds
	}
	if seconds > maxPairingTokenSeconds {
		seconds = maxPairingTokenSeconds
	}
	expiresAt := time.Now().UTC().Add(time.Duration(seconds) * time.Second)
	payload := pairingTokenPayload{
		TargetID:           targetID,
		Name:               firstNonEmpty(req.Name, defaultTargetName(kind)),
		Kind:               kind,
		AllowedCodebaseIDs: normalizedStrings(req.AllowedCodebaseIDs),
		Capabilities:       normalizedStrings(req.Capabilities),
		SecretRefCount:     req.SecretRefCount,
		ExpiresAtUnix:      expiresAt.Unix(),
	}
	token, err := s.signPairingPayload(ctx, payload)
	if err != nil {
		return PairingToken{}, err
	}
	return PairingToken{Token: token, TargetID: targetID, ExpiresAt: expiresAt.Format(time.RFC3339)}, nil
}

// RegisterPairedTarget validates a signed invite and stores target heartbeat data.
func (s *Service) RegisterPairedTarget(ctx context.Context, req PairedRegistration) (RuntimeTarget, error) {
	payload, err := s.validatePairingToken(ctx, req.Token)
	if err != nil {
		return RuntimeTarget{}, err
	}
	now := timestampNow()
	existing, err := s.store.GetTarget(ctx, payload.TargetID)
	if err != nil && !isNotFound(err) {
		return RuntimeTarget{}, err
	}
	createdAt := existing.CreatedAt
	if createdAt == "" {
		createdAt = now
	}
	target := RuntimeTarget{
		ID:                 payload.TargetID,
		Name:               firstNonEmpty(existing.Name, payload.Name, defaultTargetName(payload.Kind)),
		Kind:               payload.Kind,
		Status:             TargetStatusHealthy,
		Version:            strings.TrimSpace(req.Version),
		Capabilities:       normalizedStrings(append(payload.Capabilities, req.Capabilities...)),
		AllowedCodebaseIDs: payload.AllowedCodebaseIDs,
		SecretRefCount:     payload.SecretRefCount,
		LastSeenAt:         now,
		CurrentRunCount:    existing.CurrentRunCount,
		OS:                 strings.TrimSpace(req.OS),
		Hostname:           strings.TrimSpace(req.Hostname),
		CreatedAt:          createdAt,
		UpdatedAt:          now,
	}
	if err := s.store.UpsertTarget(ctx, target); err != nil {
		return RuntimeTarget{}, err
	}
	_ = s.store.AppendLog(ctx, TargetLogEntry{
		TargetID: target.ID,
		Level:    "info",
		Message:  "paired target heartbeat",
	})
	return s.store.GetTarget(ctx, target.ID)
}

// Health returns display-safe health metadata for one target.
func (s *Service) Health(ctx context.Context, id string) (TargetHealth, error) {
	target, err := s.GetTarget(ctx, id)
	if err != nil {
		return TargetHealth{}, err
	}
	status := strings.TrimSpace(target.Status)
	message := ""
	if status == "" {
		status = "unknown"
		message = "target has not reported health"
	}
	return TargetHealth{
		TargetID:        target.ID,
		Status:          status,
		Message:         message,
		Version:         target.Version,
		OS:              target.OS,
		Hostname:        target.Hostname,
		CurrentRunCount: target.CurrentRunCount,
		CheckedAt:       timestampNow(),
	}, nil
}

// Logs lists display-safe log rows for one target.
func (s *Service) Logs(ctx context.Context, id string) ([]TargetLogEntry, error) {
	if _, err := s.GetTarget(ctx, id); err != nil {
		return nil, err
	}
	return s.store.ListLogs(ctx, strings.TrimSpace(id), 100)
}

// SecretMetadata returns target-local secret reference metadata.
func (s *Service) SecretMetadata(ctx context.Context, id string) (TargetSecretMetadata, error) {
	target, err := s.GetTarget(ctx, id)
	if err != nil {
		return TargetSecretMetadata{}, err
	}
	return TargetSecretMetadata{TargetID: target.ID, Count: target.SecretRefCount}, nil
}

// normalizedStrings trims, deduplicates, and sorts string identifiers.
func normalizedStrings(values []string) []string {
	set := map[string]struct{}{}
	for _, value := range values {
		trimmed := strings.TrimSpace(value)
		if trimmed != "" {
			set[trimmed] = struct{}{}
		}
	}
	out := make([]string, 0, len(set))
	for value := range set {
		out = append(out, value)
	}
	sort.Strings(out)
	return out
}

// firstNonEmpty returns the first non-empty value.
func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return strings.TrimSpace(value)
		}
	}
	return ""
}

// pairingTokenPayload is the signed target invite body.
type pairingTokenPayload struct {
	TargetID           string   `json:"target_id"`
	Name               string   `json:"name"`
	Kind               string   `json:"kind"`
	AllowedCodebaseIDs []string `json:"allowed_codebase_ids,omitempty"`
	Capabilities       []string `json:"capabilities,omitempty"`
	SecretRefCount     int      `json:"secret_ref_count,omitempty"`
	ExpiresAtUnix      int64    `json:"expires_at_unix"`
}

// signPairingPayload signs one target invite payload.
func (s *Service) signPairingPayload(ctx context.Context, payload pairingTokenPayload) (string, error) {
	secret, err := s.store.PairingSecret(ctx)
	if err != nil {
		return "", err
	}
	data, err := json.Marshal(payload)
	if err != nil {
		return "", fmt.Errorf("encode runtime target pairing payload: %w", err)
	}
	encoded := base64.RawURLEncoding.EncodeToString(data)
	signature := pairingSignature(secret, encoded)
	return encoded + "." + signature, nil
}

// validatePairingToken verifies and decodes one target invite token.
func (s *Service) validatePairingToken(ctx context.Context, token string) (pairingTokenPayload, error) {
	parts := strings.Split(strings.TrimSpace(token), ".")
	if len(parts) != 2 || parts[0] == "" || parts[1] == "" {
		return pairingTokenPayload{}, fmt.Errorf("pairing token is invalid")
	}
	secret, err := s.store.PairingSecret(ctx)
	if err != nil {
		return pairingTokenPayload{}, err
	}
	expected := pairingSignature(secret, parts[0])
	if !hmac.Equal([]byte(expected), []byte(parts[1])) {
		return pairingTokenPayload{}, fmt.Errorf("pairing token signature is invalid")
	}
	data, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return pairingTokenPayload{}, fmt.Errorf("decode pairing token payload: %w", err)
	}
	var payload pairingTokenPayload
	if err := json.Unmarshal(data, &payload); err != nil {
		return pairingTokenPayload{}, fmt.Errorf("decode pairing token payload: %w", err)
	}
	if payload.TargetID == "" || !pairableTargetKind(payload.Kind) {
		return pairingTokenPayload{}, fmt.Errorf("pairing token target is invalid")
	}
	if time.Now().UTC().Unix() > payload.ExpiresAtUnix {
		return pairingTokenPayload{}, fmt.Errorf("pairing token expired")
	}
	payload.AllowedCodebaseIDs = normalizedStrings(payload.AllowedCodebaseIDs)
	payload.Capabilities = normalizedStrings(payload.Capabilities)
	return payload, nil
}

// pairingSignature signs an encoded token payload.
func pairingSignature(secret []byte, encodedPayload string) string {
	mac := hmac.New(sha256.New, secret)
	mac.Write([]byte(encodedPayload))
	return base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}

// pairableTargetKind reports whether a target kind may be invited.
func pairableTargetKind(kind string) bool {
	switch strings.TrimSpace(kind) {
	case TargetKindLAN, TargetKindCloud, TargetKindManaged:
		return true
	default:
		return false
	}
}

// defaultTargetName returns a product-facing default name for one kind.
func defaultTargetName(kind string) string {
	switch strings.TrimSpace(kind) {
	case TargetKindCloud:
		return "Cloud server"
	case TargetKindManaged:
		return "Managed server"
	default:
		return "Nearby computer"
	}
}

// randomTargetID creates a stable id prefix with random suffix.
func randomTargetID(kind string) (string, error) {
	var data [8]byte
	if _, err := rand.Read(data[:]); err != nil {
		return "", fmt.Errorf("generate runtime target id: %w", err)
	}
	return strings.TrimSpace(kind) + "_" + base64.RawURLEncoding.EncodeToString(data[:]), nil
}
