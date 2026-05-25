// This file implements portable agent-package validation execution.
package agentvalidation

import (
	"context"
	"encoding/json"
	"fmt"
	"regexp"
	"strconv"
	"strings"

	"agentawesome/internal/config/schema"
	"agentawesome/internal/services/command/command"
)

const (
	// StatusPassed means all validation assertions succeeded.
	StatusPassed = "passed"
	// StatusFailed means at least one validation assertion failed.
	StatusFailed = "failed"
	// StatusUnsupported means the runner cannot execute the target mode yet.
	StatusUnsupported = "unsupported"
)

// AgentHost runs one live agent validation through a runtime boundary.
type AgentHost interface {
	Respond(context.Context, Request) (Response, error)
}

// Request describes one live agent validation request.
type Request struct {
	Agent      schema.Agent           `json:"agent"`
	Validation schema.AgentValidation `json:"validation"`
	Prompt     string                 `json:"prompt"`
	Input      map[string]any         `json:"input,omitempty"`
	Fixtures   map[string]any         `json:"fixtures,omitempty"`
}

// Runner executes portable validations from one agent package.
type Runner struct {
	host AgentHost
}

// MissingValidationError reports selected validation IDs absent from a package.
type MissingValidationError struct {
	IDs []string
}

// Error returns a compact missing validation message for CLI and UI callers.
func (e MissingValidationError) Error() string {
	return "agent validations not found: " + strings.Join(e.IDs, ", ")
}

// NewRunner creates an agent validation runner.
func NewRunner() *Runner {
	return &Runner{}
}

// NewRunnerWithHost creates an agent validation runner with a live boundary.
func NewRunnerWithHost(host AgentHost) *Runner {
	return &Runner{host: host}
}

// SuiteResult stores one full validation run for an agent package.
type SuiteResult struct {
	Total              int      `json:"total"`
	Passed             int      `json:"passed"`
	Failed             int      `json:"failed"`
	Unsupported        int      `json:"unsupported"`
	ToolCallReferences []string `json:"tool_call_references,omitempty"`
	Results            []Result `json:"results"`
}

// Result stores one validation case result.
type Result struct {
	ID          string            `json:"id"`
	Label       string            `json:"label,omitempty"`
	Description string            `json:"description,omitempty"`
	Mode        string            `json:"mode"`
	Prompt      string            `json:"prompt"`
	Input       map[string]any    `json:"input,omitempty"`
	Fixtures    map[string]any    `json:"fixtures,omitempty"`
	Status      string            `json:"status"`
	Response    *Response         `json:"response,omitempty"`
	Assertions  []AssertionResult `json:"assertions,omitempty"`
	Diagnostics []Diagnostic      `json:"diagnostics,omitempty"`
}

// Response stores a mocked or live agent response captured for assertions.
type Response struct {
	Text      string     `json:"text,omitempty"`
	ToolCalls []ToolCall `json:"tool_calls,omitempty"`
	Output    any        `json:"output,omitempty"`
}

// ToolCall stores one tool call selected by an agent response.
type ToolCall struct {
	ID        string         `json:"id,omitempty"`
	Name      string         `json:"name,omitempty"`
	Arguments map[string]any `json:"arguments,omitempty"`
}

// AssertionResult stores the outcome of one validation assertion.
type AssertionResult struct {
	Type     string `json:"type"`
	Path     string `json:"path,omitempty"`
	Passed   bool   `json:"passed"`
	Expected any    `json:"expected,omitempty"`
	Actual   any    `json:"actual,omitempty"`
	Message  string `json:"message,omitempty"`
}

// Diagnostic stores one validation runner diagnostic.
type Diagnostic struct {
	Severity string `json:"severity"`
	Message  string `json:"message"`
}

// RunAll executes every validation declared by the agent package.
func (r *Runner) RunAll(ctx context.Context, agent schema.Agent) SuiteResult {
	result := SuiteResult{
		Results: make([]Result, 0, len(agent.Validations)),
	}
	for _, validation := range agent.Validations {
		addResult(&result, r.run(ctx, agent, validation))
	}
	result.ToolCallReferences = ToolCallReferencesFor(result.Results)
	return result
}

