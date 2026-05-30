// This file projects typed codebase catalog records onto the context graph.
package repository

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"strings"

	"memory/internal/memory/domain"
	graph "memory/internal/memory/graph/domain"
	graphstore "memory/internal/memory/graph/store"
)

const (
	codebasePropertyAliases            = "aliases"
	codebasePropertyRepositoryPath     = "repository_path"
	codebasePropertyDefaultRemote      = "default_remote"
	codebasePropertyDefaultBranch      = "default_branch"
	codebasePropertyProvider           = "provider"
	codebasePropertyProviderRepository = "provider_repository"
	codebasePropertyRuntimeTargetID    = "runtime_target_id"
	codebasePropertyAgentProfileID     = "agent_profile_id"
)

// UpsertCodebase stores or updates one durable codebase catalog entry.
func (r *Repository) UpsertCodebase(ctx context.Context, req domain.UpsertCodebaseRequest) (domain.Codebase, error) {
	normalized, err := domain.NormalizeUpsertCodebaseRequest(req)
	if err != nil {
		return domain.Codebase{}, err
	}
	var saved domain.Codebase
	if err := r.graph.WithUnitOfWork(ctx, func(graphStore *graphstore.Store) error {
		txRepo := *r
		txRepo.graph = graphStore
		record, err := txRepo.upsertCodebaseNormalized(ctx, normalized)
		if err != nil {
			return err
		}
		saved = record
		return nil
	}); err != nil {
		return domain.Codebase{}, err
	}
	return saved, nil
}

// GetCodebase loads one durable codebase catalog entry by stable id.
func (r *Repository) GetCodebase(ctx context.Context, req domain.CodebaseIDRequest) (domain.Codebase, error) {
	normalized, err := domain.NormalizeCodebaseIDRequest(req)
	if err != nil {
		return domain.Codebase{}, err
	}
	node, err := r.graph.GetNodeByStableKey(ctx, graph.KindCodebase, codebaseStableKey(normalized.ID))
	if err != nil {
		return domain.Codebase{}, fmt.Errorf("codebase %q not found: %w", normalized.ID, err)
	}
	if node.Status == graph.StatusDeleted {
		return domain.Codebase{}, sql.ErrNoRows
	}
	return r.codebaseFromNode(ctx, node)
}

// ListCodebases returns durable codebase catalog entries matching a query.
func (r *Repository) ListCodebases(ctx context.Context, req domain.CodebaseQuery) ([]domain.Codebase, error) {
	normalized, err := domain.NormalizeCodebaseQuery(req)
	if err != nil {
		return nil, err
	}
	nodes, err := r.graph.SearchNodes(ctx, graph.SearchNodesQuery{
		Text:                 normalized.Text,
		Kinds:                []graph.NodeKind{graph.KindCodebase},
		Firewall:             graph.FirewallUser,
		AllowedSensitivities: graph.DefaultReadableSensitivities(),
		Limit:                normalized.Limit,
	})
	if err != nil {
		return nil, err
	}
	codebases := make([]domain.Codebase, 0, len(nodes))
	for _, node := range nodes {
		codebase, err := r.codebaseFromNode(ctx, node)
		if err != nil {
			return nil, err
		}
		codebases = append(codebases, codebase)
	}
	return codebases, nil
}

// ResolveCodebase resolves one human phrase to a strong codebase match or ambiguity.
func (r *Repository) ResolveCodebase(ctx context.Context, req domain.ResolveCodebaseRequest) (domain.CodebaseResolution, error) {
	normalized, err := domain.NormalizeResolveCodebaseRequest(req)
	if err != nil {
		return domain.CodebaseResolution{}, err
	}
	all, err := r.ListCodebases(ctx, domain.CodebaseQuery{Limit: 100})
	if err != nil {
		return domain.CodebaseResolution{}, err
	}
	matches := exactCodebaseMatches(all, normalized.Query)
	if len(matches) == 1 {
		return domain.CodebaseResolution{Status: "matched", Codebase: &matches[0].Codebase, Matches: matches}, nil
	}
	if len(matches) > 1 {
		return domain.CodebaseResolution{Status: "ambiguous", Matches: matches, Diagnostics: []string{"multiple codebases matched the requested name or alias"}}, nil
	}
	searched, err := r.ListCodebases(ctx, domain.CodebaseQuery{Text: normalized.Query, Limit: 10})
	if err != nil {
		return domain.CodebaseResolution{}, err
	}
	searchMatches := searchCodebaseMatches(searched, normalized.Query)
	if len(searchMatches) == 1 {
		return domain.CodebaseResolution{Status: "matched", Codebase: &searchMatches[0].Codebase, Matches: searchMatches}, nil
	}
	if len(searchMatches) > 1 {
		return domain.CodebaseResolution{Status: "ambiguous", Matches: searchMatches, Diagnostics: []string{"multiple codebases matched the search text"}}, nil
	}
	return domain.CodebaseResolution{Status: "not_found", Diagnostics: []string{"no codebase matched the request"}}, nil
}

