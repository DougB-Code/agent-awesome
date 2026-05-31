package domain

import (
	"errors"
	"fmt"
	"strings"

	"memory/internal/memory/normalize"
	"memory/internal/memory/vocabulary"
)

// NormalizeGraphQueryRequest validates shared graph query request metadata.
func NormalizeGraphQueryRequest(req GraphQueryRequest) (GraphQueryRequest, error) {
	req.Actor = normalize.Default(req.Actor, vocabulary.DefaultAgentActor)
	req.Query = strings.TrimSpace(req.Query)
	req.SourceNodeID = strings.TrimSpace(req.SourceNodeID)
	if req.Query == "" {
		return req, errors.New("query is required")
	}
	domainID, err := NormalizeDomainID(req.DomainID, req.Firewall)
	if err != nil {
		return req, err
	}
	req.DomainID = domainID
	req.Firewall = domainID
	if len(req.AllowedSensitivities) == 0 {
		req.AllowedSensitivities = vocabulary.DefaultReadableSensitivities()
	}
	for _, sensitivity := range req.AllowedSensitivities {
		if !ValidSensitivity(sensitivity) {
			return req, fmt.Errorf("invalid sensitivity %q", sensitivity)
		}
	}
	return req, nil
}
