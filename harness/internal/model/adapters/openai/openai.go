// This file adapts runtime LLM requests to OpenAI-compatible chat completions.
package openai

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"iter"
	"net"
	"net/http"
	"net/url"
	"strings"

	"agentawesome/internal/config/schema"
	"agentawesome/internal/model/adapter"
	"agentawesome/internal/model/protocol"
	llmapi "google.golang.org/adk/model"
	"google.golang.org/genai"
)

type openAICompatibleModel struct {
	apiKey   string
	url      string
	client   *http.Client
	name     string
	provider string
}

var _ llmapi.LLM = (*openAICompatibleModel)(nil)

// Factory creates OpenAI-compatible runtime models.
type Factory struct {
	credentials adapter.CredentialResolver
	httpClients adapter.HTTPClientFactory
}

// NewFactory creates an OpenAI-compatible provider factory with shared
// dependencies.
func NewFactory(credentials adapter.CredentialResolver, httpClients adapter.HTTPClientFactory) Factory {
	return Factory{credentials: credentials, httpClients: httpClients}
}

// Create builds an OpenAI-compatible runtime LLM from provider schema.
func (f Factory) Create(ctx context.Context, selection schema.ProviderSelection) (llmapi.LLM, error) {
	if err := f.ValidateProvider(selection.Name, selection.Provider); err != nil {
		return nil, err
	}
	url, err := selection.Provider.ResolvedURL()
	if err != nil {
		return nil, fmt.Errorf("provider %q url: %w", selection.Name, err)
	}
	if url == "" {
		return nil, fmt.Errorf("provider %q requires url", selection.Name)
	}

	apiKey := ""
	if apiKeyEnv := strings.TrimSpace(selection.Provider.APIKeyEnv); apiKeyEnv != "" {
		secret, err := adapter.ResolveCredential(f.credentials, apiKeyEnv)
		if err != nil {
			return nil, fmt.Errorf("provider %q API key %q: %w", selection.Name, apiKeyEnv, err)
		}
		apiKey = secret
	}

	return &openAICompatibleModel{
		apiKey:   apiKey,
		url:      url,
		client:   adapter.NewProviderHTTPClient(f.httpClients),
		name:     selection.ModelName(),
		provider: selection.Name,
	}, nil
}

// ValidateProvider checks OpenAI-compatible provider-specific schema.
func (Factory) ValidateProvider(name string, provider schema.Provider) error {
	if strings.TrimSpace(provider.URL) == "" {
		return fmt.Errorf("provider %q requires url", name)
	}
	if err := adapter.ValidateNoStreamingModels(name, provider, "OpenAI-compatible"); err != nil {
		return err
	}
	if strings.TrimSpace(provider.APIKeyEnv) != "" {
		return nil
	}
	if provider.AuthMode() == schema.ProviderAuthOptional && isLoopbackURL(provider.URL) {
		return nil
	}
	if provider.AuthMode() == schema.ProviderAuthRequired {
		return fmt.Errorf("provider %q auth is required and requires api-key", name)
	}
	if isKnownHostedURL(provider.URL) || !isLoopbackURL(provider.URL) {
		return fmt.Errorf("provider %q remote OpenAI-compatible endpoint requires api-key", name)
	}
	return fmt.Errorf("provider %q loopback OpenAI-compatible endpoint without api-key must set auth: optional", name)
}

// isLoopbackURL reports whether a provider URL is local-only.
func isLoopbackURL(rawURL string) bool {
	parsed, err := url.Parse(strings.TrimSpace(rawURL))
	if err != nil || parsed.Host == "" {
		return false
	}
	host := parsed.Hostname()
	if strings.EqualFold(host, "localhost") {
		return true
	}
	ip := net.ParseIP(host)
	return ip != nil && ip.IsLoopback()
}

// isKnownHostedURL reports whether a URL belongs to a hosted OpenAI-compatible API.
func isKnownHostedURL(rawURL string) bool {
	parsed, err := url.Parse(strings.TrimSpace(rawURL))
	if err != nil {
		return false
	}
	host := strings.ToLower(parsed.Hostname())
	switch {
	case host == "api.openai.com":
		return true
	case host == "api.x.ai":
		return true
	case host == "router.huggingface.co":
		return true
	case strings.HasSuffix(host, ".ai.cloudflare.com"):
		return true
	default:
		return false
	}
}

