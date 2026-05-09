// This file adapts ADK model requests to a local LiteRT-LM binary.
package litert

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"iter"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	"agentawesome/internal/config/schema"
	"agentawesome/internal/model/adapter"
	"agentawesome/internal/model/protocol"
	llmapi "google.golang.org/adk/model"
	"google.golang.org/genai"
	"gopkg.in/yaml.v3"
)

const defaultExecutable = "litert-lm"

var gemmaQuoteSpacing = regexp.MustCompile(`(^|[\{,\s])([A-Za-z_][A-Za-z0-9_]*):(["'])`)

// Factory creates local LiteRT-LM runtime models.
type Factory struct{}

// NewFactory creates a LiteRT provider factory.
func NewFactory() Factory {
	return Factory{}
}

// Create builds a local model with executable resolution.
func (Factory) Create(_ context.Context, selection schema.ProviderSelection) (llmapi.LLM, error) {
	modelPath := strings.TrimSpace(selection.Model.Path)
	if modelPath == "" {
		return nil, fmt.Errorf("provider %q model id %q requires path", selection.Name, selection.Model.ID)
	}
	executable, err := resolveExecutable(selection.Provider.Executable)
	if err != nil {
		return nil, err
	}
	return &model{
		executable: executable,
		modelPath:  modelPath,
		name:       selection.ModelName(),
		provider:   selection.Name,
	}, nil
}

// ValidateProvider checks LiteRT-specific provider fields.
func (Factory) ValidateProvider(name string, provider schema.Provider) error {
	if strings.TrimSpace(provider.URL) != "" {
		return fmt.Errorf("provider %q does not support url", name)
	}
	if err := adapter.ValidateNoStreamingModels(name, provider, "LiteRT"); err != nil {
		return err
	}
	for _, model := range provider.Models {
		if strings.TrimSpace(model.Path) == "" {
			return fmt.Errorf("provider %q model id %q requires path", name, model.ID)
		}
	}
	return nil
}

type model struct {
	executable string
	modelPath  string
	name       string
	provider   string
}

var _ llmapi.LLM = (*model)(nil)

// Name returns the configured model name.
func (m *model) Name() string {
	return m.name
}

// GenerateContent runs one local LiteRT-LM completion.
func (m *model) GenerateContent(ctx context.Context, req *llmapi.LLMRequest, stream bool) iter.Seq2[*llmapi.LLMResponse, error] {
	return func(yield func(*llmapi.LLMResponse, error) bool) {
		if stream {
			yield(nil, adapter.NewStreamingUnsupportedError(m.provider))
			return
		}
		resp, err := m.generate(ctx, req)
		yield(resp, err)
	}
}

func (m *model) generate(ctx context.Context, req *llmapi.LLMRequest) (*llmapi.LLMResponse, error) {
	prompt, err := promptFromRequest(req)
	if err != nil {
		return nil, err
	}
	promptFile, err := writePromptFile(prompt)
	if err != nil {
		return nil, err
	}
	defer func() { _ = os.Remove(promptFile) }()

	cmd := exec.CommandContext(ctx, m.executable, "--min_log_level", "4", "run", m.modelPath, "--input_prompt_file", promptFile)
	cmd.Env = localModelEnvironment(m.executable)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	output, err := cmd.Output()
	if err != nil {
		return nil, localModelCommandError(m.provider, m.name, err, stderr.String())
	}
	text := assistantTextFromOutput(string(output))
	if strings.TrimSpace(text) == "" {
		return nil, fmt.Errorf("provider %q model %q returned empty response", m.provider, m.name)
	}
	content := contentFromLocalText(text, req)
	return &llmapi.LLMResponse{Content: content, TurnComplete: true}, nil
}

// localModelCommandError includes bounded LiteRT stderr in provider failures.
func localModelCommandError(provider string, model string, cause error, stderr string) error {
	details := strings.TrimSpace(stderr)
	if details == "" {
		return fmt.Errorf("provider %q model %q request failed: %w", provider, model, cause)
	}
	return fmt.Errorf("provider %q model %q request failed: %w: %s", provider, model, cause, clippedErrorDetail(details))
}

