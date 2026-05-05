package domain

import (
	"errors"
	"fmt"
	"strings"
)

// NormalizeGraphQueryRequest validates shared graph query request metadata.
func NormalizeGraphQueryRequest(req GraphQueryRequest) (GraphQueryRequest, error) {
	req.Actor = normalizeDefault(req.Actor, "agent")
	req.Query = strings.TrimSpace(req.Query)
	req.SourceNodeID = strings.TrimSpace(req.SourceNodeID)
	if req.Query == "" {
		return req, errors.New("query is required")
	}
	if req.Scope == "" {
		req.Scope = ScopeUser
	}
	if !ValidScope(req.Scope) {
		return req, fmt.Errorf("invalid scope %q", req.Scope)
	}
	if len(req.AllowedSensitivities) == 0 {
		req.AllowedSensitivities = []Sensitivity{SensitivityPublic, SensitivityInternal, SensitivityPrivate}
	}
	for _, sensitivity := range req.AllowedSensitivities {
		if !ValidSensitivity(sensitivity) {
			return req, fmt.Errorf("invalid sensitivity %q", sensitivity)
		}
	}
	return req, nil
}
