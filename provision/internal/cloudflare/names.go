package cloudflare

import (
	"fmt"
	"strings"
	"unicode"
)

const (
	maxBucketNameLength = 63
	maxWorkerNameLength = 63
)

// Slug returns a lowercase identifier safe for Cloudflare resource names.
func Slug(value string) (string, error) {
	var builder strings.Builder
	previousHyphen := false
	for _, current := range strings.TrimSpace(value) {
		switch {
		case current >= 'a' && current <= 'z':
			builder.WriteRune(current)
			previousHyphen = false
		case current >= 'A' && current <= 'Z':
			builder.WriteRune(unicode.ToLower(current))
			previousHyphen = false
		case current >= '0' && current <= '9':
			builder.WriteRune(current)
			previousHyphen = false
		case current == '-' || current == '_' || unicode.IsSpace(current):
			if builder.Len() > 0 && !previousHyphen {
				builder.WriteByte('-')
				previousHyphen = true
			}
		}
	}
	slug := strings.Trim(builder.String(), "-")
	if slug == "" {
		return "", fmt.Errorf("identifier must contain a letter or number")
	}
	return slug, nil
}

// BucketName returns the dedicated R2 bucket name for one agent.
func BucketName(agentID string) (string, error) {
	slug, err := Slug(agentID)
	if err != nil {
		return "", err
	}
	name := "agent-awesome-" + slug + "-memory"
	if len(name) > maxBucketNameLength {
		return "", fmt.Errorf("bucket name %q is longer than %d characters", name, maxBucketNameLength)
	}
	return name, nil
}

// WorkerName returns the Cloudflare Worker name for one agent.
func WorkerName(agentID string) (string, error) {
	slug, err := Slug(agentID)
	if err != nil {
		return "", err
	}
	name := "agent-awesome-" + slug
	if len(name) > maxWorkerNameLength {
		return "", fmt.Errorf("worker name %q is longer than %d characters", name, maxWorkerNameLength)
	}
	return name, nil
}