// clippedErrorDetail bounds subprocess stderr included in user-visible errors.
func clippedErrorDetail(text string) string {
	const limit = 1200
	if len(text) <= limit {
		return text
	}
	return text[:limit] + "...(truncated)"
}

// promptFromRequest builds a Gemma chat-template prompt for local models.
func promptFromRequest(req *llmapi.LLMRequest) (string, error) {
	if req == nil {
		return "", fmt.Errorf("request is nil")
	}
	var buffer strings.Builder
	buffer.WriteString("<bos>")
	systemText := ""
	if req.Config != nil && req.Config.SystemInstruction != nil {
		text, err := protocol.ContentText(req.Config.SystemInstruction)
		if err != nil {
			return "", fmt.Errorf("system instruction: %w", err)
		}
		systemText = strings.TrimSpace(text)
	}
	if err := appendGemmaSystemTurn(&buffer, systemText, gemmaFunctionDeclarationsForRequest(req)); err != nil {
		return "", err
	}
	pendingToolResponse := false
	for _, content := range req.Contents {
		if content == nil {
			continue
		}
		pending, err := appendGemmaContentTurn(&buffer, content, pendingToolResponse)
		if err != nil {
			return "", err
		}
		pendingToolResponse = pending
	}
	if pendingToolResponse {
		buffer.WriteString("<tool_response|><turn|>\n")
	}
	buffer.WriteString("<|turn>model\n")
	prompt := strings.TrimSpace(buffer.String())
	if prompt == "<bos><|turn>model" {
		return "", fmt.Errorf("request has no supported prompt content")
	}
	return prompt, nil
}

// appendGemmaSystemTurn writes system text and Gemma tool declarations.
func appendGemmaSystemTurn(buffer *strings.Builder, systemText string, declarations []*genai.FunctionDeclaration) error {
	if strings.TrimSpace(systemText) == "" && len(declarations) == 0 {
		return nil
	}
	buffer.WriteString("<|turn>system\n")
	if strings.TrimSpace(systemText) != "" {
		buffer.WriteString(strings.TrimSpace(systemText))
		if len(declarations) > 0 {
			buffer.WriteString("\n")
		}
	}
	for _, decl := range declarations {
		if decl == nil || strings.TrimSpace(decl.Name) == "" {
			continue
		}
		buffer.WriteString("<|tool>")
		if err := appendGemmaToolDeclaration(buffer, decl); err != nil {
			return err
		}
		buffer.WriteString("<tool|>")
	}
	buffer.WriteString("<turn|>\n")
	return nil
}

// appendGemmaContentTurn serializes one ADK content item into Gemma turns.
func appendGemmaContentTurn(buffer *strings.Builder, content *genai.Content, pendingToolResponse bool) (bool, error) {
	textParts := make([]string, 0, len(content.Parts))
	toolCalls := make([]*genai.FunctionCall, 0)
	toolResponses := make([]*genai.FunctionResponse, 0)
	for i, part := range content.Parts {
		if part == nil {
			continue
		}
		if unsupported := unsupportedLiteRTPartTypes(part); len(unsupported) > 0 {
			return pendingToolResponse, fmt.Errorf("unsupported content part at index %d: %s", i, strings.Join(unsupported, ", "))
		}
		if part.Text != "" {
			textParts = append(textParts, part.Text)
		}
		if part.FunctionCall != nil {
			toolCalls = append(toolCalls, part.FunctionCall)
		}
		if part.FunctionResponse != nil {
			toolResponses = append(toolResponses, part.FunctionResponse)
		}
	}
	if len(toolResponses) > 0 {
		if !pendingToolResponse {
			buffer.WriteString("<|turn>model\n<|tool_response>")
		}
		for _, response := range toolResponses {
			appendGemmaToolResponse(buffer, response)
		}
		buffer.WriteString("<tool_response|>")
		if text := strings.TrimSpace(strings.Join(textParts, "\n")); text != "" {
			buffer.WriteString(text)
		}
		buffer.WriteString("<turn|>\n")
		return false, nil
	}
	text := strings.TrimSpace(strings.Join(textParts, "\n"))
	if len(toolCalls) == 0 && text == "" {
		return pendingToolResponse, nil
	}
	if pendingToolResponse {
		buffer.WriteString("<tool_response|><turn|>\n")
		pendingToolResponse = false
	}
	role, err := gemmaRole(content.Role)
	if err != nil {
		return false, err
	}
	if len(toolCalls) > 0 {
		role = "model"
	}
	buffer.WriteString("<|turn>")
	buffer.WriteString(role)
	buffer.WriteString("\n")
	if text != "" {
		buffer.WriteString(text)
	}
	for _, call := range toolCalls {
		appendGemmaToolCall(buffer, call.Name, call.Args)
	}
	if len(toolCalls) > 0 {
		buffer.WriteString("<|tool_response>")
		return true, nil
	}
	buffer.WriteString("<turn|>\n")
	return false, nil
}

