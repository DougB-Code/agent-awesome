// This file implements shared string normalization helpers.
package normalize

import "strings"

// Default trims value and substitutes fallback when blank.
func Default(value string, fallback string) string {
	value = strings.TrimSpace(value)
	if value == "" {
		return fallback
	}
	return value
}

// Key trims and lowercases a controlled vocabulary or property key.
func Key(value string) string {
	return strings.ToLower(strings.TrimSpace(value))
}

// LowerUnique trims, lowercases, deduplicates, and removes blanks.
func LowerUnique(values []string) []string {
	seen := make(map[string]struct{}, len(values))
	normalized := make([]string, 0, len(values))
	for _, value := range values {
		value = Key(value)
		if value == "" {
			continue
		}
		if _, ok := seen[value]; ok {
			continue
		}
		seen[value] = struct{}{}
		normalized = append(normalized, value)
	}
	return normalized
}