// RunSelected executes selected validation IDs from one agent package.
func (r *Runner) RunSelected(ctx context.Context, agent schema.Agent, validationIDs []string) (SuiteResult, error) {
	return r.RunSelectedModes(ctx, agent, validationIDs, "")
}

// RunSelectedModes executes selected validations that match one validation mode.
func (r *Runner) RunSelectedModes(ctx context.Context, agent schema.Agent, validationIDs []string, mode string) (SuiteResult, error) {
	ids := selectedValidationIDs(validationIDs)
	filter := selectedValidationMode(mode)
	if len(ids) == 0 && filter == "" {
		return r.RunAll(ctx, agent), nil
	}
	byID := map[string]schema.AgentValidation{}
	for _, validation := range agent.Validations {
		id := strings.TrimSpace(validation.ID)
		if id != "" {
			byID[id] = validation
		}
	}
	result := SuiteResult{Results: make([]Result, 0, len(ids))}
	missing := []string{}
	if len(ids) == 0 {
		for _, validation := range agent.Validations {
			if !validationMatchesMode(validation.Mode, filter) {
				continue
			}
			addResult(&result, r.run(ctx, agent, validation))
		}
		result.ToolCallReferences = ToolCallReferencesFor(result.Results)
		return result, nil
	}
	for _, id := range ids {
		validation, ok := byID[id]
		if !ok || !validationMatchesMode(validation.Mode, filter) {
			missing = append(missing, id)
			continue
		}
		addResult(&result, r.run(ctx, agent, validation))
	}
	result.ToolCallReferences = ToolCallReferencesFor(result.Results)
	if len(missing) > 0 {
		return result, MissingValidationError{IDs: missing}
	}
	return result, nil
}

// ToolCallReferencesFor returns stable tool-call ids proved or observed by validations.
func ToolCallReferencesFor(results []Result) []string {
	refs := make([]string, 0)
	for _, result := range results {
		for _, assertion := range result.Assertions {
			if strings.TrimSpace(assertion.Type) != "tool-call" {
				continue
			}
			if !assertion.Passed {
				continue
			}
			refs = appendToolCallReference(refs, fmt.Sprint(assertion.Expected))
		}
		if result.Response == nil {
			continue
		}
		for _, call := range result.Response.ToolCalls {
			refs = appendToolCallReference(refs, commandToolCallReference(call))
			refs = appendToolCallReference(refs, specificToolCallReference(call.Name))
			refs = appendToolCallReference(refs, specificToolCallReference(call.ID))
		}
	}
	return dedupeToolCallReferences(refs)
}

// Run executes one validation declared by an agent package.
func (r *Runner) Run(_ context.Context, validation schema.AgentValidation) Result {
	return r.run(context.Background(), schema.Agent{}, validation)
}

// run executes one validation with package-level agent context.
func (r *Runner) run(ctx context.Context, agent schema.Agent, validation schema.AgentValidation) Result {
	result := Result{
		ID:          strings.TrimSpace(validation.ID),
		Label:       strings.TrimSpace(validation.Label),
		Description: strings.TrimSpace(validation.Description),
		Mode:        validationMode(validation.Mode),
		Prompt:      strings.TrimSpace(validation.Prompt),
		Input:       cloneMap(validation.Input),
		Fixtures:    cloneMap(validation.Fixtures),
		Status:      StatusFailed,
	}
	if result.Mode == "live" {
		return r.runLiveAgentResponse(ctx, agent, validation, result)
	}
	return runMockedAgentResponse(validation, result)
}

// addResult appends a validation result and updates suite counters.
func addResult(result *SuiteResult, item Result) {
	result.Total++
	result.Results = append(result.Results, item)
	switch item.Status {
	case StatusPassed:
		result.Passed++
	case StatusUnsupported:
		result.Unsupported++
	default:
		result.Failed++
	}
}

