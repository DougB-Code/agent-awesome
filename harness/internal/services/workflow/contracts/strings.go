// This file contains shared string-set helpers for workflow contracts.
package contracts

import (
	"sort"
	"strings"
)

// stringSet builds a trimmed string lookup table.
func stringSet(values []string) map[string]bool {
	set := map[string]bool{}
	for _, value := range values {
		if trimmed := strings.TrimSpace(value); trimmed != "" {
			set[trimmed] = true
		}
	}
	return set
}

// containsString reports whether a trimmed list contains a value.
func containsString(values []string, value string) bool {
	target := strings.TrimSpace(value)
	for _, item := range values {
		if strings.TrimSpace(item) == target {
			return true
		}
	}
	return false
}

// uniqueStrings returns sorted unique non-empty strings.
func uniqueStrings(values []string) []string {
	set := stringSet(values)
	out := make([]string, 0, len(set))
	for value := range set {
		out = append(out, value)
	}
	sort.Strings(out)
	return out
}
