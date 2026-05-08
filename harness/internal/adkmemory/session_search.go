// This file searches exact ADK session events in the shared memory database.
package adkmemory

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"net/url"
	"os"
	"sort"
	"strings"
	"time"

	_ "github.com/glebarez/go-sqlite"
	adkmemory "google.golang.org/adk/memory"
	"google.golang.org/genai"
)

const (
	sessionSearchCandidateLimit = 80
	sessionSearchRecentSkew     = time.Minute
)

// searchSessionEvents returns keyword matches from canonical ADK session rows.
func searchSessionEvents(ctx context.Context, dbPath string, req *adkmemory.SearchRequest, query string) ([]adkmemory.Entry, error) {
	if strings.TrimSpace(dbPath) == "" || !sessionDatabaseExists(dbPath) {
		return nil, nil
	}
	terms := searchTerms(query)
	if len(terms) == 0 {
		return nil, nil
	}
	db, err := sql.Open("sqlite", sessionSearchDSN(dbPath))
	if err != nil {
		return nil, fmt.Errorf("open ADK session database %q: %w", dbPath, err)
	}
	defer db.Close()

	rows, err := db.QueryContext(ctx, sessionSearchSQL(req, terms), sessionSearchArgs(req, terms)...)
	if err != nil {
		return nil, fmt.Errorf("query ADK session events: %w", err)
	}
	defer rows.Close()

	matches := []sessionEventMatch{}
	for rows.Next() {
		match, ok, err := scanSessionEventMatch(rows, terms)
		if err != nil {
			return nil, err
		}
		if ok {
			matches = append(matches, match)
		}
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("scan ADK session events: %w", err)
	}
	sort.Slice(matches, func(i, j int) bool {
		if matches[i].score == matches[j].score {
			return matches[i].entry.Timestamp.After(matches[j].entry.Timestamp)
		}
		return matches[i].score > matches[j].score
	})
	if len(matches) > defaultSearchLimit {
		matches = matches[:defaultSearchLimit]
	}
	entries := make([]adkmemory.Entry, 0, len(matches))
	for _, match := range matches {
		entries = append(entries, match.entry)
	}
	return entries, nil
}

// sessionEventMatch stores one scored exact-session memory candidate.
type sessionEventMatch struct {
	entry adkmemory.Entry
	score int
}

// scanSessionEventMatch maps one SQL row into a scored ADK memory entry.
func scanSessionEventMatch(rows *sql.Rows, terms []string) (sessionEventMatch, bool, error) {
	var eventID, author, sessionID string
	var timestamp time.Time
	var contentJSON []byte
	if err := rows.Scan(&eventID, &author, &sessionID, &timestamp, &contentJSON); err != nil {
		return sessionEventMatch{}, false, fmt.Errorf("scan ADK session event row: %w", err)
	}
	var content genai.Content
	if err := json.Unmarshal(contentJSON, &content); err != nil {
		return sessionEventMatch{}, false, fmt.Errorf("decode ADK session event content: %w", err)
	}
	text := contentText(&content)
	score := searchScore(text, terms)
	if score == 0 {
		return sessionEventMatch{}, false, nil
	}
	entry := adkmemory.Entry{
		ID:        "adk_session:" + sessionID + ":" + eventID,
		Content:   genai.NewContentFromText(text, genai.RoleUser),
		Author:    author,
		Timestamp: timestamp,
		CustomMetadata: map[string]any{
			"source":     "adk_session",
			"session_id": sessionID,
			"event_id":   eventID,
		},
	}
	return sessionEventMatch{entry: entry, score: score}, true, nil
}

// sessionSearchSQL returns a filtered query over ADK event content JSON.
func sessionSearchSQL(req *adkmemory.SearchRequest, terms []string) string {
	clauses := []string{
		"content IS NOT NULL",
		"(partial IS NULL OR partial = 0)",
		"timestamp < ?",
	}
	if strings.TrimSpace(req.AppName) != "" {
		clauses = append(clauses, "app_name = ?")
	}
	if strings.TrimSpace(req.UserID) != "" {
		clauses = append(clauses, "user_id = ?")
	}
	likeClauses := make([]string, 0, len(terms))
	for range terms {
		likeClauses = append(likeClauses, "lower(content) LIKE ?")
	}
	clauses = append(clauses, "("+strings.Join(likeClauses, " OR ")+")")
	return "SELECT id, author, session_id, timestamp, content FROM events WHERE " +
		strings.Join(clauses, " AND ") +
		" ORDER BY timestamp DESC LIMIT ?"
}

// sessionSearchArgs returns arguments matching sessionSearchSQL.
func sessionSearchArgs(req *adkmemory.SearchRequest, terms []string) []any {
	args := []any{time.Now().Add(-sessionSearchRecentSkew)}
	if strings.TrimSpace(req.AppName) != "" {
		args = append(args, strings.TrimSpace(req.AppName))
	}
	if strings.TrimSpace(req.UserID) != "" {
		args = append(args, strings.TrimSpace(req.UserID))
	}
	for _, term := range terms {
		args = append(args, "%"+term+"%")
	}
	args = append(args, sessionSearchCandidateLimit)
	return args
}

// searchTerms extracts useful lowercase query terms.
func searchTerms(query string) []string {
	seen := map[string]struct{}{}
	terms := []string{}
	for _, field := range strings.FieldsFunc(strings.ToLower(query), func(r rune) bool {
		return (r < 'a' || r > 'z') && (r < '0' || r > '9')
	}) {
		if len(field) < 3 || isStopword(field) {
			continue
		}
		if _, ok := seen[field]; ok {
			continue
		}
		seen[field] = struct{}{}
		terms = append(terms, field)
		if len(terms) >= 8 {
			break
		}
	}
	return terms
}

// searchScore counts query terms present in text.
func searchScore(text string, terms []string) int {
	normalized := strings.ToLower(text)
	score := 0
	for _, term := range terms {
		if strings.Contains(normalized, term) {
			score++
		}
	}
	return score
}

// isStopword filters common words that make exact session search noisy.
func isStopword(term string) bool {
	switch term {
	case "the", "and", "for", "that", "this", "with", "what", "when", "where", "who", "why", "how", "was", "were", "are", "you", "about", "from", "have", "has", "had":
		return true
	default:
		return false
	}
}

// sessionDatabaseExists reports whether a filesystem-backed session DB exists.
func sessionDatabaseExists(path string) bool {
	if strings.HasPrefix(path, "file:") {
		return true
	}
	info, err := os.Stat(path)
	return err == nil && info.Mode().IsRegular()
}

// sessionSearchDSN adds SQLite pragmas for exact session search.
func sessionSearchDSN(path string) string {
	if strings.HasPrefix(path, "file:") || strings.Contains(path, "?") {
		return path
	}
	values := url.Values{}
	values.Add("_pragma", "busy_timeout=5000")
	values.Add("_pragma", "journal_mode=WAL")
	return path + "?" + values.Encode()
}
