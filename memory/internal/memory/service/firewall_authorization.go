// This file authorizes memory service operations against firewall policy.
package service

import (
	"fmt"
	"os"
	"strings"

	"memory/internal/memory/domain"
)

// authorizeRead verifies an actor can read one memory domain.
func (s *Service) authorizeRead(actor string, firewall domain.Firewall) error {
	policy, err := s.firewallPolicyForAuthorization()
	if err != nil {
		return err
	}
	if policy == nil {
		return nil
	}
	if policy.AllowsRead(actor, firewall) {
		return nil
	}
	return fmt.Errorf("actor %q cannot read memory domain %q", actor, firewall)
}

// authorizeWrite verifies an actor can mutate one memory domain.
func (s *Service) authorizeWrite(actor string, firewall domain.Firewall) error {
	policy, err := s.firewallPolicyForAuthorization()
	if err != nil {
		return err
	}
	if policy == nil {
		return nil
	}
	if policy.AllowsWrite(actor, firewall) {
		return nil
	}
	return fmt.Errorf("actor %q cannot write memory domain %q", actor, firewall)
}

// firewallPolicyForAuthorization reloads the domain policy when its file changes.
func (s *Service) firewallPolicyForAuthorization() (*FirewallPolicy, error) {
	if s.firewallPolicyPath == "" {
		return s.firewallPolicy, nil
	}
	stat, err := os.Stat(s.firewallPolicyPath)
	if err != nil {
		return nil, fmt.Errorf("stat memory domain policy: %w", err)
	}
	if stat.IsDir() {
		return nil, fmt.Errorf("memory domain policy path is a directory")
	}
	s.firewallPolicyMu.Lock()
	defer s.firewallPolicyMu.Unlock()
	policy, err := LoadFirewallPolicyFile(s.firewallPolicyPath)
	if err != nil {
		return nil, err
	}
	s.firewallPolicy = policy
	return s.firewallPolicy, nil
}

// authorizeRetrieval verifies a retrieval query can read every requested domain.
func (s *Service) authorizeRetrieval(q domain.RetrievalQuery) error {
	if err := s.authorizeRead(q.Actor, q.DomainID); err != nil {
		return err
	}
	if q.IncludeGlobal && q.DomainID != domain.DomainGlobal {
		return s.authorizeRead(q.Actor, domain.DomainGlobal)
	}
	return nil
}

// authorizeGraphQuery verifies a graph query can read or write its domain.
func (s *Service) authorizeGraphQuery(req domain.GraphQueryRequest) error {
	if graphQueryMutates(req.Query) {
		return s.authorizeWrite(req.Actor, req.DomainID)
	}
	if err := s.authorizeRead(req.Actor, req.DomainID); err != nil {
		return err
	}
	if req.IncludeGlobal && req.DomainID != domain.DomainGlobal {
		return s.authorizeRead(req.Actor, domain.DomainGlobal)
	}
	return nil
}

// graphQueryMutates reports whether a graph query writes graph state.
func graphQueryMutates(query string) bool {
	normalized := strings.ToUpper(strings.TrimSpace(query))
	return strings.HasPrefix(normalized, "INSERT ") ||
		strings.HasPrefix(normalized, "SET ") ||
		strings.HasPrefix(normalized, "DELETE ")
}
