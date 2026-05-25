// This file adapts live agent validations to the same runtime wiring used by
// normal Agent Awesome runs.
package app

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"agentawesome/internal/config"
	"agentawesome/internal/config/schema"
	runtimecfg "agentawesome/internal/runtime"
	"agentawesome/internal/services/agentvalidation"
	commandservice "agentawesome/internal/services/command/command"
	adkagent "google.golang.org/adk/agent"
	adkrunner "google.golang.org/adk/runner"
	adksession "google.golang.org/adk/session"
	"google.golang.org/genai"
)

const (
	agentValidationAppName = "agent-awesome-validation"
	agentValidationUserID  = "agent-validation"
)

// AgentValidationHost runs live agent validation prompts through AA runtime.
type AgentValidationHost struct {
	modelCfg       *schema.ModelConfig
	toolsCfg       *schema.Tools
	opts           Options
	commandService *commandservice.Service
}

// NewAgentValidationHost loads validation runtime dependencies.
func NewAgentValidationHost(ctx context.Context, opts Options) (*AgentValidationHost, error) {
	modelCfg, err := config.LoadModel(opts.ModelConfigPath)
	if err != nil {
		return nil, err
	}
	toolsCfg, err := config.LoadTools(opts.ToolPath, opts.ToolSet)
	if err != nil {
		return nil, err
	}
	commandService, err := openCommandService(opts, toolsCfg)
	if err != nil {
		return nil, err
	}
	return &AgentValidationHost{
		modelCfg:       modelCfg,
		toolsCfg:       toolsCfg,
		opts:           opts,
		commandService: commandService,
	}, nil
}

// Close releases live validation runtime resources.
func (h *AgentValidationHost) Close() error {
	if h == nil || h.commandService == nil {
		return nil
	}
	h.commandService.Close()
	return nil
}

// Respond executes one live validation prompt through an isolated session.
func (h *AgentValidationHost) Respond(ctx context.Context, req agentvalidation.Request) (agentvalidation.Response, error) {
	if h == nil {
		return agentvalidation.Response{}, fmt.Errorf("agent validation host is nil")
	}
	runtimeConfig, err := newRuntimeConfig(
		ctx,
		h.modelCfg,
		req.Agent,
		h.toolsCfg,
		h.opts,
		h.commandService,
		adksession.InMemoryService(),
	)
	if err != nil {
		return agentvalidation.Response{}, err
	}
	return respondWithRuntimeConfig(ctx, req, runtimeConfig)
}

// respondWithRuntimeConfig executes a validation request with prepared runtime wiring.
func respondWithRuntimeConfig(ctx context.Context, req agentvalidation.Request, cfg *runtimecfg.Config) (agentvalidation.Response, error) {
	if cfg == nil {
		return agentvalidation.Response{}, fmt.Errorf("runtime config is nil")
	}
	if cfg.AgentLoader == nil || cfg.AgentLoader.RootAgent() == nil {
		return agentvalidation.Response{}, fmt.Errorf("runtime config has no root agent")
	}
	sessionService := cfg.SessionService
	if sessionService == nil {
		sessionService = adksession.InMemoryService()
	}
	runner, err := adkrunner.New(adkrunner.Config{
		AppName:           agentValidationAppName,
		Agent:             cfg.AgentLoader.RootAgent(),
		SessionService:    sessionService,
		ArtifactService:   cfg.ArtifactService,
		MemoryService:     cfg.MemoryService,
		PluginConfig:      cfg.PluginConfig,
		AutoCreateSession: true,
	})
	if err != nil {
		return agentvalidation.Response{}, err
	}

	response := agentvalidation.Response{}
	allText := strings.Builder{}
	finalText := strings.Builder{}
	userMessage := genai.NewContentFromText(validationPrompt(req), genai.RoleUser)
	for event, err := range runner.Run(
		ctx,
		agentValidationUserID,
		validationSessionID(req),
		userMessage,
		adkagent.RunConfig{StreamingMode: adkagent.StreamingModeNone},
	) {
		if event != nil {
			captureValidationEvent(&response, event, &allText, &finalText)
		}
		if err != nil {
			return response, err
		}
	}
	if text := strings.TrimSpace(finalText.String()); text != "" {
		response.Text = text
	} else {
		response.Text = strings.TrimSpace(allText.String())
	}
	return response, nil
}

// captureValidationEvent collects text and tool selections from one runtime event.
func captureValidationEvent(response *agentvalidation.Response, event *adksession.Event, allText *strings.Builder, finalText *strings.Builder) {
	if response == nil || event == nil || event.LLMResponse.Content == nil {
		return
	}
	text := contentText(event.LLMResponse.Content)
	if text != "" {
		allText.WriteString(text)
	}
	if event.IsFinalResponse() && text != "" {
		finalText.WriteString(text)
	}
	response.ToolCalls = append(response.ToolCalls, contentToolCalls(event.LLMResponse.Content)...)
}

// contentText concatenates text parts from runtime content.
func contentText(content *genai.Content) string {
	if content == nil {
		return ""
	}
	var text strings.Builder
	for _, part := range content.Parts {
		if part == nil || part.Text == "" {
			continue
		}
		text.WriteString(part.Text)
	}
	return text.String()
}

// contentToolCalls extracts function calls from runtime content.
func contentToolCalls(content *genai.Content) []agentvalidation.ToolCall {
	if content == nil {
		return nil
	}
	calls := make([]agentvalidation.ToolCall, 0)
	for _, part := range content.Parts {
		if part == nil || part.FunctionCall == nil {
			continue
		}
		calls = append(calls, agentvalidation.ToolCall{
			ID:        strings.TrimSpace(part.FunctionCall.ID),
			Name:      strings.TrimSpace(part.FunctionCall.Name),
			Arguments: cloneValidationArgs(part.FunctionCall.Args),
		})
	}
	return calls
}

// cloneValidationArgs copies function-call arguments for result ownership.
func cloneValidationArgs(args map[string]any) map[string]any {
	if len(args) == 0 {
		return nil
	}
	cloned := make(map[string]any, len(args))
	for key, value := range args {
		cloned[key] = value
	}
	return cloned
}

// validationPrompt combines prompt text with structured validation data.
func validationPrompt(req agentvalidation.Request) string {
	prompt := strings.TrimSpace(req.Prompt)
	payload := map[string]any{}
	if len(req.Input) > 0 {
		payload["input"] = req.Input
	}
	if len(req.Fixtures) > 0 {
		payload["fixtures"] = req.Fixtures
	}
	if len(payload) == 0 {
		return prompt
	}
	encoded, err := json.Marshal(payload)
	if err != nil {
		return prompt
	}
	if prompt == "" {
		return string(encoded)
	}
	return prompt + "\n\nValidation data:\n" + string(encoded)
}

// validationSessionID returns an isolated runtime session id for one case.
func validationSessionID(req agentvalidation.Request) string {
	id := strings.TrimSpace(req.Validation.ID)
	if id == "" {
		id = "case"
	}
	id = strings.Map(func(r rune) rune {
		if r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || r >= '0' && r <= '9' || r == '-' || r == '_' {
			return r
		}
		return '-'
	}, id)
	return "validation-" + id + "-" + fmt.Sprint(time.Now().UnixNano())
}