// unsupportedLiteRTPartTypes names parts LiteRT prompt serialization cannot use.
func unsupportedLiteRTPartTypes(part *genai.Part) []string {
	unsupported := protocol.UnsupportedPartTypes(part)
	filtered := unsupported[:0]
	for _, value := range unsupported {
		if value == "tool call" || value == "tool response" {
			continue
		}
		filtered = append(filtered, value)
	}
	return filtered
}

// gemmaRole maps ADK content roles onto Gemma chat-template role names.
func gemmaRole(role string) (string, error) {
	switch strings.TrimSpace(role) {
	case "", "user":
		return "user", nil
	case "model", "assistant":
		return "model", nil
	case "system":
		return "system", nil
	default:
		return "", fmt.Errorf("unsupported LiteRT role %q", role)
	}
}

// appendGemmaToolDeclaration writes one Gemma function declaration block.
func appendGemmaToolDeclaration(buffer *strings.Builder, decl *genai.FunctionDeclaration) error {
	buffer.WriteString("declaration:")
	buffer.WriteString(strings.TrimSpace(decl.Name))
	buffer.WriteString("{")
	fields := []string{}
	if description := strings.TrimSpace(decl.Description); description != "" {
		fields = append(fields, "description:"+gemmaValue(description))
	}
	fields = append(fields, "parameters:"+gemmaSchemaValue(protocol.DeclarationParameters(decl)))
	buffer.WriteString(strings.Join(fields, ","))
	buffer.WriteString("}")
	return nil
}

// appendGemmaToolCall writes a model tool-call history item.
func appendGemmaToolCall(buffer *strings.Builder, name string, args map[string]any) {
	buffer.WriteString("<|tool_call>call:")
	buffer.WriteString(strings.TrimSpace(name))
	buffer.WriteString(gemmaValue(args))
	buffer.WriteString("<tool_call|>")
}

// appendGemmaToolResponse writes a tool response inside a Gemma response block.
func appendGemmaToolResponse(buffer *strings.Builder, response *genai.FunctionResponse) {
	if response == nil {
		return
	}
	buffer.WriteString("response:")
	buffer.WriteString(strings.TrimSpace(response.Name))
	buffer.WriteString(gemmaValue(response.Response))
}

// gemmaSchemaValue writes JSON schema values in Gemma declaration syntax.
func gemmaSchemaValue(value any) string {
	switch typed := value.(type) {
	case *genai.Schema:
		data, err := json.Marshal(typed)
		if err != nil {
			return "{}"
		}
		var decoded map[string]any
		if err := json.Unmarshal(data, &decoded); err != nil {
			return "{}"
		}
		return gemmaSchemaValue(decoded)
	case map[string]any:
		keys := make([]string, 0, len(typed))
		for key := range typed {
			keys = append(keys, key)
		}
		sort.Strings(keys)
		fields := make([]string, 0, len(keys))
		for _, key := range keys {
			next := typed[key]
			if key == "type" {
				if text := strings.TrimSpace(fmt.Sprint(next)); text != "" && text != "<nil>" {
					next = strings.ToUpper(text)
				}
			}
			fields = append(fields, key+":"+gemmaSchemaValue(next))
		}
		return "{" + strings.Join(fields, ",") + "}"
	case map[string]string:
		next := make(map[string]any, len(typed))
		for key, value := range typed {
			next[key] = value
		}
		return gemmaSchemaValue(next)
	case []any:
		values := make([]string, 0, len(typed))
		for _, item := range typed {
			values = append(values, gemmaSchemaValue(item))
		}
		return "[" + strings.Join(values, ",") + "]"
	case []string:
		values := make([]string, 0, len(typed))
		for _, item := range typed {
			values = append(values, gemmaValue(item))
		}
		return "[" + strings.Join(values, ",") + "]"
	default:
		return gemmaValue(typed)
	}
}