// runMockedAgentResponse evaluates one validation using a mocked agent response.
func runMockedAgentResponse(validation schema.AgentValidation, result Result) Result {
	mock, ok := mapValue(validation.Mocks, "agent.response")
	if !ok {
		result.Diagnostics = append(result.Diagnostics, Diagnostic{
			Severity: "error",
			Message:  `mocked validation needs "agent.response" response`,
		})
		result.Status = StatusFailed
		return result
	}
	response := mockedResponse(mock)
	result.Response = &response
	result.Assertions = evaluateAssertions(validation, result)
	result.Status = assertionStatus(result.Assertions, result.Diagnostics)
	return result
}

// runLiveAgentResponse evaluates one validation through an injected runtime host.
func (r *Runner) runLiveAgentResponse(
	ctx context.Context,
	agent schema.Agent,
	validation schema.AgentValidation,
	result Result,
) Result {
	if r.host == nil {
		result.Status = StatusUnsupported
		result.Diagnostics = append(result.Diagnostics, Diagnostic{
			Severity: "warning",
			Message:  "live agent validations need an agent runtime host",
		})
		return result
	}
	response, err := r.host.Respond(ctx, Request{
		Agent:      agent,
		Validation: validation,
		Prompt:     result.Prompt,
		Input:      cloneMap(validation.Input),
		Fixtures:   cloneMap(validation.Fixtures),
	})
	result.Response = &response
	if err != nil {
		result.Diagnostics = append(result.Diagnostics, Diagnostic{
			Severity: "error",
			Message:  err.Error(),
		})
	}
	result.Assertions = evaluateAssertions(validation, result)
	result.Status = assertionStatus(result.Assertions, result.Diagnostics)
	return result
}

// mockedResponse converts generic YAML mock data into an agent response.
func mockedResponse(mock map[string]any) Response {
	response := Response{
		Text:   stringFromAny(firstPresent(mock, "text", "response")),
		Output: mock["output"],
	}
	for _, item := range listValue(mock["tool_calls"]) {
		callMap, ok := item.(map[string]any)
		if !ok {
			continue
		}
		response.ToolCalls = append(response.ToolCalls, ToolCall{
			ID:        stringFromAny(callMap["id"]),
			Name:      stringFromAny(callMap["name"]),
			Arguments: mapFromAny(callMap["arguments"]),
		})
	}
	return response
}

// evaluateAssertions checks expected metadata and explicit assertions.
func evaluateAssertions(validation schema.AgentValidation, result Result) []AssertionResult {
	assertions := make([]AssertionResult, 0, len(validation.Assertions)+len(validation.Expected)+2)
	for key, value := range validation.Expected {
		switch strings.TrimSpace(key) {
		case "response_contains", "tool_call":
			continue
		default:
			assertions = append(assertions, AssertionResult{
				Type:     "expected",
				Path:     "expected." + strings.TrimSpace(key),
				Passed:   false,
				Expected: value,
				Message:  "unsupported expected key",
			})
		}
	}
	if expected, ok := validation.Expected["response_contains"]; ok {
		assertions = append(assertions, containsAssertion(
			"response-contains",
			"response.text",
			stringFromAny(expected),
			result.responseText(),
			"response contains expected text",
		))
	}
	if expected, ok := validation.Expected["tool_call"]; ok {
		assertions = append(assertions, toolCallAssertion("tool-call", stringFromAny(expected), result, "tool call matches expected selection"))
	}
	for _, assertion := range validation.Assertions {
		assertions = append(assertions, evaluateAssertion(assertion, result))
	}
	if len(assertions) == 0 {
		assertions = append(assertions, AssertionResult{Type: "configured", Passed: true})
	}
	return assertions
}