// DeleteCodebase lifecycle-deletes one durable codebase catalog entry.
func (r *Repository) DeleteCodebase(ctx context.Context, req domain.CodebaseIDRequest) error {
	normalized, err := domain.NormalizeCodebaseIDRequest(req)
	if err != nil {
		return err
	}
	node, err := r.graph.GetNodeByStableKey(ctx, graph.KindCodebase, codebaseStableKey(normalized.ID))
	if err != nil {
		return fmt.Errorf("codebase %q not found: %w", normalized.ID, err)
	}
	if _, err := r.graph.SetNodeStatus(ctx, node.ID, graph.StatusDeleted, normalized.Actor); err != nil {
		return err
	}
	return r.graph.ReindexNode(ctx, node.ID)
}

// upsertCodebaseNormalized writes one validated codebase into the active graph store.
func (r *Repository) upsertCodebaseNormalized(ctx context.Context, req domain.UpsertCodebaseRequest) (domain.Codebase, error) {
	node, err := r.graph.UpsertNode(ctx, graph.UpsertNodeRequest{
		Kind:        graph.KindCodebase,
		StableKey:   codebaseStableKey(req.Codebase.ID),
		Title:       req.Codebase.Name,
		Summary:     codebaseSummary(req.Codebase),
		Firewall:    graph.FirewallUser,
		Sensitivity: graph.SensitivityPrivate,
		TrustLevel:  graph.TrustUserAsserted,
		Actor:       req.Actor,
	})
	if err != nil {
		return domain.Codebase{}, err
	}
	if err := r.writeCodebaseProperties(ctx, node.ID, req.Codebase, req.Actor); err != nil {
		return domain.Codebase{}, err
	}
	if err := r.graph.DeleteNodeAliases(ctx, node.ID); err != nil {
		return domain.Codebase{}, err
	}
	for _, alias := range req.Codebase.Aliases {
		if _, err := r.graph.UpsertAlias(ctx, graph.UpsertAliasRequest{NodeID: node.ID, Alias: alias, Kind: "codebase"}); err != nil {
			return domain.Codebase{}, err
		}
	}
	if err := r.graph.ReindexNode(ctx, node.ID); err != nil {
		return domain.Codebase{}, err
	}
	return r.codebaseFromNode(ctx, node)
}

// writeCodebaseProperties stores all dumb codebase data fields as graph properties.
func (r *Repository) writeCodebaseProperties(ctx context.Context, nodeID graph.NodeID, codebase domain.Codebase, actor string) error {
	aliases, err := json.Marshal(codebase.Aliases)
	if err != nil {
		return fmt.Errorf("encode codebase aliases: %w", err)
	}
	properties := map[string]graph.Value{
		codebasePropertyAliases:            {Type: graph.ValueJSON, JSON: string(aliases)},
		codebasePropertyRepositoryPath:     {Type: graph.ValueText, Text: codebase.RepositoryPath},
		codebasePropertyDefaultRemote:      {Type: graph.ValueText, Text: codebase.DefaultRemote},
		codebasePropertyDefaultBranch:      {Type: graph.ValueText, Text: codebase.DefaultBranch},
		codebasePropertyProvider:           {Type: graph.ValueText, Text: codebase.Provider},
		codebasePropertyProviderRepository: {Type: graph.ValueText, Text: codebase.ProviderRepository},
		codebasePropertyRuntimeTargetID:    {Type: graph.ValueText, Text: codebase.RuntimeTargetID},
		codebasePropertyAgentProfileID:     {Type: graph.ValueText, Text: codebase.AgentProfileID},
	}
	for key, value := range properties {
		if _, err := r.graph.UpsertNodeProperty(ctx, graph.UpsertNodePropertyRequest{
			NodeID:     nodeID,
			Key:        key,
			Value:      value,
			TrustLevel: graph.TrustUserAsserted,
			Actor:      actor,
		}); err != nil {
			return err
		}
	}
	return nil
}