// gemmaValue writes scalar and collection values in Gemma function syntax.
func gemmaValue(value any) string {
	switch typed := value.(type) {
	case nil:
		return "null"
	case string:
		return `<|"|>` + strings.ReplaceAll(typed, `<|"|>`, "") + `<|"|>`
	case bool:
		if typed {
			return "true"
		}
		return "false"
	case int:
		return fmt.Sprint(typed)
	case int32:
		return fmt.Sprint(typed)
	case int64:
		return fmt.Sprint(typed)
	case float32:
		return fmt.Sprint(typed)
	case float64:
		return fmt.Sprint(typed)
	case json.Number:
		return typed.String()
	case map[string]any:
		keys := make([]string, 0, len(typed))
		for key := range typed {
			keys = append(keys, key)
		}
		sort.Strings(keys)
		fields := make([]string, 0, len(keys))
		for _, key := range keys {
			fields = append(fields, key+":"+gemmaValue(typed[key]))
		}
		return "{" + strings.Join(fields, ",") + "}"
	case []any:
		values := make([]string, 0, len(typed))
		for _, item := range typed {
			values = append(values, gemmaValue(item))
		}
		return "[" + strings.Join(values, ",") + "]"
	case []string:
		values := make([]string, 0, len(typed))
		for _, item := range typed {
			values = append(values, gemmaValue(item))
		}
		return "[" + strings.Join(values, ",") + "]"
	default:
		return gemmaValue(fmt.Sprint(typed))
	}
}

// contentFromLocalText parses local-model tool markup or returns safe plain text.
func contentFromLocalText(text string, req *llmapi.LLMRequest) *genai.Content {
	if call := toolCallFromText(text, req); call != nil {
		if reply := completedToolCallReply(call, req); reply != "" {
			return genai.NewContentFromText(reply, "model")
		}
		part := genai.NewPartFromFunctionCall(call.Name, call.Args)
		part.FunctionCall.ID = call.ID
		return &genai.Content{Role: "model", Parts: []*genai.Part{part}}
	}
	if looksLikeToolMarkup(text) {
		return genai.NewContentFromText(
			"I tried to use a tool, but the local model emitted an invalid tool request. Please retry the request.",
			"model",
		)
	}
	return genai.NewContentFromText(text, "model")
}

type toolCall struct {
	ID   string
	Name string
	Args map[string]any
}

// toolCallFromText converts Gemma tool markup into an ADK function call.
func toolCallFromText(text string, req *llmapi.LLMRequest) *toolCall {
	payload, ok := toolPayload(text)
	if !ok {
		return nil
	}
	call, ok := parseToolPayload(payload)
	if !ok {
		return nil
	}
	return normalizeToolCall(call, availableToolNames(req), req)
}

// toolPayload extracts the model-emitted call payload from LiteRT text output.
func toolPayload(text string) (string, bool) {
	start := strings.Index(text, "<|tool_call>")
	if start == -1 {
		return "", false
	}
	after := start + len("<|tool_call>")
	end := strings.Index(text[after:], "<tool_call|>")
	if end == -1 {
		end = strings.Index(text[after:], "<|/tool_call|>")
	}
	if end == -1 {
		return unterminatedToolPayload(text[after:])
	}
	payload := strings.TrimSpace(text[after : after+end])
	return payload, payload != ""
}

// unterminatedToolPayload extracts a balanced call payload without a closing tag.
func unterminatedToolPayload(text string) (string, bool) {
	trimmed := strings.TrimSpace(text)
	end, ok := balancedObjectEnd(trimmed)
	if !ok {
		return "", false
	}
	payload := strings.TrimSpace(trimmed[:end])
	return payload, payload != ""
}

