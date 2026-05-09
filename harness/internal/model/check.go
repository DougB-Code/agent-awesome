// This file performs runtime smoke checks against configured model clients.
package model

import (
	"context"
	"fmt"
	"strings"

	"agentawesome/internal/model/protocol"
	llmapi "google.golang.org/adk/model"
	"google.golang.org/genai"
)

// SmokeCheck sends one minimal prompt to verify provider credentials and model IDs.
func SmokeCheck(ctx context.Context, llm llmapi.LLM, prompt string) (string, error) {
	if llm == nil {
		return "", fmt.Errorf("model client is nil")
	}
	prompt = strings.TrimSpace(prompt)
	if prompt == "" {
		prompt = "Reply with OK."
	}
	req := &llmapi.LLMRequest{
		Contents: []*genai.Content{genai.NewContentFromText(prompt, genai.RoleUser)},
	}
	for response, err := range llm.GenerateContent(ctx, req, false) {
		if err != nil {
			return "", err
		}
		if response == nil || response.Content == nil {
			continue
		}
		text, err := protocol.ContentText(response.Content)
		if err != nil {
			return "", fmt.Errorf("decode smoke-check response: %w", err)
		}
		if strings.TrimSpace(text) == "" {
			return "", fmt.Errorf("model returned an empty smoke-check response")
		}
		return strings.TrimSpace(text), nil
	}
	return "", fmt.Errorf("model returned no smoke-check response")
}
