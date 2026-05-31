// This file converts runtime session events into memory capture requests.
package adkmemory

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"strings"

	"google.golang.org/adk/session"
)

const (
	chatMemorySourceSystem = "agent_awesome_chat"
	chatMemoryTopic        = "chat"
	chatMemoryKeyPrefix    = "agent_awesome_chat"
)

// capturePayload returns a save_memory_candidate payload for one chat event.
func capturePayload(curSession session.Session, event *session.Event, actor string) (map[string]any, bool) {
	if event == nil || event.LLMResponse.Content == nil || event.LLMResponse.Partial {
		return nil, false
	}
	text := contentText(event.LLMResponse.Content)
	if text == "" {
		return nil, false
	}
	eventID := stableEventID(curSession, event, text)
	speaker := eventSpeaker(event)
	payload := map[string]any{
		"actor":           actor,
		"content":         text,
		"media_type":      "text/plain; charset=utf-8",
		"title":           captureTitle(curSession, speaker),
		"source":          map[string]any{"system": chatMemorySourceSystem, "id": eventID},
		"kind":            conversationKind,
		"trust_level":     sourceTrustLevel,
		"sensitivity":     privateSensitivity,
		"subjects":        []string{speaker},
		"topics":          captureTopics(curSession),
		"idempotency_key": idempotencyKey(curSession, eventID),
	}
	if !event.Timestamp.IsZero() {
		payload["event_time"] = event.Timestamp
	}
	return payload, true
}

// stableEventID returns the runtime event ID or a deterministic content hash.
func stableEventID(curSession session.Session, event *session.Event, text string) string {
	if strings.TrimSpace(event.ID) != "" {
		return strings.TrimSpace(event.ID)
	}
	sum := sha256.Sum256([]byte(strings.Join([]string{
		curSession.AppName(),
		curSession.UserID(),
		curSession.ID(),
		event.Author,
		event.Timestamp.String(),
		text,
	}, "\x00")))
	return hex.EncodeToString(sum[:8])
}

// eventSpeaker returns the most useful author label for a stored event.
func eventSpeaker(event *session.Event) string {
	if speaker := strings.TrimSpace(event.Author); speaker != "" {
		return speaker
	}
	if event.LLMResponse.Content != nil && strings.TrimSpace(event.LLMResponse.Content.Role) != "" {
		return strings.TrimSpace(event.LLMResponse.Content.Role)
	}
	return "unknown"
}

// captureTitle builds a compact human-readable memory title.
func captureTitle(curSession session.Session, speaker string) string {
	sessionID := shortID(curSession.ID())
	if sessionID == "" {
		return fmt.Sprintf("Chat message from %s", speaker)
	}
	return fmt.Sprintf("Chat message from %s in %s", speaker, sessionID)
}

// captureTopics returns stable tags for captured conversation memory.
func captureTopics(curSession session.Session) []string {
	topics := []string{chatMemoryTopic}
	if appName := strings.TrimSpace(curSession.AppName()); appName != "" {
		topics = append(topics, appName)
	}
	return topics
}

// idempotencyKey returns a repeatable key for a captured runtime event.
func idempotencyKey(curSession session.Session, eventID string) string {
	return strings.Join([]string{
		chatMemoryKeyPrefix,
		curSession.AppName(),
		curSession.UserID(),
		curSession.ID(),
		eventID,
	}, ":")
}

// shortID returns a readable session identifier prefix.
func shortID(value string) string {
	value = strings.TrimSpace(value)
	if len(value) <= 8 {
		return value
	}
	return value[:8]
}
