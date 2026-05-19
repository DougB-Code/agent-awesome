// This file defines shared controlled vocabularies and their validators.
package vocabulary

// Firewall classifies an isolated memory sharing boundary.
type Firewall string

const (
	// FirewallSession limits data to one session.
	FirewallSession Firewall = "session"
	// FirewallUser limits data to one user.
	FirewallUser Firewall = "user"
	// FirewallHousehold shares data across a household.
	FirewallHousehold Firewall = "household"
	// FirewallTenant limits data to an organization tenant.
	FirewallTenant Firewall = "tenant"
	// FirewallProject limits data to a project.
	FirewallProject Firewall = "project"
	// FirewallGlobal exposes data globally within service policy.
	FirewallGlobal Firewall = "global"
)

// Sensitivity controls whether a caller may see a record or graph fact.
type Sensitivity string

const (
	// SensitivityPublic is safe for broad disclosure.
	SensitivityPublic Sensitivity = "public"
	// SensitivityInternal is visible inside the configured boundary.
	SensitivityInternal Sensitivity = "internal"
	// SensitivityPrivate is visible to the owning user or household.
	SensitivityPrivate Sensitivity = "private"
	// SensitivityRestricted requires an explicit request grant.
	SensitivityRestricted Sensitivity = "restricted"
)

// TrustLevel describes where a fact or artifact came from.
type TrustLevel string

const (
	// TrustSourceOriginal marks verbatim source artifacts.
	TrustSourceOriginal TrustLevel = "source_original"
	// TrustUserAsserted marks user-supplied claims.
	TrustUserAsserted TrustLevel = "user_asserted"
	// TrustModelExtracted marks model-extracted fields.
	TrustModelExtracted TrustLevel = "model_extracted"
	// TrustModelSynthesized marks model-written summaries or pages.
	TrustModelSynthesized TrustLevel = "model_synthesized"
	// TrustExternallyVerified marks facts checked against an external source.
	TrustExternallyVerified TrustLevel = "externally_verified"
)

// LifecycleStatus describes whether data is active or retained history.
type LifecycleStatus string

const (
	// StatusActive marks current data.
	StatusActive LifecycleStatus = "active"
	// StatusSuperseded marks data replaced by newer source content.
	StatusSuperseded LifecycleStatus = "superseded"
	// StatusDeprecated marks discouraged data that remains auditable.
	StatusDeprecated LifecycleStatus = "deprecated"
	// StatusArchived marks retained but inactive data.
	StatusArchived LifecycleStatus = "archived"
	// StatusDeleted marks lifecycle-deleted graph facts.
	StatusDeleted LifecycleStatus = "deleted"
)

const (
	// DefaultAgentActor is the actor used when automated memory work omits one.
	DefaultAgentActor = "agent"
	// DefaultUserActor is the actor used when user task work omits one.
	DefaultUserActor = "user"
)

// FirewallStrings returns default firewall ids for schemas and diagnostics.
func FirewallStrings() []string {
	return StringValues([]Firewall{FirewallSession, FirewallUser, FirewallHousehold, FirewallTenant, FirewallProject, FirewallGlobal})
}

// SensitivityStrings returns sensitivity vocabulary values for schemas and diagnostics.
func SensitivityStrings() []string {
	return StringValues([]Sensitivity{SensitivityPublic, SensitivityInternal, SensitivityPrivate, SensitivityRestricted})
}

// DefaultReadableSensitivities returns the non-restricted sensitivity set.
func DefaultReadableSensitivities() []Sensitivity {
	return []Sensitivity{SensitivityPublic, SensitivityInternal, SensitivityPrivate}
}

// TrustLevelStrings returns trust vocabulary values for schemas and diagnostics.
func TrustLevelStrings() []string {
	return StringValues([]TrustLevel{TrustSourceOriginal, TrustUserAsserted, TrustModelExtracted, TrustModelSynthesized, TrustExternallyVerified})
}

// LifecycleStatusStrings returns full lifecycle vocabulary values for schemas and diagnostics.
func LifecycleStatusStrings() []string {
	return StringValues([]LifecycleStatus{StatusActive, StatusSuperseded, StatusDeprecated, StatusArchived, StatusDeleted})
}

// MemoryStatusStrings returns memory-exposed lifecycle values for schemas and diagnostics.
func MemoryStatusStrings() []string {
	return StringValues([]LifecycleStatus{StatusActive, StatusSuperseded, StatusDeprecated, StatusArchived})
}

// ValidFirewall reports whether firewall is a safe memory firewall id.
func ValidFirewall(firewall Firewall) bool {
	value := string(firewall)
	if len(value) == 0 || len(value) > 64 {
		return false
	}
	for index, char := range value {
		validLower := char >= 'a' && char <= 'z'
		validDigit := char >= '0' && char <= '9'
		validSeparator := char == '-' || char == '_'
		if index == 0 && !validLower && !validDigit {
			return false
		}
		if !validLower && !validDigit && !validSeparator {
			return false
		}
	}
	return true
}

// ValidSensitivity reports whether sensitivity is in the controlled vocabulary.
func ValidSensitivity(sensitivity Sensitivity) bool {
	switch sensitivity {
	case SensitivityPublic, SensitivityInternal, SensitivityPrivate, SensitivityRestricted:
		return true
	default:
		return false
	}
}

// ValidTrustLevel reports whether trust is in the controlled vocabulary.
func ValidTrustLevel(trust TrustLevel) bool {
	switch trust {
	case TrustSourceOriginal, TrustUserAsserted, TrustModelExtracted, TrustModelSynthesized, TrustExternallyVerified:
		return true
	default:
		return false
	}
}

// ValidLifecycleStatus reports whether status is in the full lifecycle vocabulary.
func ValidLifecycleStatus(status LifecycleStatus) bool {
	switch status {
	case StatusActive, StatusSuperseded, StatusDeprecated, StatusArchived, StatusDeleted:
		return true
	default:
		return false
	}
}

// ValidMemoryStatus reports whether status is exposed by memory DTOs.
func ValidMemoryStatus(status LifecycleStatus) bool {
	switch status {
	case StatusActive, StatusSuperseded, StatusDeprecated, StatusArchived:
		return true
	default:
		return false
	}
}

// DefaultFirewall returns the user firewall when firewall is blank.
func DefaultFirewall(firewall Firewall) Firewall {
	if firewall == "" {
		return FirewallUser
	}
	return firewall
}

// DefaultSensitivity returns private sensitivity when sensitivity is blank.
func DefaultSensitivity(sensitivity Sensitivity) Sensitivity {
	if sensitivity == "" {
		return SensitivityPrivate
	}
	return sensitivity
}

// DefaultTrustLevel returns fallback when trust is blank.
func DefaultTrustLevel(trust TrustLevel, fallback TrustLevel) TrustLevel {
	if trust == "" {
		return fallback
	}
	return trust
}

// DefaultLifecycleStatus returns active lifecycle status when status is blank.
func DefaultLifecycleStatus(status LifecycleStatus) LifecycleStatus {
	if status == "" {
		return StatusActive
	}
	return status
}

// StringValues converts typed vocabulary values to plain strings.
func StringValues[T ~string](values []T) []string {
	strings := make([]string, 0, len(values))
	for _, value := range values {
		strings = append(strings, string(value))
	}
	return strings
}
