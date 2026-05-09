// This file adapts ADK model requests to a local LiteRT-LM binary.
package litert

import (
	"context"
	"encoding/json"
	"fmt"
	"iter"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"unicode"

	"agentawesome/internal/config/schema"
	"agentawesome/internal/model/adapter"
	"agentawesome/internal/model/protocol"
	llmapi "google.golang.org/adk/model"
	"google.golang.org/genai"
	"gopkg.in/yaml.v3"
)

const defaultExecutable = "litert-lm"

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
	output, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("provider %q model %q request failed: %w", m.provider, m.name, err)
	}
	text := assistantTextFromOutput(string(output))
	if strings.TrimSpace(text) == "" {
		return nil, fmt.Errorf("provider %q model %q returned empty response", m.provider, m.name)
	}
	content := contentFromLocalText(text, req)
	return &llmapi.LLMResponse{Content: content, TurnComplete: true}, nil
}

// promptFromRequest builds a compact prompt for instruction-tuned local models.
func promptFromRequest(req *llmapi.LLMRequest) (string, error) {
	if req == nil {
		return "", fmt.Errorf("request is nil")
	}
	var buffer strings.Builder
	if tools := toolPromptSection(req); tools != "" {
		buffer.WriteString(tools)
		buffer.WriteString("\n\n")
	}
	if req.Config != nil && req.Config.SystemInstruction != nil {
		text, err := protocol.ContentText(req.Config.SystemInstruction)
		if err != nil {
			return "", fmt.Errorf("system instruction: %w", err)
		}
		if strings.TrimSpace(text) != "" {
			buffer.WriteString("SYSTEM: ")
			buffer.WriteString(strings.TrimSpace(text))
			buffer.WriteString("\n")
		}
	}
	for _, content := range req.Contents {
		if content == nil {
			continue
		}
		text, err := contentPromptText(content)
		if err != nil {
			return "", err
		}
		if strings.TrimSpace(text) == "" {
			continue
		}
		role := strings.ToUpper(strings.TrimSpace(content.Role))
		if role == "" {
			role = "USER"
		}
		buffer.WriteString(role)
		buffer.WriteString(": ")
		buffer.WriteString(strings.TrimSpace(text))
		buffer.WriteString("\n")
	}
	prompt := strings.TrimSpace(buffer.String())
	if prompt == "" {
		return "", fmt.Errorf("request has no supported prompt content")
	}
	return prompt, nil
}