// balancedObjectEnd returns the end offset of call:name{...} payload text.
func balancedObjectEnd(text string) (int, bool) {
	start := strings.Index(text, "{")
	if start <= 0 {
		return 0, false
	}
	depth := 0
	inString := false
	escaped := false
	var quote rune
	for index, value := range text[start:] {
		if inString {
			if escaped {
				escaped = false
				continue
			}
			if value == '\\' {
				escaped = true
				continue
			}
			if value == quote {
				inString = false
			}
			continue
		}
		switch value {
		case '"', '\'':
			inString = true
			quote = value
		case '{':
			depth++
		case '}':
			depth--
			if depth == 0 {
				return start + index + 1, true
			}
		}
	}
	return 0, false
}

// parseToolPayload decodes supported local-model tool payload shapes.
func parseToolPayload(payload string) (*toolCall, bool) {
	body := strings.TrimSpace(payload)
	if strings.HasPrefix(body, "call:") {
		body = strings.TrimSpace(strings.TrimPrefix(body, "call:"))
	}
	if call, ok := parseStandardToolPayload(body); ok {
		return call, true
	}
	return parseWrappedToolPayload(body)
}

// parseStandardToolPayload decodes name{...} payload text into a tool call.
func parseStandardToolPayload(body string) (*toolCall, bool) {
	body = strings.TrimSpace(body)
	argsStart := strings.Index(body, "{")
	argsEnd := strings.LastIndex(body, "}")
	if argsStart <= 0 || argsEnd <= argsStart {
		return nil, false
	}
	name := strings.TrimSpace(body[:argsStart])
	args, ok := decodeLooseObject(body[argsStart : argsEnd+1])
	if name == "" || !ok {
		return nil, false
	}
	return &toolCall{ID: "call-local", Name: name, Args: args}, true
}

// parseWrappedToolPayload decodes Gemma's nested tool_call{tool_name{...}} form.
func parseWrappedToolPayload(body string) (*toolCall, bool) {
	const wrapperPrefix = "tool_call{"
	body = strings.TrimSpace(body)
	if !strings.HasPrefix(body, wrapperPrefix) || !strings.HasSuffix(body, "}") {
		return nil, false
	}
	inner := strings.TrimSpace(body[len(wrapperPrefix) : len(body)-1])
	if strings.HasPrefix(inner, "call:") {
		inner = strings.TrimSpace(strings.TrimPrefix(inner, "call:"))
	}
	return parseStandardToolPayload(inner)
}

// looksLikeToolMarkup reports whether text contains local model control tokens.
func looksLikeToolMarkup(text string) bool {
	trimmed := strings.TrimSpace(text)
	return strings.HasPrefix(trimmed, "<|tool_call>") ||
		strings.Contains(trimmed, "<|tool_call>call:") ||
		strings.Contains(trimmed, "<tool_call|>")
}

// normalizeToolCall maps local-model tool markup onto available ADK tools.
func normalizeToolCall(call *toolCall, available map[string]bool, _ *llmapi.LLMRequest) *toolCall {
	if call == nil {
		return nil
	}
	if available[call.Name] {
		return call
	}
	if call.Name == "task_tool" && available["create_task"] && fmt.Sprint(call.Args["action"]) == "create" {
		args := createTaskArgs(call.Args)
		if strings.TrimSpace(fmt.Sprint(args["title"])) == "" {
			return nil
		}
		return &toolCall{ID: call.ID, Name: "create_task", Args: args}
	}
	return nil
}

// completedToolCallReply converts repeated post-success tool calls into text.
func completedToolCallReply(call *toolCall, req *llmapi.LLMRequest) string {
	if call == nil || call.Name != "create_task" || !hasSuccessfulToolResult(req, "create_task") {
		return ""
	}
	title := strings.TrimSpace(fmt.Sprint(call.Args["title"]))
	if title == "" || title == "<nil>" {
		return "Done. I created the task."
	}
	return "Done. I created the task: " + title + "."
}

// hasSuccessfulToolResult reports whether ADK already returned a good tool result.
func hasSuccessfulToolResult(req *llmapi.LLMRequest, name string) bool {
	if req == nil {
		return false
	}
	for _, content := range req.Contents {
		if content == nil {
			continue
		}
		for _, part := range content.Parts {
			if part == nil || part.FunctionResponse == nil || part.FunctionResponse.Name != name {
				continue
			}
			if _, failed := part.FunctionResponse.Response["error"]; failed {
				continue
			}
			return true
		}
	}
	return false
}

