// This file adapts runtime LLM requests to Anthropic messages.
package anthropic

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"iter"
	"net/http"
	"strings"

	"agent-awesome.com/harnessinternal/config/schema"
	"agent-awesome.com/harnessinternal/model/adapter"
	"agent-awesome.com/harnessinternal/model/protocol"

	llmapi "google.golang.org/adk/model"
	"google.golang.org/genai"
)

// Factory creates Anthropic-backed runtime models.
type Factory struct {
	credentials adapter.CredentialResolver
	httpClients adapter.HTTPClientFactory
}

// NewFactory creates an Anthropic provider factory with shared dependencies.
func NewFactory(credentials adapter.CredentialResolver, httpClients adapter.HTTPClientFactory) Factory {
	return Factory{credentials: credentials, httpClients: httpClients}
}

// Create builds an Anthropic-backed runtime LLM from provider schema.
func (f Factory) Create(ctx context.Context, selection schema.ProviderSelection) (llmapi.LLM, error) {
	apiKeyEnv := strings.TrimSpace(selection.Provider.APIKeyEnv)
	if apiKeyEnv == "" {
		return nil, fmt.Errorf("provider %q requires api-key", selection.Name)
	}

	apiKey, err := adapter.ResolveCredential(f.credentials, apiKeyEnv)
	if err != nil {
		return nil, fmt.Errorf("provider %q API key %q: %w", selection.Name, apiKeyEnv, err)
	}

	endpoint, err := selection.Provider.ResolvedURL()
	if err != nil {
		return nil, fmt.Errorf("provider %q url: %w", selection.Name, err)
	}
	if endpoint == "" {
		return nil, fmt.Errorf("provider %q requires url", selection.Name)
	}

	return &anthropicModel{
		apiKey:   apiKey,
		endpoint: endpoint,
		client:   adapter.NewProviderHTTPClient(f.httpClients),
		name:     selection.ModelName(),
		provider: selection.Name,
	}, nil
}

// ValidateProvider checks Anthropic provider-specific schema.
func (Factory) ValidateProvider(name string, provider schema.Provider) error {
	if strings.TrimSpace(provider.APIKeyEnv) == "" {
		return fmt.Errorf("provider %q requires api-key", name)
	}
	if strings.TrimSpace(provider.URL) == "" {
		return fmt.Errorf("provider %q requires url", name)
	}
	return nil
}

type anthropicModel struct {
	apiKey   string
	endpoint string
	client   *http.Client
	name     string
	provider string
}

var _ llmapi.LLM = (*anthropicModel)(nil)

// Name returns the selected model name exposed to the runtime.
func (m *anthropicModel) Name() string {
	return m.name
}

// GenerateContent implements the runtime LLM interface for non-streaming
// Anthropic messages.
func (m *anthropicModel) GenerateContent(ctx context.Context, req *llmapi.LLMRequest, stream bool) iter.Seq2[*llmapi.LLMResponse, error] {
	return func(yield func(*llmapi.LLMResponse, error) bool) {
		if stream {
			yield(nil, fmt.Errorf("provider %q does not support streaming", m.provider))
			return
		}
		resp, err := m.generate(ctx, req)
		if err != nil {
			yield(nil, err)
			return
		}
		yield(resp, nil)
	}
}

// generate sends one Anthropic messages request and converts text/tool-use
// blocks back into runtime content.
func (m *anthropicModel) generate(ctx context.Context, req *llmapi.LLMRequest) (*llmapi.LLMResponse, error) {
	system, err := anthropicSystem(req)
	if err != nil {
		return nil, err
	}
	messages, err := anthropicMessages(req)
	if err != nil {
		return nil, err
	}
	body := anthropicRequest{
		Model:     m.modelName(req),
		MaxTokens: 1024,
		System:    system,
		Messages:  messages,
		Tools:     anthropicTools(req),
	}
	data, err := json.Marshal(body)
	if err != nil {
		return nil, err
	}

	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, m.endpoint, bytes.NewReader(data))
	if err != nil {
		return nil, err
	}
	httpReq.Header.Set("anthropic-version", "2023-06-01")
	httpReq.Header.Set("content-type", "application/json")
	httpReq.Header.Set("x-api-key", m.apiKey)

	resp, err := m.client.Do(httpReq)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return nil, adapter.NewProviderError(m.provider, body.Model, resp.StatusCode, resp.Status)
	}

	var decoded anthropicResponse
	if err := json.Unmarshal(respBody, &decoded); err != nil {
		return nil, err
	}

	content, err := anthropicResponseContent(decoded)
	if err != nil {
		return nil, err
	}
	return &llmapi.LLMResponse{
		Content:      content,
		TurnComplete: true,
	}, nil
}

// anthropicResponseContent converts Anthropic response blocks into runtime
// content parts.
func anthropicResponseContent(response anthropicResponse) (*genai.Content, error) {
	parts := make([]*genai.Part, 0, len(response.Content))
	for _, part := range response.Content {
		if part.Type == "text" && part.Text != "" {
			parts = append(parts, genai.NewPartFromText(part.Text))
		}
		// Anthropic returns tool calls as tool_use blocks; the runtime expects
		// them as FunctionCall parts with the provider-assigned call ID preserved.
		if part.Type == "tool_use" {
			input := part.Input
			if input == nil {
				input = make(map[string]any)
			}
			genaiPart := genai.NewPartFromFunctionCall(part.Name, input)
			genaiPart.FunctionCall.ID = part.ID
			parts = append(parts, genaiPart)
		}
	}
	if len(parts) == 0 {
		return nil, fmt.Errorf("empty response")
	}
	return &genai.Content{Role: "model", Parts: parts}, nil
}

