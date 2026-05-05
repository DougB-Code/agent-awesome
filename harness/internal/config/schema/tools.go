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
	return validateMCP(c.MCP)
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
	if c.RequireConfirmation != nil && !*c.RequireConfirmation {
		return fmt.Errorf("local-exec require-confirmation must be true")
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
	for _, dir := range c.AllowedWorkdirs {
		if strings.TrimSpace(dir) == "" {
			return fmt.Errorf("local-exec allowed-workdirs must not contain empty paths")
		}
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
	if err := validateLocalExecCommandTimeout(name, command.Timeout); err != nil {
		return err
	}
	if command.MaxOutputBytes < 0 {
		return fmt.Errorf("local-exec command %q max-output-bytes must not be negative", name)
	}
	for _, prefix := range command.Approval.AlwaysAllowCommandPrefixes {
		if strings.TrimSpace(prefix) == "" {
			return fmt.Errorf("local-exec command %q approval always-allow-command-starts-with must not contain empty prefixes", name)
		}
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