// evaluateAssertion checks one explicit assertion record.
func evaluateAssertion(assertion schema.ValidationAssertion, result Result) AssertionResult {
	assertionType := strings.TrimSpace(assertion.Type)
	switch assertionType {
	case "response-contains":
		return containsAssertion(assertionType, "response.text", assertion.Contains, result.responseText(), assertion.Message)
	case "tool-call":
		return toolCallAssertion(assertionType, stringFromAny(assertion.Equals), result, assertion.Message)
	case "json-path":
		actual := pathValue(resultMap(result), assertion.Path)
		if assertion.Contains != "" {
			return containsAssertion(assertionType, assertion.Path, assertion.Contains, fmt.Sprint(actual), assertion.Message)
		}
		if assertion.Matches != "" {
			return matchesAssertion(assertionType, assertion.Path, assertion.Matches, fmt.Sprint(actual), assertion.Message)
		}
		return compareAssertion(assertionType, assertion.Path, assertion.Equals, actual, assertion.Message)
	case "schema":
		actual := pathValue(resultMap(result), assertion.Path)
		validation := command.ValidateOutput(actual, assertion.Schema)
		return AssertionResult{
			Type:    assertionType,
			Path:    assertion.Path,
			Passed:  validation.Valid,
			Message: strings.Join(validation.Errors, "; "),
		}
	default:
		return AssertionResult{
			Type:    assertionType,
			Path:    assertion.Path,
			Passed:  false,
			Message: "unsupported assertion type",
		}
	}
}

// responseText returns the captured response text for assertions.
func (r Result) responseText() string {
	if r.Response == nil {
		return ""
	}
	return r.Response.Text
}

// compareAssertion checks exact value equality through display-stable values.
func compareAssertion(assertionType string, path string, expected any, actual any, message string) AssertionResult {
	passed := fmt.Sprint(expected) == fmt.Sprint(actual)
	return AssertionResult{
		Type:     assertionType,
		Path:     path,
		Passed:   passed,
		Expected: expected,
		Actual:   actual,
		Message:  assertionMessage(passed, message, fmt.Sprintf("expected %v, got %v", expected, actual)),
	}
}

// containsAssertion checks that actual text contains expected text.
func containsAssertion(assertionType string, path string, expected string, actual string, message string) AssertionResult {
	passed := expected != "" && strings.Contains(actual, expected)
	return AssertionResult{
		Type:     assertionType,
		Path:     path,
		Passed:   passed,
		Expected: expected,
		Actual:   actual,
		Message:  assertionMessage(passed, message, fmt.Sprintf("expected %q to contain %q", actual, expected)),
	}
}

// matchesAssertion checks actual text against a regular expression.
func matchesAssertion(assertionType string, path string, pattern string, actual string, message string) AssertionResult {
	matched, err := regexp.MatchString(pattern, actual)
	passed := pattern != "" && err == nil && matched
	if err != nil {
		message = err.Error()
	}
	return AssertionResult{
		Type:     assertionType,
		Path:     path,
		Passed:   passed,
		Expected: pattern,
		Actual:   actual,
		Message:  assertionMessage(passed, message, fmt.Sprintf("expected %q to match %q", actual, pattern)),
	}
}

// toolCallAssertion checks that the agent selected an expected tool call.
func toolCallAssertion(assertionType string, expected string, result Result, message string) AssertionResult {
	expectedCandidates := toolCallAssertionCandidates(expected)
	actual := []string{}
	if result.Response != nil {
		for _, call := range result.Response.ToolCalls {
			callCandidates := toolCallAssertionCandidatesForCall(call)
			actual = append(actual, firstNonEmpty(callCandidates...))
			if toolCallCandidatesIntersect(expectedCandidates, callCandidates) {
				return AssertionResult{
					Type:     assertionType,
					Path:     "response.tool_calls",
					Passed:   true,
					Expected: expected,
					Actual:   strings.Join(dedupeToolCallReferences(actual), ","),
				}
			}
		}
	}
	actual = dedupeToolCallReferences(actual)
	return AssertionResult{
		Type:     assertionType,
		Path:     "response.tool_calls",
		Passed:   false,
		Expected: expected,
		Actual:   strings.Join(actual, ","),
		Message:  assertionMessage(false, message, fmt.Sprintf("expected tool call %q in %q", expected, strings.Join(actual, ","))),
	}
}