// Name returns the selected model name exposed to the runtime.
func (m *openAICompatibleModel) Name() string {
	return m.name
}

// GenerateContent implements the runtime LLM interface for non-streaming
// OpenAI-compatible chat completions.
func (m *openAICompatibleModel) GenerateContent(ctx context.Context, req *llmapi.LLMRequest, stream bool) iter.Seq2[*llmapi.LLMResponse, error] {
	return func(yield func(*llmapi.LLMResponse, error) bool) {
		if stream {
			yield(nil, adapter.NewStreamingUnsupportedError(m.provider))
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

// generate sends one chat-completions request and converts the first choice
// back into runtime content.
func (m *openAICompatibleModel) generate(ctx context.Context, req *llmapi.LLMRequest) (*llmapi.LLMResponse, error) {
	messages, err := openAIMessages(req)
	if err != nil {
		return nil, err
	}
	body := openAIChatRequest{
		Model:    m.modelName(req),
		Messages: messages,
		Stream:   false,
		Tools:    openAITools(req),
	}
	data, err := json.Marshal(body)
	if err != nil {
		return nil, err
	}

	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, m.url, bytes.NewReader(data))
	if err != nil {
		return nil, err
	}
	httpReq.Header.Set("content-type", "application/json")
	if m.apiKey != "" {
		httpReq.Header.Set("authorization", "Bearer "+m.apiKey)
	}

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

	var decoded openAIChatResponse
	if err := json.Unmarshal(respBody, &decoded); err != nil {
		return nil, err
	}
	if len(decoded.Choices) == 0 {
		return nil, fmt.Errorf("empty response")
	}
	message := decoded.Choices[0].Message
	content, err := openAIResponseContent(message)
	if err != nil {
		return nil, err
	}
	return &llmapi.LLMResponse{
		Content:      content,
		TurnComplete: true,
	}, nil
}

// modelName lets a request override the configured model name when supplied.
func (m *openAICompatibleModel) modelName(req *llmapi.LLMRequest) string {
	if req != nil && strings.TrimSpace(req.Model) != "" {
		return strings.TrimSpace(req.Model)
	}
	return m.name
}

// openAIMessages converts runtime system/user/model/tool content into
// OpenAI-compatible chat messages.
func openAIMessages(req *llmapi.LLMRequest) ([]openAIMessage, error) {
	if req == nil {
		return nil, fmt.Errorf("request is nil")
	}

	messages := make([]openAIMessage, 0, len(req.Contents)+1)
	if req.Config != nil && req.Config.SystemInstruction != nil {
		text, err := protocol.ContentText(req.Config.SystemInstruction)
		if err != nil {
			return nil, fmt.Errorf("system instruction: %w", err)
		}
		if text := strings.TrimSpace(text); text != "" {
			messages = append(messages, openAIMessage{Role: "system", Content: text})
		}
	}
	for _, content := range req.Contents {
		if content == nil {
			continue
		}
		contentMessages, err := openAIContentMessages(content)
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

// openAIContentMessages converts a single runtime content item into one or more
// OpenAI-compatible messages.
func openAIContentMessages(content *genai.Content) ([]openAIMessage, error) {
	textParts := make([]string, 0, len(content.Parts))
	toolCalls := make([]openAIToolCall, 0)
	toolResponses := make([]openAIMessage, 0)
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
			arguments, err := json.Marshal(part.FunctionCall.Args)
			if err != nil {
				return nil, fmt.Errorf("marshal function call %q arguments: %w", part.FunctionCall.Name, err)
			}
			toolCalls = append(toolCalls, openAIToolCall{
				ID:   part.FunctionCall.ID,
				Type: "function",
				Function: openAIFunctionCall{
					Name:      part.FunctionCall.Name,
					Arguments: string(arguments),
				},
			})
		}
		if part.FunctionResponse != nil {
			content, err := json.Marshal(part.FunctionResponse.Response)
			if err != nil {
				return nil, fmt.Errorf("marshal function response %q: %w", part.FunctionResponse.Name, err)
			}
			toolResponses = append(toolResponses, openAIMessage{
				Role:       "tool",
				ToolCallID: part.FunctionResponse.ID,
				Content:    string(content),
			})
		}
	}

	text := strings.Join(textParts, "\n")
	messages := make([]openAIMessage, 0, 1+len(toolResponses))
	// OpenAI represents model tool calls on an assistant message, followed by
	// separate tool-role messages for the tool results.
	if len(toolCalls) > 0 {
		messages = append(messages, openAIMessage{
			Role:      "assistant",
			Content:   text,
			ToolCalls: toolCalls,
		})
	} else if strings.TrimSpace(text) != "" {
		role, err := openAIRole(content.Role)
		if err != nil {
			return nil, err
		}
		messages = append(messages, openAIMessage{Role: role, Content: text})
	}
	messages = append(messages, toolResponses...)
	return messages, nil
}

// openAIRole maps runtime roles into OpenAI-compatible chat roles.
func openAIRole(role string) (string, error) {
	switch role {
	case "", "user":
		return "user", nil
	case "model", "assistant":
		return "assistant", nil
	case "system":
		return "system", nil
	default:
		return "", fmt.Errorf("unsupported OpenAI-compatible role %q", role)
	}
}

// openAITools converts runtime function declarations into OpenAI tool
// declarations.
func openAITools(req *llmapi.LLMRequest) []openAITool {
	declarations := protocol.FunctionDeclarations(req)
	if len(declarations) == 0 {
		return nil
	}
	tools := make([]openAITool, 0, len(declarations))
	for _, decl := range declarations {
		if decl == nil {
			continue
		}
		tools = append(tools, openAITool{
			Type: "function",
			Function: openAIFunctionDeclaration{
				Name:        decl.Name,
				Description: decl.Description,
				Parameters:  protocol.DeclarationParameters(decl),
			},
		})
	}
	return tools
}

// openAIResponseContent converts assistant text and tool calls from an
// OpenAI-compatible response into runtime content parts.
func openAIResponseContent(message openAIMessage) (*genai.Content, error) {
	parts := make([]*genai.Part, 0, 1+len(message.ToolCalls))
	if strings.TrimSpace(message.Content) != "" {
		parts = append(parts, genai.NewPartFromText(message.Content))
	}
	for _, call := range message.ToolCalls {
		args := make(map[string]any)
		if strings.TrimSpace(call.Function.Arguments) != "" {
			if err := json.Unmarshal([]byte(call.Function.Arguments), &args); err != nil {
				return nil, fmt.Errorf("decode tool call %q arguments: %w", call.Function.Name, err)
			}
		}
		part := genai.NewPartFromFunctionCall(call.Function.Name, args)
		part.FunctionCall.ID = call.ID
		parts = append(parts, part)
	}
	if len(parts) == 0 {
		return nil, fmt.Errorf("empty response content")
	}
	return &genai.Content{Role: "model", Parts: parts}, nil
}

type openAIChatRequest struct {
	Model    string          `json:"model"`
	Messages []openAIMessage `json:"messages"`
	Stream   bool            `json:"stream"`
	Tools    []openAITool    `json:"tools,omitempty"`
}

type openAIMessage struct {
	Role       string           `json:"role"`
	Content    string           `json:"content,omitempty"`
	ToolCalls  []openAIToolCall `json:"tool_calls,omitempty"`
	ToolCallID string           `json:"tool_call_id,omitempty"`
}

type openAIChatResponse struct {
	Choices []struct {
		Message openAIMessage `json:"message"`
	} `json:"choices"`
}

type openAITool struct {
	Type     string                    `json:"type"`
	Function openAIFunctionDeclaration `json:"function"`
}

type openAIFunctionDeclaration struct {
	Name        string `json:"name"`
	Description string `json:"description,omitempty"`
	Parameters  any    `json:"parameters,omitempty"`
}

type openAIToolCall struct {
	ID       string             `json:"id,omitempty"`
	Type     string             `json:"type"`
	Function openAIFunctionCall `json:"function"`
}

type openAIFunctionCall struct {
	Name      string `json:"name"`
	Arguments string `json:"arguments"`
}