// modelName lets a request override the configured model name when supplied.
func (m *anthropicModel) modelName(req *llmapi.LLMRequest) string {
	if req != nil && strings.TrimSpace(req.Model) != "" {
		return strings.TrimSpace(req.Model)
	}
	return m.name
}

// anthropicSystem converts the runtime system instruction into Anthropic's
// top-level system string.
func anthropicSystem(req *llmapi.LLMRequest) (string, error) {
	if req == nil || req.Config == nil || req.Config.SystemInstruction == nil {
		return "", nil
	}
	text, err := protocol.ContentText(req.Config.SystemInstruction)
	if err != nil {
		return "", fmt.Errorf("system instruction: %w", err)
	}
	return strings.TrimSpace(text), nil
}

// anthropicMessages converts runtime conversation content into Anthropic
// messages.
func anthropicMessages(req *llmapi.LLMRequest) ([]anthropicMessage, error) {
	if req == nil || len(req.Contents) == 0 {
		return nil, fmt.Errorf("request has no contents")
	}

	messages := make([]anthropicMessage, 0, len(req.Contents))
	for _, content := range req.Contents {
		if content == nil {
			continue
		}
		contentMessages, err := anthropicContentMessages(content)
		if err != nil {
			return nil, err
		}
		messages = append(messages, contentMessages...)
	}
	if len(messages) == 0 {
		return nil, fmt.Errorf("request has no supported text messages")
	}
	return messages, nil
}

// anthropicContentMessages converts a single runtime content item into one or
// more Anthropic messages.
func anthropicContentMessages(content *genai.Content) ([]anthropicMessage, error) {
	textParts := make([]string, 0, len(content.Parts))
	assistantBlocks := make([]anthropicContentBlock, 0)
	toolResults := make([]anthropicMessage, 0)
	for i, part := range content.Parts {
		if part == nil {
			continue
		}
		if unsupported := protocol.UnsupportedPartTypes(part); len(unsupported) > 0 {
			return nil, fmt.Errorf("unsupported content part at index %d: %s", i, strings.Join(unsupported, ", "))
		}
		if part.Text != "" {
			textParts = append(textParts, part.Text)
		}
		if part.FunctionCall != nil {
			assistantBlocks = append(assistantBlocks, anthropicContentBlock{
				Type:  "tool_use",
				ID:    part.FunctionCall.ID,
				Name:  part.FunctionCall.Name,
				Input: part.FunctionCall.Args,
			})
		}
		if part.FunctionResponse != nil {
			content, err := json.Marshal(part.FunctionResponse.Response)
			if err != nil {
				return nil, fmt.Errorf("marshal function response %q: %w", part.FunctionResponse.Name, err)
			}
			toolResults = append(toolResults, anthropicMessage{
				Role: "user",
				Content: []anthropicContentBlock{
					{
						Type:      "tool_result",
						ToolUseID: part.FunctionResponse.ID,
						Content:   string(content),
					},
				},
			})
		}
	}

	text := strings.Join(textParts, "\n")
	messages := make([]anthropicMessage, 0, 1+len(toolResults))
	// Anthropic represents model tool calls as assistant content blocks, then
	// requires tool results to come back as user messages.
	if len(assistantBlocks) > 0 {
		blocks := make([]anthropicContentBlock, 0, 1+len(assistantBlocks))
		if strings.TrimSpace(text) != "" {
			blocks = append(blocks, anthropicContentBlock{Type: "text", Text: text})
		}
		blocks = append(blocks, assistantBlocks...)
		messages = append(messages, anthropicMessage{Role: "assistant", Content: blocks})
	} else if strings.TrimSpace(text) != "" {
		role, err := protocol.AnthropicRole(content.Role)
		if err != nil {
			return nil, err
		}
		messages = append(messages, anthropicMessage{Role: role, Content: text})
	}
	messages = append(messages, toolResults...)
	return messages, nil
}

// anthropicTools converts runtime function declarations into Anthropic tool
// declarations.
func anthropicTools(req *llmapi.LLMRequest) []anthropicTool {
	declarations := protocol.FunctionDeclarations(req)
	if len(declarations) == 0 {
		return nil
	}
	tools := make([]anthropicTool, 0, len(declarations))
	for _, decl := range declarations {
		if decl == nil {
			continue
		}
		tools = append(tools, anthropicTool{
			Name:        decl.Name,
			Description: decl.Description,
			InputSchema: protocol.DeclarationParameters(decl),
		})
	}
	return tools
}

type anthropicRequest struct {
	Model     string             `json:"model"`
	MaxTokens int                `json:"max_tokens"`
	System    string             `json:"system,omitempty"`
	Messages  []anthropicMessage `json:"messages"`
	Tools     []anthropicTool    `json:"tools,omitempty"`
}

type anthropicMessage struct {
	Role    string `json:"role"`
	Content any    `json:"content"`
}

type anthropicResponse struct {
	Content []anthropicContentBlock `json:"content"`
}

type anthropicContentBlock struct {
	Type      string         `json:"type"`
	Text      string         `json:"text,omitempty"`
	ID        string         `json:"id,omitempty"`
	Name      string         `json:"name,omitempty"`
	Input     map[string]any `json:"input,omitempty"`
	ToolUseID string         `json:"tool_use_id,omitempty"`
	Content   string         `json:"content,omitempty"`
}

type anthropicTool struct {
	Name        string `json:"name"`
	Description string `json:"description,omitempty"`
	InputSchema any    `json:"input_schema"`
}