// toolCallAssertionCandidates returns compatible contract ids for one value.
func toolCallAssertionCandidates(value string) []string {
	trimmed := strings.TrimSpace(value)
	candidates := []string{}
	candidates = appendToolCallReference(candidates, trimmed)
	candidates = appendToolCallReference(candidates, specificToolCallReference(trimmed))
	return dedupeToolCallReferences(candidates)
}

// toolCallAssertionCandidatesForCall returns compatible ids for one tool call.
func toolCallAssertionCandidatesForCall(call ToolCall) []string {
	candidates := []string{}
	candidates = appendToolCallReference(candidates, commandToolCallReference(call))
	candidates = append(candidates, toolCallAssertionCandidates(call.ID)...)
	candidates = append(candidates, toolCallAssertionCandidates(call.Name)...)
	return dedupeToolCallReferences(candidates)
}

// toolCallCandidatesIntersect reports whether two candidate lists overlap.
func toolCallCandidatesIntersect(expected []string, actual []string) bool {
	for _, want := range expected {
		for _, got := range actual {
			if want != "" && want == got {
				return true
			}
		}
	}
	return false
}

// appendToolCallReference adds non-empty agent tool-call contract references.
func appendToolCallReference(refs []string, value string) []string {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return refs
	}
	return append(refs, trimmed)
}

// commandToolCallReference extracts command operation ids from tool arguments.
func commandToolCallReference(call ToolCall) string {
	templateID := stringFromAny(call.Arguments["template_id"])
	if templateID == "" {
		return ""
	}
	return "command:" + templateID
}

// specificToolCallReference returns tool-call ids that name package contracts.
func specificToolCallReference(value string) string {
	trimmed := strings.TrimSpace(value)
	if strings.HasPrefix(trimmed, "command:") || strings.HasPrefix(trimmed, "mcp:") {
		return trimmed
	}
	if !strings.Contains(trimmed, ":") && strings.Contains(trimmed, ".") {
		return "command:" + trimmed
	}
	return ""
}

// dedupeToolCallReferences removes repeated references while preserving order.
func dedupeToolCallReferences(refs []string) []string {
	out := make([]string, 0, len(refs))
	seen := map[string]struct{}{}
	for _, ref := range refs {
		trimmed := strings.TrimSpace(ref)
		if trimmed == "" {
			continue
		}
		if _, ok := seen[trimmed]; ok {
			continue
		}
		seen[trimmed] = struct{}{}
		out = append(out, trimmed)
	}
	return out
}

// assertionMessage returns an empty message when an assertion passed.
func assertionMessage(passed bool, configured string, fallback string) string {
	if passed {
		return ""
	}
	if strings.TrimSpace(configured) != "" {
		return strings.TrimSpace(configured)
	}
	return fallback
}

// assertionStatus computes a result status from assertions and diagnostics.
func assertionStatus(assertions []AssertionResult, diagnostics []Diagnostic) string {
	for _, diagnostic := range diagnostics {
		if strings.EqualFold(diagnostic.Severity, "error") {
			return StatusFailed
		}
	}
	for _, assertion := range assertions {
		if !assertion.Passed {
			return StatusFailed
		}
	}
	return StatusPassed
}

// resultMap builds a generic result object for path assertions.
func resultMap(result Result) map[string]any {
	response := map[string]any{}
	if result.Response != nil {
		response["text"] = result.Response.Text
		response["tool_calls"] = toolCallMaps(result.Response.ToolCalls)
		response["output"] = result.Response.Output
	}
	return map[string]any{
		"id":       result.ID,
		"mode":     result.Mode,
		"prompt":   result.Prompt,
		"input":    result.Input,
		"fixtures": result.Fixtures,
		"response": response,
		"text":     result.responseText(),
	}
}

