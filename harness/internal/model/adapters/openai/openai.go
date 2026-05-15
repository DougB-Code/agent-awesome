// This file adapts runtime LLM requests to OpenAI-compatible chat completions.
package openai

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"iter"
	"net"
	"net/http"
	"net/url"
	"os"
	"strings"

	"agentawesome/internal/config/schema"
	"agentawesome/internal/model/adapter"
	"agentawesome/internal/model/protocol"
	openaisdk "github.com/openai/openai-go"
	"github.com/openai/openai-go/option"
	"github.com/openai/openai-go/shared"
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
	url, err := adapter.ResolveProviderURL(selection.Provider, os.LookupEnv)
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
	params, err := m.chatCompletionParams(req)
	if err != nil {
		return nil, err
	}
	client := m.openAIClient()
	completion, err := client.Chat.Completions.New(ctx, params)
	if err != nil {
		return nil, m.providerError(string(params.Model), err)
	}
	if len(completion.Choices) == 0 {
		return nil, fmt.Errorf("empty response")
	}
	content, err := openAIResponseContent(completion.Choices[0].Message)
	if err != nil {
		return nil, err
	}
	return &llmapi.LLMResponse{
		Content:      content,
		TurnComplete: true,
	}, nil
}

// chatCompletionParams converts an ADK request into official OpenAI SDK params.
func (m *openAICompatibleModel) chatCompletionParams(req *llmapi.LLMRequest) (openaisdk.ChatCompletionNewParams, error) {
	messages, err := openAIMessages(req)
	if err != nil {
		return openaisdk.ChatCompletionNewParams{}, err
	}
	tools, err := openAITools(req)
	if err != nil {
		return openaisdk.ChatCompletionNewParams{}, err
	}
	return openaisdk.ChatCompletionNewParams{
		Model:    openaisdk.ChatModel(m.modelName(req)),
		Messages: messages,
		Tools:    tools,
	}, nil
}

// openAIClient builds an official SDK client with configured adapter options.
func (m *openAICompatibleModel) openAIClient() openaisdk.Client {
	options := []option.RequestOption{
		option.WithBaseURL(openAIBaseURL(m.url)),
		option.WithHTTPClient(m.client),
	}
	if m.apiKey == "" {
		options = append(options, option.WithHeaderDel("authorization"))
	} else {
		options = append(options, option.WithAPIKey(m.apiKey))
	}
	return openaisdk.NewClient(options...)
}

// providerError converts SDK API errors into sanitized provider errors.
func (m *openAICompatibleModel) providerError(modelName string, err error) error {
	var apiErr *openaisdk.Error
	if !errors.As(err, &apiErr) {
		return err
	}
	status := http.StatusText(apiErr.StatusCode)
	if apiErr.Response != nil && apiErr.Response.Status != "" {
		status = apiErr.Response.Status
	}
	detailBody, _ := json.Marshal(map[string]any{
		"error": map[string]any{
			"message": apiErr.Message,
			"type":    apiErr.Type,
			"code":    apiErr.Code,
			"param":   apiErr.Param,
		},
	})
	return adapter.NewProviderErrorWithDetail(
		m.provider,
		modelName,
		apiErr.StatusCode,
		status,
		adapter.ProviderErrorDetail(detailBody),
	)
}

