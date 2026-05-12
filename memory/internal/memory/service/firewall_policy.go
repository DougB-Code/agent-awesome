// This file defines memory firewall access policy for process-boundary calls.
package service

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"

	"memory/internal/memory/domain"
)

// FirewallPolicy controls actor access to memory firewalls.
type FirewallPolicy struct {
	// DefaultAllow controls access when no explicit firewall rule matches.
	DefaultAllow bool `json:"default_allow"`

	// Firewalls maps firewall ids to actor read and write grants.
	Firewalls []FirewallRule `json:"firewalls"`
}

// FirewallRule stores actor grants for one memory firewall.
type FirewallRule struct {
	// Firewall is the memory firewall id the rule protects.
	Firewall domain.Firewall `json:"firewall"`

	// Readers can retrieve records from this firewall.
	Readers []string `json:"readers"`

	// Writers can create, repair, or rebuild records in this firewall.
	Writers []string `json:"writers"`
}

// LoadFirewallPolicyFile reads a JSON firewall policy file.
func LoadFirewallPolicyFile(path string) (*FirewallPolicy, error) {
	if strings.TrimSpace(path) == "" {
		return nil, nil
	}
	content, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read firewall policy: %w", err)
	}
	var policy FirewallPolicy
	if err := json.Unmarshal(content, &policy); err != nil {
		return nil, fmt.Errorf("parse firewall policy: %w", err)
	}
	normalized, err := NormalizeFirewallPolicy(policy)
	if err != nil {
		return nil, err
	}
	return &normalized, nil
}

// NormalizeFirewallPolicy trims actors, drops duplicate grants, and validates firewalls.
func NormalizeFirewallPolicy(policy FirewallPolicy) (FirewallPolicy, error) {
	normalized := FirewallPolicy{DefaultAllow: policy.DefaultAllow}
	for _, rule := range policy.Firewalls {
		rule.Firewall = domain.Firewall(strings.TrimSpace(string(rule.Firewall)))
		if rule.Firewall == "" {
			continue
		}
		if !domain.ValidFirewall(rule.Firewall) {
			return FirewallPolicy{}, fmt.Errorf("invalid firewall policy firewall %q", rule.Firewall)
		}
		normalized.Firewalls = append(normalized.Firewalls, FirewallRule{
			Firewall: rule.Firewall,
			Readers:  normalizePolicyActors(rule.Readers),
			Writers:  normalizePolicyActors(rule.Writers),
		})
	}
	return normalized, nil
}

// AllowsRead reports whether an actor may retrieve from one firewall.
func (p FirewallPolicy) AllowsRead(actor string, firewall domain.Firewall) bool {
	rule, ok := p.ruleFor(firewall)
	if !ok {
		return p.DefaultAllow
	}
	return actorAllowed(actor, rule.Readers) || actorAllowed(actor, rule.Writers)
}

// AllowsWrite reports whether an actor may mutate one firewall.
func (p FirewallPolicy) AllowsWrite(actor string, firewall domain.Firewall) bool {
	rule, ok := p.ruleFor(firewall)
	if !ok {
		return p.DefaultAllow
	}
	return actorAllowed(actor, rule.Writers)
}

// ruleFor returns the first rule matching a firewall.
func (p FirewallPolicy) ruleFor(firewall domain.Firewall) (FirewallRule, bool) {
	for _, rule := range p.Firewalls {
		if rule.Firewall == firewall {
			return rule, true
		}
	}
	return FirewallRule{}, false
}

// normalizePolicyActors trims, lowercases, and deduplicates policy actors.
func normalizePolicyActors(actors []string) []string {
	seen := map[string]bool{}
	normalized := []string{}
	for _, actor := range actors {
		key := normalizePolicyActor(actor)
		if key == "" || seen[key] {
			continue
		}
		seen[key] = true
		normalized = append(normalized, key)
	}
	return normalized
}

// actorAllowed reports whether an actor matches a grant list.
func actorAllowed(actor string, grants []string) bool {
	key := normalizePolicyActor(actor)
	if key == "" {
		return false
	}
	for _, grant := range grants {
		if grant == "*" || grant == key {
			return true
		}
	}
	return false
}

// normalizePolicyActor returns the comparable actor principal key.
func normalizePolicyActor(actor string) string {
	return strings.ToLower(strings.TrimSpace(actor))
}