// toolCallMaps converts typed tool calls into generic maps.
func toolCallMaps(calls []ToolCall) []any {
	out := make([]any, 0, len(calls))
	for _, call := range calls {
		out = append(out, map[string]any{
			"id":        call.ID,
			"name":      call.Name,
			"arguments": call.Arguments,
		})
	}
	return out
}

// pathValue resolves simple dot-separated paths from maps and lists.
func pathValue(value any, path string) any {
	trimmed := strings.Trim(strings.TrimSpace(path), "$.")
	if trimmed == "" {
		return value
	}
	current := value
	for _, part := range strings.Split(trimmed, ".") {
		switch typed := current.(type) {
		case map[string]any:
			current = typed[part]
		case []any:
			index, err := strconv.Atoi(part)
			if err != nil || index < 0 || index >= len(typed) {
				return nil
			}
			current = typed[index]
		default:
			return nil
		}
	}
	return current
}

// mapValue returns one nested map value.
func mapValue(values map[string]any, key string) (map[string]any, bool) {
	value, ok := values[key]
	if !ok {
		return nil, false
	}
	result, ok := value.(map[string]any)
	return result, ok
}

// mapFromAny returns a map when value has map shape.
func mapFromAny(value any) map[string]any {
	if result, ok := value.(map[string]any); ok {
		return result
	}
	return nil
}

// cloneMap returns a shallow copy of generic metadata maps.
func cloneMap(value map[string]any) map[string]any {
	if len(value) == 0 {
		return nil
	}
	result := make(map[string]any, len(value))
	for key, item := range value {
		result[key] = item
	}
	return result
}

// listValue returns a slice when value has list shape.
func listValue(value any) []any {
	if value == nil {
		return nil
	}
	if result, ok := value.([]any); ok {
		return result
	}
	return nil
}

// firstPresent returns the first map value present for the requested keys.
func firstPresent(values map[string]any, keys ...string) any {
	for _, key := range keys {
		if value, ok := values[key]; ok {
			return value
		}
	}
	return nil
}

// stringFromAny returns a display-stable string for generic data.
func stringFromAny(value any) string {
	if value == nil {
		return ""
	}
	if text, ok := value.(string); ok {
		return strings.TrimSpace(text)
	}
	return strings.TrimSpace(fmt.Sprint(value))
}

// validationMode normalizes empty validation modes to mocked.
func validationMode(value string) string {
	mode := strings.TrimSpace(value)
	if mode == "" {
		return "mocked"
	}
	return mode
}

// selectedValidationMode normalizes optional mode filters.
func selectedValidationMode(value string) string {
	switch strings.TrimSpace(value) {
	case "mocked":
		return "mocked"
	case "live":
		return "live"
	default:
		return ""
	}
}

// validationMatchesMode reports whether a validation should run for a filter.
func validationMatchesMode(value string, mode string) bool {
	filter := selectedValidationMode(mode)
	return filter == "" || validationMode(value) == filter
}

// selectedValidationIDs normalizes requested validation IDs while preserving order.
func selectedValidationIDs(validationIDs []string) []string {
	out := make([]string, 0, len(validationIDs))
	seen := map[string]struct{}{}
	for _, value := range validationIDs {
		id := strings.TrimSpace(value)
		if id == "" {
			continue
		}
		if _, ok := seen[id]; ok {
			continue
		}
		seen[id] = struct{}{}
		out = append(out, id)
	}
	return out
}

// firstNonEmpty returns the first non-empty trimmed value.
func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if trimmed := strings.TrimSpace(value); trimmed != "" {
			return trimmed
		}
	}
	return ""
}

// CloneResult returns a JSON-stable copy for callers that need plain maps.
func CloneResult(result Result) map[string]any {
	encoded, err := json.Marshal(result)
	if err != nil {
		return map[string]any{}
	}
	var out map[string]any
	if err := json.Unmarshal(encoded, &out); err != nil {
		return map[string]any{}
	}
	return out
}