// openAIBaseURL converts configured chat-completions URLs to SDK base URLs.
func openAIBaseURL(rawURL string) string {
	trimmed := strings.TrimRight(strings.TrimSpace(rawURL), "/")
	if strings.HasSuffix(trimmed, "/chat/completions") {
		return strings.TrimSuffix(trimmed, "/chat/completions")
	}
	return trimmed
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
func openAIMessages(req *llmapi.LLMRequest) ([]openaisdk.ChatCompletionMessageParamUnion, error) {
	if req == nil {
		return nil, fmt.Errorf("request is nil")
	}

	messages := make([]openaisdk.ChatCompletionMessageParamUnion, 0, len(req.Contents)+1)
	if req.Config != nil && req.Config.SystemInstruction != nil {
		text, err := protocol.ContentText(req.Config.SystemInstruction)
		if err != nil {
			return nil, fmt.Errorf("system instruction: %w", err)
		}
		if text := strings.TrimSpace(text); text != "" {
			messages = append(messages, openaisdk.SystemMessage(text))
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
func openAIContentMessages(content *genai.Content) ([]openaisdk.ChatCompletionMessageParamUnion, error) {
	textParts := make([]string, 0, len(content.Parts))
	toolCalls := make([]openaisdk.ChatCompletionMessageToolCallParam, 0)
	toolResponses := make([]openaisdk.ChatCompletionMessageParamUnion, 0)
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
			toolCalls = append(toolCalls, openaisdk.ChatCompletionMessageToolCallParam{
				ID: part.FunctionCall.ID,
				Function: openaisdk.ChatCompletionMessageToolCallFunctionParam{
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
			toolResponses = append(
				toolResponses,
				openaisdk.ToolMessage(string(content), part.FunctionResponse.ID),
			)
		}
	}

	text := strings.Join(textParts, "\n")
	messages := make([]openaisdk.ChatCompletionMessageParamUnion, 0, 1+len(toolResponses))
	// OpenAI represents model tool calls on an assistant message, followed by
	// separate tool-role messages for the tool results.
	if len(toolCalls) > 0 {
		assistant := openaisdk.ChatCompletionAssistantMessageParam{
			ToolCalls: toolCalls,
		}
		if strings.TrimSpace(text) != "" {
			assistant.Content.OfString = openaisdk.String(text)
		}
		messages = append(messages, openaisdk.ChatCompletionMessageParamUnion{
			OfAssistant: &assistant,
		})
	} else if strings.TrimSpace(text) != "" {
		message, err := openAITextMessage(content.Role, text)
		if err != nil {
			return nil, err
		}
		messages = append(messages, message)
	}
	messages = append(messages, toolResponses...)
	return messages, nil
}

// openAITextMessage maps runtime roles into OpenAI SDK text message params.
func openAITextMessage(role string, text string) (openaisdk.ChatCompletionMessageParamUnion, error) {
	switch role {
	case "", "user":
		return openaisdk.UserMessage(text), nil
	case "model", "assistant":
		return openaisdk.AssistantMessage(text), nil
	case "system":
		return openaisdk.SystemMessage(text), nil
	default:
		return openaisdk.ChatCompletionMessageParamUnion{}, fmt.Errorf("unsupported OpenAI-compatible role %q", role)
	}
}

// openAITools converts runtime function declarations into OpenAI tool
// declarations.
func openAITools(req *llmapi.LLMRequest) ([]openaisdk.ChatCompletionToolParam, error) {
	declarations := protocol.FunctionDeclarations(req)
	if len(declarations) == 0 {
		return nil, nil
	}
	tools := make([]openaisdk.ChatCompletionToolParam, 0, len(declarations))
	for _, decl := range declarations {
		if decl == nil {
			continue
		}
		parameters, err := openAIParametersSchema(protocol.DeclarationParameters(decl))
		if err != nil {
			return nil, fmt.Errorf("tool %q parameters: %w", decl.Name, err)
		}
		function := shared.FunctionDefinitionParam{
			Name:       decl.Name,
			Parameters: parameters,
		}
		if strings.TrimSpace(decl.Description) != "" {
			function.Description = openaisdk.String(decl.Description)
		}
		tools = append(tools, openaisdk.ChatCompletionToolParam{
			Function: function,
		})
	}
	return tools, nil
}

// openAIResponseContent converts assistant text and tool calls from an
// OpenAI-compatible response into runtime content parts.
func openAIResponseContent(message openaisdk.ChatCompletionMessage) (*genai.Content, error) {
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