// contentPromptText serializes text and tool result parts into prompt text.
func contentPromptText(content *genai.Content) (string, error) {
	parts := make([]string, 0, len(content.Parts))
	for i, part := range content.Parts {
		if part == nil {
			continue
		}
		if part.Text != "" {
			parts = append(parts, part.Text)
		}
		if part.FunctionCall != nil {
			data, err := json.Marshal(part.FunctionCall.Args)
			if err != nil {
				return "", fmt.Errorf("marshal function call %q arguments: %w", part.FunctionCall.Name, err)
			}
			parts = append(parts, fmt.Sprintf("TOOL_CALL %s %s", part.FunctionCall.Name, data))
		}
		if part.FunctionResponse != nil {
			data, err := json.Marshal(part.FunctionResponse.Response)
			if err != nil {
				return "", fmt.Errorf("marshal function response %q: %w", part.FunctionResponse.Name, err)
			}
			parts = append(parts, fmt.Sprintf("TOOL_RESULT %s %s", part.FunctionResponse.Name, data))
		}
		if unsupported := unsupportedLiteRTPartTypes(part); len(unsupported) > 0 {
			return "", fmt.Errorf("unsupported content part at index %d: %s", i, strings.Join(unsupported, ", "))
		}
	}
	return strings.Join(parts, "\n"), nil
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

// toolPromptSection describes available function tools for the local model.
func toolPromptSection(req *llmapi.LLMRequest) string {
	declarations := protocol.FunctionDeclarations(req)
	if len(declarations) == 0 {
		return ""
	}
	lines := []string{
		"AVAILABLE TOOLS:",
		"Use exact tool names only. To call a tool, reply with only <|tool_call>call:tool_name{json_arguments}<tool_call|>. ADK will execute the tool.",
	}
	for _, decl := range declarations {
		if decl == nil || strings.TrimSpace(decl.Name) == "" {
			continue
		}
		signature := decl.Name + "({" + strings.Join(parameterNames(decl), ", ") + "})"
		if strings.TrimSpace(decl.Description) != "" {
			signature += ": " + strings.TrimSpace(decl.Description)
		}
		lines = append(lines, "- "+signature)
	}
	if len(lines) == 2 {
		return ""
	}
	return strings.Join(lines, "\n")
}

// contentFromLocalText parses local-model tool markup or returns plain text.
func contentFromLocalText(text string, req *llmapi.LLMRequest) *genai.Content {
	if call := toolCallFromText(text, req); call != nil {
		if reply := completedToolCallReply(call, req); reply != "" {
			return genai.NewContentFromText(reply, "model")
		}
		part := genai.NewPartFromFunctionCall(call.Name, call.Args)
		part.FunctionCall.ID = call.ID
		return &genai.Content{Role: "model", Parts: []*genai.Part{part}}
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

// parseToolPayload decodes call:name{...} payload text into a tool call.
func parseToolPayload(payload string) (*toolCall, bool) {
	body := strings.TrimPrefix(payload, "call:")
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

func normalizeToolCall(call *toolCall, available map[string]bool, req *llmapi.LLMRequest) *toolCall {
	if call == nil {
		return nil
	}
	if available[call.Name] {
		if call.Name == "create_task" {
			call.Args = withCreateTaskIdempotency(call.Args, req)
		}
		return call
	}
	if call.Name == "task_tool" && available["create_task"] && fmt.Sprint(call.Args["action"]) == "create" {
		args := createTaskArgs(call.Args)
		if strings.TrimSpace(fmt.Sprint(args["title"])) == "" {
			return nil
		}
		args = withCreateTaskIdempotency(args, req)
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

// withCreateTaskIdempotency fills a stable chat-scoped key when the model omits it.
func withCreateTaskIdempotency(args map[string]any, req *llmapi.LLMRequest) map[string]any {
	if strings.TrimSpace(fmt.Sprint(args["idempotency_key"])) != "" &&
		strings.TrimSpace(fmt.Sprint(args["idempotency_key"])) != "<nil>" {
		return args
	}
	sessionID := sessionIDFromRequest(req)
	title := strings.TrimSpace(fmt.Sprint(args["title"]))
	if sessionID == "" || title == "" || title == "<nil>" {
		return args
	}
	next := make(map[string]any, len(args)+1)
	for key, value := range args {
		next[key] = value
	}
	next["idempotency_key"] = "personal_pilot:" + sessionID + ":" + taskKeySlug(title)
	return next
}

// sessionIDFromRequest extracts the UI-injected session id from prompt content.
func sessionIDFromRequest(req *llmapi.LLMRequest) string {
	if req == nil {
		return ""
	}
	const marker = `Current chat session id is "`
	for _, content := range req.Contents {
		if content == nil {
			continue
		}
		for _, part := range content.Parts {
			if part == nil || !strings.Contains(part.Text, marker) {
				continue
			}
			after := part.Text[strings.Index(part.Text, marker)+len(marker):]
			end := strings.Index(after, `"`)
			if end > 0 {
				return strings.TrimSpace(after[:end])
			}
		}
	}
	return ""
}

// taskKeySlug returns a compact deterministic suffix for chat-created tasks.
func taskKeySlug(value string) string {
	parts := []string{}
	var current strings.Builder
	for _, r := range strings.ToLower(value) {
		if unicode.IsLetter(r) || unicode.IsDigit(r) {
			current.WriteRune(r)
			continue
		}
		if current.Len() > 0 {
			parts = append(parts, current.String())
			current.Reset()
		}
	}
	if current.Len() > 0 {
		parts = append(parts, current.String())
	}
	if len(parts) == 0 {
		return "task"
	}
	return strings.Join(parts, "_")
}

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
	for _, field := range toolArgumentFields {
		normalized = strings.ReplaceAll(normalized, field+`:"`, field+`: "`)
		normalized = strings.ReplaceAll(normalized, field+`:'`, field+`: '`)
	}
	return normalized
}

// toolArgumentFields lists known fields that Gemma may emit without colon space.
var toolArgumentFields = []string{
	"action",
	"actor",
	"assignee",
	"confidence",
	"context",
	"description",
	"due_at",
	"effort",
	"energy_required",
	"estimate_minutes",
	"follow_up_at",
	"idempotency_key",
	"location",
	"note",
	"owner",
	"person",
	"priority",
	"project",
	"risk",
	"scheduled_at",
	"source",
	"status",
	"task",
	"text",
	"title",
	"topics",
	"urgency",
	"value",
	"view",
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

func parameterNames(decl *genai.FunctionDeclaration) []string {
	raw, ok := protocol.DeclarationParameters(decl).(map[string]any)
	if !ok {
		return nil
	}
	properties, ok := raw["properties"].(map[string]any)
	if !ok {
		return nil
	}
	names := make([]string, 0, len(properties))
	for name := range properties {
		names = append(names, name)
	}
	sort.Strings(names)
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
