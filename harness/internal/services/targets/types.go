// This file defines dumb Runtime Target data models.
package targets

// RuntimeTarget stores one Computer or Server execution target.
type RuntimeTarget struct {
	ID                 string   `json:"id"`
	Name               string   `json:"name"`
	Kind               string   `json:"kind"`
	Status             string   `json:"status"`
	Version            string   `json:"version,omitempty"`
	Capabilities       []string `json:"capabilities,omitempty"`
	AllowedCodebaseIDs []string `json:"allowed_codebase_ids,omitempty"`
	SecretRefCount     int      `json:"secret_ref_count"`
	LastSeenAt         string   `json:"last_seen_at,omitempty"`
	CurrentRunCount    int      `json:"current_run_count"`
	OS                 string   `json:"os,omitempty"`
	Hostname           string   `json:"hostname,omitempty"`
	CreatedAt          string   `json:"created_at,omitempty"`
	UpdatedAt          string   `json:"updated_at,omitempty"`
}

// TargetHealth stores display-safe target health and runtime metadata.
type TargetHealth struct {
	TargetID        string `json:"target_id"`
	Status          string `json:"status"`
	Message         string `json:"message,omitempty"`
	Version         string `json:"version,omitempty"`
	OS              string `json:"os,omitempty"`
	Hostname        string `json:"hostname,omitempty"`
	CurrentRunCount int    `json:"current_run_count"`
	CheckedAt       string `json:"checked_at"`
}

// TargetLogEntry stores one display-safe target log row.
type TargetLogEntry struct {
	ID        int64  `json:"id"`
	TargetID  string `json:"target_id"`
	Level     string `json:"level"`
	Message   string `json:"message"`
	CreatedAt string `json:"created_at"`
}

// TargetSecretMetadata stores target-local secret reference metadata.
type TargetSecretMetadata struct {
	TargetID string `json:"target_id"`
	Count    int    `json:"count"`
}

// PairingTokenRequest carries scoped Computer or Server invite settings.
type PairingTokenRequest struct {
	Name               string   `json:"name,omitempty"`
	Kind               string   `json:"kind,omitempty"`
	AllowedCodebaseIDs []string `json:"allowed_codebase_ids,omitempty"`
	Capabilities       []string `json:"capabilities,omitempty"`
	SecretRefCount     int      `json:"secret_ref_count,omitempty"`
	ExpiresInSeconds   int      `json:"expires_in_seconds,omitempty"`
}

// PairingToken stores a signed short-lived target pairing invite.
type PairingToken struct {
	Token     string `json:"token"`
	TargetID  string `json:"target_id"`
	ExpiresAt string `json:"expires_at"`
}

// PairedRegistration carries a target heartbeat plus signed invite token.
type PairedRegistration struct {
	Token        string   `json:"token"`
	Version      string   `json:"version,omitempty"`
	Capabilities []string `json:"capabilities,omitempty"`
	OS           string   `json:"os,omitempty"`
	Hostname     string   `json:"hostname,omitempty"`
}

// TargetUpdateRequest carries editable target fields.
type TargetUpdateRequest struct {
	Name               string   `json:"name,omitempty"`
	Status             string   `json:"status,omitempty"`
	AllowedCodebaseIDs []string `json:"allowed_codebase_ids,omitempty"`
	SecretRefCount     *int     `json:"secret_ref_count,omitempty"`
}

// LocalRegistration stores local target startup data.
type LocalRegistration struct {
	Version      string
	Capabilities []string
}