// createTaskArgs converts Gemma's generic task_tool shape into create_task.
func createTaskArgs(args map[string]any) map[string]any {
	details, _ := args["details"].(map[string]any)
	if details == nil {
		details = map[string]any{}
	}
	out := make(map[string]any, len(details)+2)
	for key, value := range details {
		out[key] = value
	}
	if title := firstNonEmpty(out["title"], args["title"], out["description"], args["description"]); title != "" {
		out["title"] = title
	}
	if key := strings.TrimSpace(fmt.Sprint(args["idempotency_key"])); key != "" && key != "<nil>" {
		out["idempotency_key"] = key
	}
	return out
}

// decodeLooseObject accepts strict JSON and YAML-like object fragments.
func decodeLooseObject(text string) (map[string]any, bool) {
	text = normalizeGemmaToolQuotes(text)
	var decoded map[string]any
	if err := json.Unmarshal([]byte(text), &decoded); err == nil {
		return decoded, true
	}
	if err := yaml.Unmarshal([]byte(text), &decoded); err != nil {
		return nil, false
	}
	return decoded, true
}

// normalizeGemmaToolQuotes converts Gemma quote sentinels into parseable quotes.
func normalizeGemmaToolQuotes(text string) string {
	normalized := strings.NewReplacer(
		`<|"|>`, `"`,
		`<|'|>`, `'`,
	).Replace(text)
	return gemmaQuoteSpacing.ReplaceAllString(normalized, `${1}${2}: ${3}`)
}

func availableToolNames(req *llmapi.LLMRequest) map[string]bool {
	names := map[string]bool{}
	for _, decl := range protocol.FunctionDeclarations(req) {
		if decl != nil && strings.TrimSpace(decl.Name) != "" {
			names[decl.Name] = true
		}
	}
	return names
}

func resolveExecutable(configured string) (string, error) {
	candidates := []string{strings.TrimSpace(configured)}
	if candidates[0] == "" {
		candidates[0] = defaultExecutable
	}
	if candidates[0] == "litert-lm" {
		candidates = append(candidates, "litert_lm")
	}
	for _, candidate := range candidates {
		if filepath.IsAbs(candidate) {
			if stat, err := os.Stat(candidate); err == nil && !stat.IsDir() && stat.Mode()&0o111 != 0 {
				return candidate, nil
			}
			continue
		}
		if path, err := exec.LookPath(candidate); err == nil {
			return path, nil
		}
	}
	return "", fmt.Errorf("LiteRT-LM executable %q was not found", candidates[0])
}

func writePromptFile(prompt string) (string, error) {
	file, err := os.CreateTemp("", "agentawesome-litert-prompt-*.txt")
	if err != nil {
		return "", err
	}
	if _, err := file.WriteString(prompt); err != nil {
		_ = file.Close()
		_ = os.Remove(file.Name())
		return "", err
	}
	if err := file.Close(); err != nil {
		_ = os.Remove(file.Name())
		return "", err
	}
	return file.Name(), nil
}

func assistantTextFromOutput(output string) string {
	lines := strings.Split(output, "\n")
	kept := lines[:0]
	for _, line := range lines {
		if strings.HasPrefix(line, "INFO: Created TensorFlow Lite ") {
			continue
		}
		kept = append(kept, line)
	}
	return strings.TrimSpace(strings.Join(kept, "\n"))
}

func localModelEnvironment(executable string) []string {
	env := os.Environ()
	dir := filepath.Dir(executable)
	if dir == "." || dir == "" {
		return env
	}
	current := os.Getenv("LD_LIBRARY_PATH")
	if current == "" {
		env = append(env, "LD_LIBRARY_PATH="+dir)
	} else {
		env = append(env, "LD_LIBRARY_PATH="+dir+":"+current)
	}
	return env
}

func firstNonEmpty(values ...any) string {
	for _, value := range values {
		text := strings.TrimSpace(fmt.Sprint(value))
		if text != "" && text != "<nil>" {
			return text
		}
	}
	return ""
}
