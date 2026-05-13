// This file implements Google's ADK memory.Service interface.
package adkmemory

import (
	"context"
	"fmt"
	"sort"
	"strings"
	"sync"

	"github.com/modelcontextprotocol/go-sdk/mcp"
	"github.com/rs/zerolog/log"
	adkmemory "google.golang.org/adk/memory"
	"google.golang.org/adk/session"
	"google.golang.org/genai"
)

const (
	saveMemoryToolName    = "save_memory_candidate"
	searchMemoryToolName  = "search_memory"
	searchSourcesToolName = "search_sources"
	conversationKind      = "conversation"
	userFirewall          = "user"
	privateSensitivity    = "private"
	sourceTrustLevel      = "source_original"
	defaultSearchLimit    = 12
)

// Service stores and retrieves ADK chat memory through memory domains.
type Service struct {
	actor                string
	domains              []memoryDomain
	defaultWriteDomain   string
	writeDomains         map[string]struct{}
	allowedFlows         map[string]map[string]struct{}
	allowedSensitivities []string
	mu                   sync.Mutex
	sessionEventCursor   map[string]int
	turnSourceDomains    map[string]map[string]struct{}
}

var _ adkmemory.Service = (*Service)(nil)

// New creates a memory service backed by configured memory domains.
func New(runtime memoryRuntimeConfig) *Service {
	return &Service{
		actor:                runtime.actor,
		domains:              runtime.domains,
		defaultWriteDomain:   runtime.defaultWriteDomain,
		writeDomains:         runtime.writeDomains,
		allowedFlows:         runtime.allowedFlows,
		allowedSensitivities: runtime.allowedSensitivities,
		sessionEventCursor:   make(map[string]int),
		turnSourceDomains:    make(map[string]map[string]struct{}),
	}
}

// AddSessionToMemory persists text chat events from one ADK session.
func (s *Service) AddSessionToMemory(ctx context.Context, curSession session.Session) error {
	if curSession == nil {
		return nil
	}
	events := curSession.Events()
	if events == nil {
		return nil
	}
	eventCount := events.Len()
	cursorKey, start := s.nextCaptureStart(curSession, eventCount)
	writeDomain, ok := s.defaultWriteMemoryDomain()
	if !ok {
		return nil
	}
	var mcpSession *mcp.ClientSession
	for index := start; index < eventCount; index++ {
		event := events.At(index)
		payload, ok := capturePayload(curSession, event, s.actor)
		if !ok {
			s.markCapturedThrough(cursorKey, index+1)
			continue
		}
		sourceDomains, allowed := s.sourceDomainsForEvent(curSession, event)
		if !allowed || !s.canWriteFromSources(writeDomain.id, sourceDomains) {
			log.Warn().
				Str("write_domain", writeDomain.id).
				Strs("source_domains", setValues(sourceDomains)).
				Msg("skip ADK memory capture blocked by domain flow policy")
			s.markCapturedThrough(cursorKey, index+1)
			continue
		}
		if mcpSession == nil {
			var err error
			mcpSession, err = s.connect(ctx, writeDomain.server)
			if err != nil {
				return fmt.Errorf("connect memory MCP: %w", err)
			}
			defer mcpSession.Close()
		}
		if _, err := callTool(ctx, mcpSession, saveMemoryToolName, payload); err != nil {
			return err
		}
		s.markCapturedThrough(cursorKey, index+1)
	}
	s.clearTurnSourceDomains(curSession)
	return nil
}

// nextCaptureStart returns the first uncaptured event index for one ADK session.
func (s *Service) nextCaptureStart(curSession session.Session, eventCount int) (string, int) {
	key := sessionEventCursorKey(curSession)
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.sessionEventCursor == nil {
		s.sessionEventCursor = make(map[string]int)
	}
	start := s.sessionEventCursor[key]
	if start > eventCount {
		s.sessionEventCursor[key] = 0
		return key, 0
	}
	return key, start
}

// markCapturedThrough advances the captured event cursor for one ADK session.
func (s *Service) markCapturedThrough(cursorKey string, nextIndex int) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.sessionEventCursor == nil {
		s.sessionEventCursor = make(map[string]int)
	}
	if nextIndex > s.sessionEventCursor[cursorKey] {
		s.sessionEventCursor[cursorKey] = nextIndex
	}
}

