// This file implements Google's ADK memory.Service interface.
package adkmemory

import (
	"context"
	"fmt"
	"strings"

	"agentawesome/internal/config/schema"
	"github.com/rs/zerolog/log"
	adkmemory "google.golang.org/adk/memory"
	"google.golang.org/adk/session"
	"google.golang.org/genai"
)

const (
	actorName             = "agentawesome-harness"
	saveMemoryToolName    = "save_memory_candidate"
	searchMemoryToolName  = "search_memory"
	searchSourcesToolName = "search_sources"
	conversationKind      = "conversation"
	userScope             = "user"
	privateSensitivity    = "private"
	sourceTrustLevel      = "source_original"
	defaultSearchLimit    = 12
)

// Service stores and retrieves ADK chat memory through the memory MCP server.
type Service struct {
	server              schema.MCPServer
	searchTool          string
	sessionDatabasePath string
}

var _ adkmemory.Service = (*Service)(nil)

// New creates a memory service backed by one configured MCP server.
func New(server schema.MCPServer, sessionDatabasePath ...string) *Service {
	return &Service{
		server:              server,
		searchTool:          preferredSearchTool(server.Tools.Allow),
		sessionDatabasePath: firstSessionDatabasePath(sessionDatabasePath),
	}
}

// AddSessionToMemory persists text chat events from one ADK session.
func (s *Service) AddSessionToMemory(ctx context.Context, curSession session.Session) error {
	if curSession == nil {
		return nil
	}
	mcpSession, err := s.connect(ctx)
	if err != nil {
		return fmt.Errorf("connect memory MCP: %w", err)
	}
	defer mcpSession.Close()

	for event := range curSession.Events().All() {
		payload, ok := capturePayload(curSession, event)
		if !ok {
			continue
		}
		if _, err := callTool(ctx, mcpSession, saveMemoryToolName, payload); err != nil {
			return err
		}
	}
	return nil
}

// SearchMemory returns prior chat memories relevant to an ADK query.
func (s *Service) SearchMemory(ctx context.Context, req *adkmemory.SearchRequest) (*adkmemory.SearchResponse, error) {
	if req == nil {
		return &adkmemory.SearchResponse{}, nil
	}
	query := cleanSessionText(req.Query)
	if strings.TrimSpace(query) == "" {
		return &adkmemory.SearchResponse{}, nil
	}
	response := &adkmemory.SearchResponse{}
	mcpSession, err := s.connect(ctx)
	if err != nil {
		log.Warn().Err(err).Msg("search ADK memory unavailable")
	} else {
		defer mcpSession.Close()
		content, err := callTool(ctx, mcpSession, s.searchTool, searchPayload(query))
		if err != nil {
			log.Warn().Err(err).Msg("search ADK memory failed")
		} else if bundle, err := decodeStructured[retrievalBundle](content); err != nil {
			log.Warn().Err(err).Msg("decode ADK memory search result failed")
		} else {
			response = searchResponseFromBundle(bundle)
		}
	}
	sessionEntries, err := searchSessionEvents(ctx, s.sessionDatabasePath, req, query)
	if err != nil {
		log.Warn().Err(err).Msg("search ADK session history failed")
		return response, nil
	}
	response.Memories = appendMemoryEntries(response.Memories, sessionEntries...)
	return response, nil
}

// firstSessionDatabasePath returns the optional exact-session search path.
func firstSessionDatabasePath(paths []string) string {
	if len(paths) == 0 {
		return ""
	}
	return strings.TrimSpace(paths[0])
}

// appendMemoryEntries appends entries not already present by ID.
func appendMemoryEntries(entries []adkmemory.Entry, next ...adkmemory.Entry) []adkmemory.Entry {
	seen := make(map[string]struct{}, len(entries))
	for _, entry := range entries {
		if entry.ID != "" {
			seen[entry.ID] = struct{}{}
		}
	}
	for _, entry := range next {
		if entry.ID != "" {
			if _, ok := seen[entry.ID]; ok {
				continue
			}
			seen[entry.ID] = struct{}{}
		}
		entries = append(entries, entry)
	}
	return entries
}

// searchPayload builds a memory search request for user-scoped conversations.
func searchPayload(query string) map[string]any {
	return map[string]any{
		"actor":                 actorName,
		"scope":                 userScope,
		"text":                  query,
		"kinds":                 []string{conversationKind},
		"allowed_sensitivities": []string{"public", "internal", privateSensitivity},
		"limit":                 defaultSearchLimit,
	}
}

// searchResponseFromBundle maps Agent Awesome records into ADK memory entries.
func searchResponseFromBundle(bundle retrievalBundle) *adkmemory.SearchResponse {
	response := &adkmemory.SearchResponse{
		Memories: make([]adkmemory.Entry, 0, len(bundle.Primary)),
	}
	for _, record := range bundle.Primary {
		text := recordText(record)
		if strings.TrimSpace(text) == "" {
			continue
		}
		response.Memories = append(response.Memories, adkmemory.Entry{
			ID:        record.ID,
			Content:   genai.NewContentFromText(text, genai.RoleUser),
			Author:    recordAuthor(record),
			Timestamp: recordTimestamp(record),
			CustomMetadata: map[string]any{
				"memory_id":   record.ID,
				"evidence_id": record.EvidenceID,
				"source":      record.Source,
			},
		})
	}
	return response
}
