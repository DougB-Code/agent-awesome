// This file maps small memory nugget tool arguments onto capture requests.
package toolargs

import (
	"strings"

	"memory/internal/memory/domain"
)

// RememberArgs contains the small model-facing memory nugget payload.
type RememberArgs struct {
	Actor          string             `json:"actor"`
	Text           string             `json:"text"`
	Title          string             `json:"title"`
	Topics         []string           `json:"topics"`
	Entities       []string           `json:"entities"`
	Scope          domain.Scope       `json:"scope"`
	Sensitivity    domain.Sensitivity `json:"sensitivity"`
	IdempotencyKey string             `json:"idempotency_key"`
}

// CaptureRequest maps a memory nugget onto the durable graph memory model.
func (args RememberArgs) CaptureRequest() domain.CaptureRequest {
	return domain.CaptureRequest{
		Actor:          args.Actor,
		Content:        args.Text,
		MediaType:      "text/plain; charset=utf-8",
		Title:          rememberTitle(args.Title, args.Text),
		Kind:           domain.KindProfileFact,
		Scope:          args.Scope,
		TrustLevel:     domain.TrustUserAsserted,
		Sensitivity:    args.Sensitivity,
		Topics:         args.Topics,
		EntityNames:    args.Entities,
		IdempotencyKey: args.IdempotencyKey,
	}
}

// rememberTitle returns an explicit title or a compact excerpt of the nugget.
func rememberTitle(title string, text string) string {
	trimmedTitle := strings.TrimSpace(title)
	if trimmedTitle != "" {
		return trimmedTitle
	}
	words := strings.Fields(text)
	if len(words) == 0 {
		return ""
	}
	value := strings.Join(words, " ")
	const limit = 64
	if len(value) <= limit {
		return value
	}
	return strings.TrimSpace(value[:limit])
}
