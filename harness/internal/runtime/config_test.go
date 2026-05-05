// This file tests runtime configuration and syntax behavior.
package runtime

import (
	"context"
	"iter"
	"strings"
	"testing"

	agentpkg "agentawesome/internal/agent"
	llmapi "google.golang.org/adk/model"
)

func TestNewConfigBuildsSingleAgentLoader(t *testing.T) {
	cfg, err := NewConfig(agentpkg.Definition{
		Name:        "test_agent",
		Description: "Test agent.",
		Instruction: "Be helpful.",
	}, testLLM{}, ToolsConfig{})
	if err != nil {
		t.Fatalf("NewConfig() error = %v", err)
	}
	if cfg == nil {
		t.Fatalf("NewConfig() = nil")
	}
	if cfg.AgentLoader == nil {
		t.Fatalf("AgentLoader = nil")
	}
}

func TestSyntaxExcludesADKConsoleLauncher(t *testing.T) {
	syntax := Syntax()
	if strings.Contains(syntax, "console -") {
		t.Fatalf("Syntax() = %q, want delegated non-console syntax only", syntax)
	}
	if !strings.Contains(syntax, "web -") {
		t.Fatalf("Syntax() = %q, want web launcher syntax", syntax)
	}
}

type testLLM struct{}

func (testLLM) Name() string { return "test-model" }

func (testLLM) GenerateContent(context.Context, *llmapi.LLMRequest, bool) iter.Seq2[*llmapi.LLMResponse, error] {
	return func(yield func(*llmapi.LLMResponse, error) bool) {}
}