// sessionEventCursorKey identifies the append-only event stream for one session.
func sessionEventCursorKey(curSession session.Session) string {
	return curSession.AppName() + ":" + curSession.UserID() + ":" + curSession.ID()
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
	for _, domain := range s.domains {
		mcpSession, err := s.connect(ctx, domain.server)
		if err != nil {
			log.Warn().Err(err).Str("domain", domain.id).Msg("search ADK memory unavailable")
			continue
		}
		defer mcpSession.Close()
		content, err := callTool(ctx, mcpSession, domain.searchTool, s.searchPayload(query))
		if err != nil {
			log.Warn().Err(err).Str("domain", domain.id).Msg("search ADK memory failed")
		} else if bundle, err := decodeStructured[retrievalBundle](content); err != nil {
			log.Warn().Err(err).Str("domain", domain.id).Msg("decode ADK memory search result failed")
		} else {
			domainResponse := searchResponseFromBundle(domain.id, bundle)
			if len(domainResponse.Memories) > 0 {
				s.markTurnSourceDomain(req, domain.id)
			}
			response.Memories = appendMemoryEntries(response.Memories, domainResponse.Memories...)
		}
	}
	return response, nil
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

// searchPayload builds a memory search request for granted conversations.
func (s *Service) searchPayload(query string) map[string]any {
	allowed := s.allowedSensitivities
	if len(allowed) == 0 {
		allowed = []string{"public", "internal", privateSensitivity}
	}
	return map[string]any{
		"actor":                 s.actor,
		"firewall":              userFirewall,
		"text":                  query,
		"kinds":                 []string{conversationKind},
		"allowed_sensitivities": allowed,
		"limit":                 defaultSearchLimit,
	}
}

// sourceDomainsForEvent returns memory domains that may have informed an event.
func (s *Service) sourceDomainsForEvent(curSession session.Session, event *session.Event) (map[string]struct{}, bool) {
	if eventSpeaker(event) == "user" {
		return nil, true
	}
	sources := s.turnSourcesForSession(curSession)
	if len(sources) > 0 {
		return sources, true
	}
	if len(s.domains) == 1 {
		return map[string]struct{}{s.domains[0].id: {}}, true
	}
	return nil, false
}

// canWriteFromSources enforces default-deny cross-domain memory writes.
func (s *Service) canWriteFromSources(destination string, sources map[string]struct{}) bool {
	if _, ok := s.writeDomains[destination]; !ok {
		return false
	}
	for source := range sources {
		if source == destination {
			continue
		}
		if allowed, ok := s.allowedFlows[source]; !ok {
			return false
		} else if _, ok := allowed[destination]; !ok {
			return false
		}
	}
	return true
}

// markTurnSourceDomain records a domain that supplied memory to the turn.
func (s *Service) markTurnSourceDomain(req *adkmemory.SearchRequest, domainID string) {
	key := searchTurnKey(req.AppName, req.UserID)
	if key == "" {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.turnSourceDomains == nil {
		s.turnSourceDomains = make(map[string]map[string]struct{})
	}
	if s.turnSourceDomains[key] == nil {
		s.turnSourceDomains[key] = map[string]struct{}{}
	}
	s.turnSourceDomains[key][domainID] = struct{}{}
}

// turnSourcesForSession returns a copy of domains read during the active turn.
func (s *Service) turnSourcesForSession(curSession session.Session) map[string]struct{} {
	key := searchTurnKey(curSession.AppName(), curSession.UserID())
	if key == "" {
		return nil
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	sources := s.turnSourceDomains[key]
	if len(sources) == 0 {
		return nil
	}
	copy := make(map[string]struct{}, len(sources))
	for id := range sources {
		copy[id] = struct{}{}
	}
	return copy
}

// clearTurnSourceDomains drops source provenance after session capture runs.
func (s *Service) clearTurnSourceDomains(curSession session.Session) {
	key := searchTurnKey(curSession.AppName(), curSession.UserID())
	if key == "" {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.turnSourceDomains, key)
}

// searchTurnKey identifies the current ADK user/app search context.
func searchTurnKey(appName string, userID string) string {
	appName = strings.TrimSpace(appName)
	userID = strings.TrimSpace(userID)
	if appName == "" || userID == "" {
		return ""
	}
	return appName + ":" + userID
}

// setValues returns deterministic string values for diagnostics.
func setValues(values map[string]struct{}) []string {
	out := make([]string, 0, len(values))
	for value := range values {
		out = append(out, value)
	}
	sort.Strings(out)
	return out
}

// searchResponseFromBundle maps Agent Awesome records into ADK memory entries.
func searchResponseFromBundle(domainID string, bundle retrievalBundle) *adkmemory.SearchResponse {
	response := &adkmemory.SearchResponse{
		Memories: make([]adkmemory.Entry, 0, len(bundle.Primary)),
	}
	for _, record := range bundle.Primary {
		text := recordText(record)
		if strings.TrimSpace(text) == "" {
			continue
		}
		response.Memories = append(response.Memories, adkmemory.Entry{
			ID:        domainID + ":" + record.ID,
			Content:   genai.NewContentFromText(text, genai.RoleUser),
			Author:    recordAuthor(record),
			Timestamp: recordTimestamp(record),
			CustomMetadata: map[string]any{
				"domain_id":   domainID,
				"memory_id":   record.ID,
				"evidence_id": record.EvidenceID,
				"source":      record.Source,
			},
		})
	}
	return response
}

// defaultWriteMemoryDomain returns the configured automatic capture domain.
func (s *Service) defaultWriteMemoryDomain() (memoryDomain, bool) {
	if _, ok := s.writeDomains[s.defaultWriteDomain]; !ok {
		return memoryDomain{}, false
	}
	for _, domain := range s.domains {
		if domain.id == s.defaultWriteDomain {
			return domain, true
		}
	}
	return memoryDomain{}, false
}
