// This file authorizes memory service operations against firewall policy.
package service

import (
	"fmt"
	"strings"

	"memory/internal/memory/domain"
)

// authorizeRead verifies an actor can read one firewall.
func (s *Service) authorizeRead(actor string, firewall domain.Firewall) error {
	if s.firewallPolicy == nil {
		return nil
	}
	if s.firewallPolicy.AllowsRead(actor, firewall) {
		return nil
	}
	return fmt.Errorf("actor %q cannot read memory firewall %q", actor, firewall)
}

// authorizeWrite verifies an actor can mutate one firewall.
func (s *Service) authorizeWrite(actor string, firewall domain.Firewall) error {
	if s.firewallPolicy == nil {
		return nil
	}
	if s.firewallPolicy.AllowsWrite(actor, firewall) {
		return nil
	}
	return fmt.Errorf("actor %q cannot write memory firewall %q", actor, firewall)
}

// authorizeRetrieval verifies a retrieval query can read every requested firewall.
func (s *Service) authorizeRetrieval(q domain.RetrievalQuery) error {
	if err := s.authorizeRead(q.Actor, q.Firewall); err != nil {
		return err
	}
	if q.IncludeGlobal && q.Firewall != domain.FirewallGlobal {
		return s.authorizeRead(q.Actor, domain.FirewallGlobal)
	}
	return nil
}

// authorizeGraphQuery verifies a graph query can read or write its firewall.
func (s *Service) authorizeGraphQuery(req domain.GraphQueryRequest) error {
	if graphQueryMutates(req.Query) {
		return s.authorizeWrite(req.Actor, req.Firewall)
	}
	if err := s.authorizeRead(req.Actor, req.Firewall); err != nil {
		return err
	}
	if req.IncludeGlobal && req.Firewall != domain.FirewallGlobal {
		return s.authorizeRead(req.Actor, domain.FirewallGlobal)
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
