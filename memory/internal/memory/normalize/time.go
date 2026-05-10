// This file implements shared time parsing helpers.
package normalize

import (
	"strings"
	"time"
)

// ParseFlexibleTime parses supported user-facing timestamp literals.
func ParseFlexibleTime(value string) (time.Time, bool) {
	value = strings.TrimSpace(value)
	for _, layout := range []string{time.RFC3339Nano, time.RFC3339, "2006-01-02"} {
		parsed, err := time.Parse(layout, value)
		if err == nil {
			return parsed.UTC(), true
		}
	}
	return time.Time{}, false
}
