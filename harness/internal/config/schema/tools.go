// This file validates tool configuration schema values.
package schema

import (
	"fmt"
	"net/url"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

var localExecCommandNamePattern = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_-]*$`)

// Validate checks all configured tool sections.
func (c *Tools) Validate() error {
	if c == nil {
		return fmt.Errorf("config is nil")
	}
	if err := validateLocalExec(c.LocalExec); err != nil {
		return err
	}
	if err := validateMCP(c.MCP); err != nil {
		return err
	}
	if err := validateMemory(c.Memory); err != nil {
		return err
	}
	return validateToolMetadata(c.NodePresets, c.Validations, c.LocalExec, c.MCP)
}

// DefaultTimeoutDuration returns the configured local exec timeout or the
// package default when unset or invalid.
func (c LocalExec) DefaultTimeoutDuration() time.Duration {
	if strings.TrimSpace(c.DefaultTimeout) == "" {
		return defaultLocalExecTimeout
	}
	timeout, err := time.ParseDuration(strings.TrimSpace(c.DefaultTimeout))
	if err != nil {
		return defaultLocalExecTimeout
	}
	return timeout
}

// DefaultOutputLimit returns the configured local exec output limit or the
// package default when unset.
func (c LocalExec) DefaultOutputLimit() int {
	if c.DefaultMaxOutputBytes == 0 {
		return defaultLocalExecMaxOutputBytes
	}
	return c.DefaultMaxOutputBytes
}

// validateLocalExec checks local execution configuration and command entries.
func validateLocalExec(c LocalExec) error {
	if !c.Enabled {
		return nil
	}
	if strings.TrimSpace(c.DefaultTimeout) != "" {
		timeout, err := time.ParseDuration(strings.TrimSpace(c.DefaultTimeout))
		if err != nil {
			return fmt.Errorf("local-exec default-timeout: %w", err)
		}
		if timeout <= 0 {
			return fmt.Errorf("local-exec default-timeout must be positive")
		}
	}
	if c.DefaultMaxOutputBytes < 0 {
		return fmt.Errorf("local-exec default-max-output-bytes must not be negative")
	}
	if c.DefaultMaxOutputBytes == 0 {
		c.DefaultMaxOutputBytes = defaultLocalExecMaxOutputBytes
	}
	if c.DefaultMaxOutputBytes <= 0 {
		return fmt.Errorf("local-exec default-max-output-bytes must be positive")
	}
	if len(c.Commands) == 0 {
		return fmt.Errorf("local-exec commands must not be empty when enabled")
	}
	seen := make(map[string]struct{}, len(c.Commands))
	for _, command := range c.Commands {
		name, err := validateLocalExecCommandName(command.Name)
		if err != nil {
			return err
		}
		if _, ok := seen[name]; ok {
			return fmt.Errorf("local-exec duplicate command %q", name)
		}
		seen[name] = struct{}{}
		if err := validateLocalExecCommand(command, name); err != nil {
			return err
		}
	}
	return nil
}

// validateLocalExecCommandName trims and validates a configured command name.
func validateLocalExecCommandName(value string) (string, error) {
	name := strings.TrimSpace(value)
	if name == "" {
		return "", fmt.Errorf("local-exec command name must not be empty")
	}
	if !localExecCommandNamePattern.MatchString(name) {
		return "", fmt.Errorf("local-exec command %q uses an invalid name", name)
	}
	return name, nil
}

// validateLocalExecCommand checks one local execution command entry.
func validateLocalExecCommand(command LocalExecCommand, name string) error {
	if strings.TrimSpace(command.Executable) == "" {
		return fmt.Errorf("local-exec command %q executable must not be empty", name)
	}
	if strings.TrimSpace(command.Description) == "" {
		return fmt.Errorf("local-exec command %q description must not be empty", name)
	}
	for key := range command.Env {
		if strings.TrimSpace(key) == "" {
			return fmt.Errorf("local-exec command %q env must not contain empty variable names", name)
		}
	}
	if err := validateLocalExecCommandTimeout(name, command.Timeout); err != nil {
		return err
	}
	if command.MaxOutputBytes < 0 {
		return fmt.Errorf("local-exec command %q max-output-bytes must not be negative", name)
	}
	if err := validateCommandSurface(name, command.Surface); err != nil {
		return err
	}
	if err := validateCommandOperations(name, command.Operations); err != nil {
		return err
	}
	return nil
}

// validateCommandSurface checks model-facing CLI surface documentation.
func validateCommandSurface(commandName string, surface CommandSurface) error {
	for _, flag := range surface.GlobalFlags {
		if strings.TrimSpace(flag.Name) == "" {
			return fmt.Errorf("local-exec command %q global flag name must not be empty", commandName)
		}
	}
	return validateCommandSubcommands(commandName, "", surface.Subcommands)
}

// validateCommandSubcommands checks one sibling level of CLI subcommands.
func validateCommandSubcommands(commandName string, parentPath string, subcommands []CommandSubcommand) error {
	seen := make(map[string]struct{}, len(subcommands))
	for _, subcommand := range subcommands {
		name := strings.TrimSpace(subcommand.Name)
		if name == "" {
			return fmt.Errorf("local-exec command %q subcommand name must not be empty", commandName)
		}
		path := name
		if strings.TrimSpace(parentPath) != "" {
			path = strings.TrimSpace(parentPath) + " " + name
		}
		if _, ok := seen[name]; ok {
			return fmt.Errorf("local-exec command %q duplicate subcommand %q", commandName, path)
		}
		seen[name] = struct{}{}
		for _, flag := range subcommand.Flags {
			if strings.TrimSpace(flag.Name) == "" {
				return fmt.Errorf("local-exec command %q subcommand %q flag name must not be empty", commandName, path)
			}
		}
		if err := validateCommandSubcommands(commandName, path, subcommand.Subcommands); err != nil {
			return err
		}
	}
	return nil
}

// validateCommandOperations checks deterministic workflow-callable operations.
func validateCommandOperations(commandName string, operations []CommandOperation) error {
	seen := make(map[string]struct{}, len(operations))
	for _, operation := range operations {
		name, err := validateLocalExecCommandName(operation.Name)
		if err != nil {
			return fmt.Errorf("local-exec command %q operation: %w", commandName, err)
		}
		if _, ok := seen[name]; ok {
			return fmt.Errorf("local-exec command %q duplicate operation %q", commandName, name)
		}
		seen[name] = struct{}{}
		if strings.TrimSpace(operation.Description) == "" {
			return fmt.Errorf("local-exec command %q operation %q description must not be empty", commandName, name)
		}
		if err := validateLocalExecCommandTimeout(commandName+"."+name, operation.Timeout); err != nil {
			return err
		}
		if operation.MaxOutputBytes < 0 {
			return fmt.Errorf("local-exec command %q operation %q max-output-bytes must not be negative", commandName, name)
		}
		for key := range operation.Env {
			if strings.TrimSpace(key) == "" {
				return fmt.Errorf("local-exec command %q operation %q env must not contain empty variable names", commandName, name)
			}
		}
		if err := validateCommandOutput(commandName, name, operation.Output); err != nil {
			return err
		}
	}
	return nil
}

// validateCommandOutput checks the known generic output contract values.
func validateCommandOutput(commandName string, operationName string, output CommandOutput) error {
	switch strings.ToLower(strings.TrimSpace(output.Format)) {
	case "", "json", "text", "plain":
	default:
		return fmt.Errorf("local-exec command %q operation %q output format must be json, text, or plain", commandName, operationName)
	}
	switch strings.ToLower(strings.TrimSpace(output.Source)) {
	case "", "stdout", "stderr", "combined":
	default:
		return fmt.Errorf("local-exec command %q operation %q output source must be stdout, stderr, or combined", commandName, operationName)
	}
	return nil
}

// validateLocalExecCommandTimeout checks a command-specific timeout override.
func validateLocalExecCommandTimeout(name, value string) error {
	if strings.TrimSpace(value) == "" {
		return nil
	}
	timeout, err := time.ParseDuration(strings.TrimSpace(value))
	if err != nil {
		return fmt.Errorf("local-exec command %q timeout: %w", name, err)
	}
	if timeout <= 0 {
		return fmt.Errorf("local-exec command %q timeout must be positive", name)
	}
	return nil
}

// validateToolMetadata checks authoring presets and portable validation metadata.
func validateToolMetadata(presets []NodePreset, validations []ToolValidation, localExec LocalExec, mcp MCP) error {
	operations := commandOperationIDs(localExec.Commands)
	commandTemplates := commandTemplateIDs(localExec.Commands)
	mcpTools := configuredMCPToolIDs(mcp.Servers)
	presetIDs := make(map[string]struct{}, len(presets))
	for _, preset := range presets {
		id, err := validateLocalExecCommandName(preset.ID)
		if err != nil {
			return fmt.Errorf("node preset: %w", err)
		}
		if _, ok := presetIDs[id]; ok {
			return fmt.Errorf("node preset duplicate %q", id)
		}
		presetIDs[id] = struct{}{}
		switch strings.TrimSpace(preset.Action) {
		case "command.execute", "mcp.call":
		default:
			return fmt.Errorf("node preset %q action must be command.execute or mcp.call", id)
		}
		if err := validateNodePresetArguments(id, preset, commandTemplates, mcpTools); err != nil {
			return err
		}
	}
	validationIDs := make(map[string]struct{}, len(validations))
	for _, validation := range validations {
		id, err := validateLocalExecCommandName(validation.ID)
		if err != nil {
			return fmt.Errorf("validation: %w", err)
		}
		if _, ok := validationIDs[id]; ok {
			return fmt.Errorf("validation duplicate %q", id)
		}
		validationIDs[id] = struct{}{}
		if err := validateToolValidation(id, validation, presetIDs, operations, mcpTools); err != nil {
			return err
		}
	}
	return nil
}

// validateNodePresetArguments checks preset action arguments against tools.
func validateNodePresetArguments(
	id string,
	preset NodePreset,
	commandTemplates map[string]struct{},
	mcpTools map[string]map[string]struct{},
) error {
	switch strings.TrimSpace(preset.Action) {
	case "command.execute":
		templateID := stringArgument(preset.Arguments, "template_id")
		if templateID == "" {
			return fmt.Errorf("node preset %q command.execute needs template_id", id)
		}
		if _, ok := commandTemplates[templateID]; !ok {
			return fmt.Errorf("node preset %q references unknown command template %q", id, templateID)
		}
	case "mcp.call":
		serverName := stringArgument(preset.Arguments, "server_id")
		toolName := stringArgument(preset.Arguments, "tool")
		if serverName == "" || toolName == "" {
			return fmt.Errorf("node preset %q mcp.call needs server_id and tool", id)
		}
		serverTools, ok := mcpTools[serverName]
		if !ok {
			return fmt.Errorf("node preset %q references unknown MCP server %q", id, serverName)
		}
		if _, ok := serverTools[toolName]; !ok {
			return fmt.Errorf("node preset %q references unknown MCP tool %q on server %q", id, toolName, serverName)
		}
	}
	return nil
}

// commandTemplateIDs returns template ids the command runtime can execute.
func commandTemplateIDs(commands []LocalExecCommand) map[string]struct{} {
	out := make(map[string]struct{}, len(commands))
	for _, command := range commands {
		commandName := strings.TrimSpace(command.Name)
		if commandName == "" {
			continue
		}
		if len(command.Operations) == 0 {
			out[commandName] = struct{}{}
			continue
		}
		for _, operation := range command.Operations {
			operationName := strings.TrimSpace(operation.Name)
			if operationName != "" {
				out[commandName+"."+operationName] = struct{}{}
			}
		}
	}
	return out
}

// stringArgument returns a trimmed string action argument.
func stringArgument(values map[string]any, key string) string {
	value, _ := values[key].(string)
	return strings.TrimSpace(value)
}

// commandOperationIDs returns configured command.operation identifiers.
func commandOperationIDs(commands []LocalExecCommand) map[string]map[string]struct{} {
	out := make(map[string]map[string]struct{}, len(commands))
	for _, command := range commands {
		commandName := strings.TrimSpace(command.Name)
		if commandName == "" {
			continue
		}
		if _, ok := out[commandName]; !ok {
			out[commandName] = make(map[string]struct{}, len(command.Operations))
		}
		for _, operation := range command.Operations {
			operationName := strings.TrimSpace(operation.Name)
			if operationName != "" {
				out[commandName][operationName] = struct{}{}
			}
		}
	}
	return out
}

// configuredMCPToolIDs returns configured server.tool identifiers.
func configuredMCPToolIDs(servers []MCPServer) map[string]map[string]struct{} {
	out := make(map[string]map[string]struct{}, len(servers))
	for _, server := range servers {
		serverName := strings.TrimSpace(server.Name)
		if serverName == "" {
			continue
		}
		if _, ok := out[serverName]; !ok {
			out[serverName] = make(map[string]struct{}, len(server.Tools.Allow))
		}
		for _, tool := range server.Tools.Allow {
			toolName := strings.TrimSpace(tool)
			if toolName != "" {
				out[serverName][toolName] = struct{}{}
			}
		}
	}
	return out
}

// validateToolValidation checks one portable validation target.
func validateToolValidation(
	id string,
	validation ToolValidation,
	presetIDs map[string]struct{},
	operations map[string]map[string]struct{},
	mcpTools map[string]map[string]struct{},
) error {
	switch strings.TrimSpace(validation.Mode) {
	case "", "mocked", "live":
	default:
		return fmt.Errorf("validation %q mode must be mocked or live", id)
	}
	target := validation.Target
	switch strings.TrimSpace(target.Type) {
	case "workflow-node":
		presetID := strings.TrimSpace(target.PresetID)
		hasPreset := presetID != ""
		hasCommand := strings.TrimSpace(target.Command) != "" || strings.TrimSpace(target.Operation) != ""
		hasMCP := strings.TrimSpace(target.MCPServer) != "" || strings.TrimSpace(target.MCPTool) != ""
		selected := boolCount(hasPreset, hasCommand, hasMCP)
		if selected > 1 {
			return fmt.Errorf("validation %q workflow-node target must choose preset-id, command-operation, or mcp-tool", id)
		}
		if hasCommand {
			return validateCommandOperationTarget(id, target, operations, "workflow-node")
		}
		if hasMCP {
			return validateMCPToolTarget(id, target, mcpTools, "workflow-node")
		}
		if _, ok := presetIDs[presetID]; !ok {
			return fmt.Errorf("validation %q references unknown preset %q", id, presetID)
		}
	case "command-operation":
		if err := validateCommandOperationTarget(id, target, operations, "command-operation"); err != nil {
			return err
		}
	case "mcp-tool":
		if err := validateMCPToolTarget(id, target, mcpTools, "mcp-tool"); err != nil {
			return err
		}
	case "agent-tool-call":
		if strings.TrimSpace(validation.Prompt) == "" {
			return fmt.Errorf("validation %q agent-tool-call target needs a prompt", id)
		}
		if err := validateAgentToolCallTarget(id, target, operations, mcpTools); err != nil {
			return err
		}
	case "":
		return fmt.Errorf("validation %q target type must not be empty", id)
	default:
		return fmt.Errorf("validation %q target type must be workflow-node, command-operation, mcp-tool, or agent-tool-call", id)
	}
	if err := validateToolValidationExpected(id, validation.Expected); err != nil {
		return err
	}
	return validateToolValidationAssertions(id, validation.Assertions)
}

// validateCommandOperationTarget checks one configured command operation target.
func validateCommandOperationTarget(
	id string,
	target ToolValidationTarget,
	operations map[string]map[string]struct{},
	targetType string,
) error {
	commandName := strings.TrimSpace(target.Command)
	operationName := strings.TrimSpace(target.Operation)
	if commandName == "" || operationName == "" {
		return fmt.Errorf("validation %q %s target needs command and operation", id, targetType)
	}
	commandOperations, ok := operations[commandName]
	if !ok {
		return fmt.Errorf("validation %q references unknown command %q", id, commandName)
	}
	if _, ok := commandOperations[operationName]; !ok {
		return fmt.Errorf("validation %q references unknown operation %q on command %q", id, operationName, commandName)
	}
	return nil
}

// boolCount returns the number of true values.
func boolCount(values ...bool) int {
	count := 0
	for _, value := range values {
		if value {
			count++
		}
	}
	return count
}

// validateAgentToolCallTarget checks the concrete tool an agent should select.
func validateAgentToolCallTarget(
	id string,
	target ToolValidationTarget,
	operations map[string]map[string]struct{},
	mcpTools map[string]map[string]struct{},
) error {
	hasCommand := strings.TrimSpace(target.Command) != "" || strings.TrimSpace(target.Operation) != ""
	hasMCP := strings.TrimSpace(target.MCPServer) != "" || strings.TrimSpace(target.MCPTool) != ""
	switch {
	case hasCommand && hasMCP:
		return fmt.Errorf("validation %q agent-tool-call target must choose command-operation or mcp-tool, not both", id)
	case hasCommand:
		commandName := strings.TrimSpace(target.Command)
		operationName := strings.TrimSpace(target.Operation)
		if commandName == "" || operationName == "" {
			return fmt.Errorf("validation %q agent-tool-call command target needs command and operation", id)
		}
		commandOperations, ok := operations[commandName]
		if !ok {
			return fmt.Errorf("validation %q references unknown command %q", id, commandName)
		}
		if _, ok := commandOperations[operationName]; !ok {
			return fmt.Errorf("validation %q references unknown operation %q on command %q", id, operationName, commandName)
		}
	case hasMCP:
		if err := validateMCPToolTarget(id, target, mcpTools, "agent-tool-call MCP"); err != nil {
			return err
		}
	default:
		return fmt.Errorf("validation %q agent-tool-call target needs command-operation or mcp-tool", id)
	}
	return nil
}

// validateMCPToolTarget checks one configured MCP tool target.
func validateMCPToolTarget(
	id string,
	target ToolValidationTarget,
	mcpTools map[string]map[string]struct{},
	targetType string,
) error {
	serverName := strings.TrimSpace(target.MCPServer)
	toolName := strings.TrimSpace(target.MCPTool)
	if serverName == "" || toolName == "" {
		return fmt.Errorf("validation %q %s target needs mcp-server and mcp-tool", id, targetType)
	}
	serverTools, ok := mcpTools[serverName]
	if !ok {
		return fmt.Errorf("validation %q references unknown MCP server %q", id, serverName)
	}
	if _, ok := serverTools[toolName]; !ok {
		return fmt.Errorf("validation %q references unknown MCP tool %q on server %q", id, toolName, serverName)
	}
	return nil
}

// validateToolValidationAssertions checks assertion metadata without executing it.
func validateToolValidationAssertions(id string, assertions []ValidationAssertion) error {
	for index, assertion := range assertions {
		assertionType := strings.TrimSpace(assertion.Type)
		switch assertionType {
		case "status", "exit-code", "exit-code-not-equals", "exit-code-greater-than", "exit-code-less-than", "json-path", "stdout-contains", "stderr-contains", "schema":
		default:
			return fmt.Errorf("validation %q assertion %d uses an unsupported type", id, index+1)
		}
		if err := validateValidationAssertionExpectation("validation", id, index, assertion, assertionType); err != nil {
			return err
		}
	}
	return nil
}

// validateToolValidationExpected checks shortcut expectations on tool validations.
func validateToolValidationExpected(id string, expected map[string]any) error {
	for key, value := range expected {
		expectedKey := strings.TrimSpace(key)
		switch expectedKey {
		case "status":
			if value == nil || strings.TrimSpace(fmt.Sprint(value)) == "" {
				return fmt.Errorf("validation %q expected status must not be empty", id)
			}
		case "exit_code":
			if value == nil {
				return fmt.Errorf("validation %q expected exit_code must not be empty", id)
			}
		default:
			if expectedKey == "" {
				return fmt.Errorf("validation %q expected key must not be empty", id)
			}
			return fmt.Errorf("validation %q expected %q is unsupported", id, expectedKey)
		}
	}
	return nil
}

// validateMCP checks MCP server configuration when MCP is enabled.
func validateMCP(c MCP) error {
	if !c.Enabled {
		return nil
	}
	if len(c.Servers) == 0 {
		return fmt.Errorf("mcp servers must not be empty when enabled")
	}
	seen := make(map[string]struct{}, len(c.Servers))
	for _, server := range c.Servers {
		name, err := validateMCPServerName(server.Name)
		if err != nil {
			return err
		}
		if _, ok := seen[name]; ok {
			return fmt.Errorf("mcp duplicate server %q", name)
		}
		seen[name] = struct{}{}
		if err := validateMCPServer(server, name); err != nil {
			return err
		}
	}
	return nil
}

// validateMCPServerName trims and validates one MCP server name.
func validateMCPServerName(value string) (string, error) {
	name := strings.TrimSpace(value)
	if name == "" {
		return "", fmt.Errorf("mcp server name must not be empty")
	}
	if !localExecCommandNamePattern.MatchString(name) {
		return "", fmt.Errorf("mcp server %q uses an invalid name", name)
	}
	return name, nil
}

// validateMCPServer checks one MCP server transport and tool configuration.
func validateMCPServer(server MCPServer, name string) error {
	switch normalizeMCPTransport(server.Transport) {
	case "stdio":
		if strings.TrimSpace(server.Command) == "" {
			return fmt.Errorf("mcp server %q command must not be empty for stdio transport", name)
		}
		if strings.TrimSpace(server.Endpoint) != "" || strings.TrimSpace(server.URL) != "" {
			return fmt.Errorf("mcp server %q endpoint/url is only valid for http transport", name)
		}
		if err := validateMCPFilesystemRoots(server, name); err != nil {
			return err
		}
	case "streamable-http":
		if strings.TrimSpace(server.Command) != "" {
			return fmt.Errorf("mcp server %q command is only valid for stdio transport", name)
		}
		if len(server.Args) > 0 {
			return fmt.Errorf("mcp server %q args are only valid for stdio transport", name)
		}
		endpoint := mcpServerEndpoint(server)
		if endpoint == "" {
			return fmt.Errorf("mcp server %q endpoint must not be empty for http transport", name)
		}
		if err := validateHTTPURL(endpoint); err != nil {
			return fmt.Errorf("mcp server %q endpoint: %w", name, err)
		}
	default:
		return fmt.Errorf("mcp server %q transport must be stdio or streamable-http", name)
	}
	if len(server.RequireConfirmationTools) > 0 && server.RequireConfirmation {
		return fmt.Errorf("mcp server %q require-confirmation-tools cannot be combined with require-confirmation", name)
	}
	if err := validateUniqueNonEmptyStrings("mcp server "+name+" tools allow", server.Tools.Allow); err != nil {
		return err
	}
	if err := validateUniqueNonEmptyStrings("mcp server "+name+" require-confirmation-tools", server.RequireConfirmationTools); err != nil {
		return err
	}
	for key := range server.Env {
		if strings.TrimSpace(key) == "" {
			return fmt.Errorf("mcp server %q env must not contain empty variable names", name)
		}
	}
	for key := range server.Headers {
		if strings.TrimSpace(key) == "" {
			return fmt.Errorf("mcp server %q headers must not contain empty names", name)
		}
	}
	for key, envName := range server.HeadersFromEnv {
		if strings.TrimSpace(key) == "" {
			return fmt.Errorf("mcp server %q headers-from-env must not contain empty header names", name)
		}
		if strings.TrimSpace(envName) == "" {
			return fmt.Errorf("mcp server %q headers-from-env %q must name an environment variable", name, key)
		}
	}
	return nil
}

// normalizeMCPTransport maps supported transport aliases to canonical names.
func normalizeMCPTransport(value string) string {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "stdio":
		return "stdio"
	case "http", "streamable-http":
		return "streamable-http"
	default:
		return strings.ToLower(strings.TrimSpace(value))
	}
}

// mcpServerEndpoint returns the preferred HTTP endpoint field.
func mcpServerEndpoint(server MCPServer) string {
	if endpoint := strings.TrimSpace(server.Endpoint); endpoint != "" {
		return endpoint
	}
	return strings.TrimSpace(server.URL)
}

// validateHTTPURL checks that an MCP endpoint is an absolute HTTP(S) URL.
func validateHTTPURL(value string) error {
	parsed, err := url.Parse(value)
	if err != nil {
		return err
	}
	if parsed.Scheme != "http" && parsed.Scheme != "https" {
		return fmt.Errorf("scheme must be http or https")
	}
	if parsed.Host == "" {
		return fmt.Errorf("host must not be empty")
	}
	return nil
}

// validateMemory checks runtime memory domain grants and endpoint references.
func validateMemory(memory Memory) error {
	if len(memory.ReadDomains) == 0 {
		return nil
	}
	if strings.TrimSpace(memory.Actor) == "" {
		return fmt.Errorf("memory actor must not be empty when read-domains are configured")
	}
	if len(memory.WriteDomains) == 0 {
		return fmt.Errorf("memory write-domains must not be empty when read-domains are configured")
	}
	if strings.TrimSpace(memory.DefaultWriteDomain) == "" {
		return fmt.Errorf("memory default-write-domain must not be empty when read-domains are configured")
	}
	seen := make(map[string]struct{}, len(memory.ReadDomains))
	for _, domain := range memory.ReadDomains {
		id, err := validateMCPServerName(domain.ID)
		if err != nil {
			return fmt.Errorf("memory domain id: %w", err)
		}
		if _, ok := seen[id]; ok {
			return fmt.Errorf("memory duplicate domain %q", id)
		}
		seen[id] = struct{}{}
		if strings.TrimSpace(domain.Endpoint) == "" {
			return fmt.Errorf("memory domain %q endpoint must not be empty", id)
		}
		if err := validateHTTPURL(domain.Endpoint); err != nil {
			return fmt.Errorf("memory domain %q endpoint: %w", id, err)
		}
		for key, envName := range domain.HeadersFromEnv {
			if strings.TrimSpace(key) == "" || strings.TrimSpace(envName) == "" {
				return fmt.Errorf("memory domain %q headers-from-env must not contain empty names", id)
			}
		}
	}
	for _, id := range append(append([]string{}, memory.WriteDomains...), memory.DefaultWriteDomain) {
		if strings.TrimSpace(id) == "" {
			continue
		}
		if _, ok := seen[strings.TrimSpace(id)]; !ok {
			return fmt.Errorf("memory grant references unknown domain %q", id)
		}
	}
	if strings.TrimSpace(memory.DefaultWriteDomain) != "" && !containsString(memory.WriteDomains, memory.DefaultWriteDomain) {
		return fmt.Errorf("memory default-write-domain must be included in write-domains")
	}
	for _, flow := range memory.AllowedFlows {
		from := strings.TrimSpace(flow.From)
		to := strings.TrimSpace(flow.To)
		if _, ok := seen[from]; !ok {
			return fmt.Errorf("memory flow references unknown source domain %q", flow.From)
		}
		if _, ok := seen[to]; !ok {
			return fmt.Errorf("memory flow references unknown destination domain %q", flow.To)
		}
		if !containsMemoryDomain(memory.ReadDomains, from) {
			return fmt.Errorf("memory flow source %q is not readable", flow.From)
		}
		if !containsString(memory.WriteDomains, to) {
			return fmt.Errorf("memory flow destination %q is not writable", flow.To)
		}
	}
	return nil
}

// containsMemoryDomain reports whether a memory domain list contains an id.
func containsMemoryDomain(domains []MemoryDomain, target string) bool {
	target = strings.TrimSpace(target)
	for _, domain := range domains {
		if strings.TrimSpace(domain.ID) == target {
			return true
		}
	}
	return false
}

// containsString reports whether values contains target after trimming.
func containsString(values []string, target string) bool {
	target = strings.TrimSpace(target)
	for _, value := range values {
		if strings.TrimSpace(value) == target {
			return true
		}
	}
	return false
}

// validateMCPFilesystemRoots checks filesystem server root path arguments.
func validateMCPFilesystemRoots(server MCPServer, name string) error {
	if !isFilesystemMCPServer(server) {
		return nil
	}
	roots := filesystemRootArgs(server)
	if len(roots) == 0 {
		return fmt.Errorf("mcp filesystem server %q must include at least one absolute root path", name)
	}
	for _, root := range roots {
		if !filepath.IsAbs(root) {
			return fmt.Errorf("mcp filesystem server %q root path %q must be absolute", name, root)
		}
	}
	return nil
}

// isFilesystemMCPServer reports whether a stdio server appears to be the
// filesystem MCP server.
func isFilesystemMCPServer(server MCPServer) bool {
	if strings.Contains(strings.ToLower(server.Command), "filesystem") {
		return true
	}
	for _, arg := range server.Args {
		if strings.Contains(strings.ToLower(arg), "server-filesystem") {
			return true
		}
	}
	return false
}

// filesystemRootArgs extracts filesystem root arguments from server args.
func filesystemRootArgs(server MCPServer) []string {
	roots := make([]string, 0, len(server.Args))
	collect := strings.Contains(strings.ToLower(server.Command), "filesystem")
	for _, arg := range server.Args {
		trimmed := strings.TrimSpace(arg)
		if trimmed == "" {
			continue
		}
		if strings.Contains(strings.ToLower(trimmed), "server-filesystem") {
			collect = true
			continue
		}
		if collect && !strings.HasPrefix(trimmed, "-") {
			roots = append(roots, trimmed)
		}
	}
	return roots
}

// validateUniqueNonEmptyStrings rejects duplicate or empty string lists.
func validateUniqueNonEmptyStrings(label string, values []string) error {
	seen := make(map[string]struct{}, len(values))
	for _, value := range values {
		trimmed := strings.TrimSpace(value)
		if trimmed == "" {
			return fmt.Errorf("%s must not contain empty values", label)
		}
		if _, ok := seen[trimmed]; ok {
			return fmt.Errorf("%s contains duplicate value %q", label, trimmed)
		}
		seen[trimmed] = struct{}{}
	}
	return nil
}