// codebaseFromNode projects one graph node and its properties into a DTO.
func (r *Repository) codebaseFromNode(ctx context.Context, node graph.Node) (domain.Codebase, error) {
	props, err := r.graph.ListNodeProperties(ctx, node.ID)
	if err != nil {
		return domain.Codebase{}, err
	}
	values := map[string]graph.Value{}
	for _, prop := range props {
		values[prop.Key] = prop.Value
	}
	codebase := domain.Codebase{
		ID:                 strings.TrimPrefix(node.StableKey, "codebase:"),
		Name:               node.Title,
		RepositoryPath:     codebaseTextProperty(values, codebasePropertyRepositoryPath),
		DefaultRemote:      codebaseTextProperty(values, codebasePropertyDefaultRemote),
		DefaultBranch:      codebaseTextProperty(values, codebasePropertyDefaultBranch),
		Provider:           codebaseTextProperty(values, codebasePropertyProvider),
		ProviderRepository: codebaseTextProperty(values, codebasePropertyProviderRepository),
		RuntimeTargetID:    codebaseTextProperty(values, codebasePropertyRuntimeTargetID),
		AgentProfileID:     codebaseTextProperty(values, codebasePropertyAgentProfileID),
		CreatedAt:          node.CreatedAt,
		UpdatedAt:          node.UpdatedAt,
	}
	if raw := values[codebasePropertyAliases].JSON; strings.TrimSpace(raw) != "" {
		if err := json.Unmarshal([]byte(raw), &codebase.Aliases); err != nil {
			return domain.Codebase{}, fmt.Errorf("decode codebase aliases: %w", err)
		}
	}
	return codebase, nil
}

// codebaseTextProperty returns one text property value by key.
func codebaseTextProperty(values map[string]graph.Value, key string) string {
	return values[key].Text
}

// exactCodebaseMatches returns deterministic exact id, name, or alias matches.
func exactCodebaseMatches(codebases []domain.Codebase, query string) []domain.CodebaseMatch {
	normalized := strings.ToLower(strings.TrimSpace(query))
	matches := []domain.CodebaseMatch{}
	for _, codebase := range codebases {
		switch {
		case codebase.ID == normalized:
			matches = append(matches, domain.CodebaseMatch{Codebase: codebase, Confidence: 1, Reason: "id"})
		case strings.ToLower(codebase.Name) == normalized:
			matches = append(matches, domain.CodebaseMatch{Codebase: codebase, Confidence: 1, Reason: "name"})
		case containsString(codebase.Aliases, normalized):
			matches = append(matches, domain.CodebaseMatch{Codebase: codebase, Confidence: 0.98, Reason: "alias"})
		}
	}
	return matches
}

// searchCodebaseMatches wraps graph search results as lower-confidence candidates.
func searchCodebaseMatches(codebases []domain.Codebase, query string) []domain.CodebaseMatch {
	if strings.TrimSpace(query) == "" {
		return nil
	}
	matches := make([]domain.CodebaseMatch, 0, len(codebases))
	for _, codebase := range codebases {
		matches = append(matches, domain.CodebaseMatch{Codebase: codebase, Confidence: 0.75, Reason: "search"})
	}
	return matches
}

// containsString reports whether values contains one exact string.
func containsString(values []string, target string) bool {
	for _, value := range values {
		if value == target {
			return true
		}
	}
	return false
}

// codebaseStableKey returns a graph stable key for one catalog id.
func codebaseStableKey(id string) string {
	return "codebase:" + id
}

// codebaseSummary returns display-safe searchable codebase metadata.
func codebaseSummary(codebase domain.Codebase) string {
	values := []string{codebase.RepositoryPath, codebase.Provider, codebase.ProviderRepository, codebase.DefaultBranch}
	out := []string{}
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			out = append(out, strings.TrimSpace(value))
		}
	}
	return strings.Join(out, " ")
}
