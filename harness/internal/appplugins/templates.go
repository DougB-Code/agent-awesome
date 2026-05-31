// This file provides built-in app plugin manifest templates.
package appplugins

import (
	"regexp"
	"strings"
)

var credentialTokenPattern = regexp.MustCompile(`[^A-Z0-9]+`)

// AppleCalendarTemplate returns a portable app plugin manifest for an external
// Apple Calendar sync package.
func AppleCalendarTemplate(profileID string) map[string]any {
	token := credentialReferenceToken(profileID)
	return map[string]any{
		"id":          "apple-calendar",
		"name":        "Apple Calendar",
		"description": "Calendar panels and sync actions backed by an external Apple CalDAV plugin.",
		"navigation": map[string]any{
			"icon": "calendar",
		},
		"panels": []any{
			map[string]any{
				"id":          "schedule",
				"title":       "Schedule",
				"kind":        "calendar",
				"description": "Review and sync Apple Calendar events through an external plugin boundary.",
				"blocks": []any{
					map[string]any{
						"title":  "Sync",
						"text":   "Uses an external CalDAV-capable app plugin action instead of first-class calendar code.",
						"icon":   "sync",
						"badges": []any{"read events", "write events"},
					},
				},
				"actions": []any{
					map[string]any{
						"id":          "sync-events",
						"title":       "Sync events",
						"description": "Run the external Apple Calendar sync action.",
						"kind":        "mcp",
						"target":      "apple-calendar.sync_events",
					},
				},
			},
		},
		"integrations": []any{
			map[string]any{
				"id":              "apple-calendar",
				"title":           "Apple Calendar",
				"kind":            "apple-calendar",
				"credentialScope": "calendar.readwrite",
				"credential": map[string]any{
					"kind":        "apple-calendar",
					"profileId":   strings.ToLower(strings.ReplaceAll(token, "_", "-")),
					"usernameRef": "AA_APPLE_CALENDAR_" + token + "_APPLE_ID",
					"passwordRef": "AA_APPLE_CALENDAR_" + token + "_APP_PASSWORD",
				},
				"capabilities": []any{"read events", "write events", "sync events"},
			},
		},
	}
}

// credentialReferenceToken converts profile labels into credential ref tokens.
func credentialReferenceToken(value string) string {
	token := strings.ToUpper(strings.TrimSpace(value))
	token = credentialTokenPattern.ReplaceAllString(token, "_")
	token = strings.Trim(token, "_")
	if token == "" {
		return "DEFAULT"
	}
	return token
}
