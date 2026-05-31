// This file defines tool-package validation CLI commands.
package cli

import (
	"context"
	"encoding/json"
	"encoding/xml"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"agentawesome/internal/app"
	"agentawesome/internal/config"
	"agentawesome/internal/config/schema"
	commandservice "agentawesome/internal/services/command/command"
	"agentawesome/internal/services/runbook/actions"
	"agentawesome/internal/services/toolvalidation"
	"agentawesome/internal/tools/mcpclient"
	"agentawesome/internal/tools/openapiimporter"
	"agentawesome/internal/tools/sourcecontrol"
	"github.com/modelcontextprotocol/go-sdk/mcp"
	"github.com/spf13/cobra"
)

// newToolsCommand creates tool package commands.
func newToolsCommand(ctx context.Context) *cobra.Command {
	return newToolsCommandWithValidator(ctx, os.Stdout, runToolValidationSuite)
}

// toolValidationOptions stores CLI options for validating tool packages.
type toolValidationOptions struct {
	ToolPath            string
	ToolDir             string
	ValidationIDs       []string
	Mode                string
	Runtime             app.Options
	JSON                bool
	JUnitPath           string
	RequireCoverage     bool
	RequireInputSchemas bool
	RequireAssertions   bool
}

// toolOpenAPIImportOptions stores OpenAPI import command options.
type toolOpenAPIImportOptions struct {
	SchemaPath string
	OutputPath string
	Name       string
	BaseURL    string
}

// toolInstallOptions stores source-control package installation flags.
type toolInstallOptions struct {
	Source    string
	PackageID string
	ToolRoot  string
	MCPRoot   string
	AppRoot   string
	JSON      bool
}

// toolValidationRunner executes validations for one package path.
type toolValidationRunner func(context.Context, string, []string, string) (toolvalidation.SuiteResult, error)

// toolValidationLibraryResult stores an aggregate run across many packages.
type toolValidationLibraryResult struct {
	TotalPackages       int                           `json:"total_packages"`
	PassedPackages      int                           `json:"passed_packages"`
	FailedPackages      int                           `json:"failed_packages"`
	UnsupportedPackages int                           `json:"unsupported_packages"`
	Total               int                           `json:"total"`
	Passed              int                           `json:"passed"`
	Failed              int                           `json:"failed"`
	Unsupported         int                           `json:"unsupported"`
	CoverageRequired    int                           `json:"coverage_required"`
	CoverageCovered     int                           `json:"coverage_covered"`
	CoverageMissing     int                           `json:"coverage_missing"`
	InputSchemaRequired int                           `json:"input_schema_required"`
	InputSchemaCovered  int                           `json:"input_schema_covered"`
	InputSchemaMissing  int                           `json:"input_schema_missing"`
	MissingAssertions   int                           `json:"missing_assertions"`
	Packages            []toolValidationPackageResult `json:"packages"`
}

// toolValidationPackageResult stores one package validation result.
type toolValidationPackageResult struct {
	Path   string                     `json:"path"`
	Result toolvalidation.SuiteResult `json:"result"`
	Error  string                     `json:"error,omitempty"`
}

// newToolsCommandWithValidator creates tool commands with injectable behavior.
func newToolsCommandWithValidator(
	ctx context.Context,
	stdout io.Writer,
	validator toolValidationRunner,
) *cobra.Command {
	cmd := &cobra.Command{
		Use:   "tools",
		Short: "Validate configured tool packages",
	}
	cmd.AddCommand(newToolsValidateCommand(ctx, stdout, validator))
	cmd.AddCommand(newToolsImportOpenAPICommand(stdout))
	cmd.AddCommand(newToolsInstallCommand(ctx, stdout))
	return cmd
}

// newToolsInstallCommand creates a source-control-backed package installer.
func newToolsInstallCommand(ctx context.Context, stdout io.Writer) *cobra.Command {
	opts := toolInstallOptions{
		ToolRoot: config.DefaultToolConfigDir(),
		MCPRoot:  config.DefaultMCPConfigDir(),
		AppRoot:  config.DefaultAppPluginConfigDir(),
	}
	cmd := &cobra.Command{
		Use:   "install SOURCE",
		Short: "Install a tool or MCP package from source control",
		Args: func(cmd *cobra.Command, args []string) error {
			if len(args) != 1 {
				return fmt.Errorf("install requires exactly one SOURCE")
			}
			opts.Source = args[0]
			return nil
		},
		RunE: func(cmd *cobra.Command, args []string) error {
			result, err := sourcecontrol.Install(ctx, sourcecontrol.Options{
				Source:    opts.Source,
				PackageID: opts.PackageID,
				ToolRoot:  opts.ToolRoot,
				MCPRoot:   opts.MCPRoot,
				AppRoot:   opts.AppRoot,
			})
			if err != nil {
				return err
			}
			if opts.JSON {
				return json.NewEncoder(stdout).Encode(result)
			}
			_, err = fmt.Fprintf(stdout, "installed %s package %q at %s\n", result.Kind, result.PackageID, result.ConfigPath)
			return err
		},
	}
	cmd.Flags().StringVar(&opts.PackageID, "name", opts.PackageID, "installed package directory name")
	cmd.Flags().StringVar(&opts.ToolRoot, "tool-root", opts.ToolRoot, "installed tool package root")
	cmd.Flags().StringVar(&opts.MCPRoot, "mcp-root", opts.MCPRoot, "installed MCP package root")
	cmd.Flags().StringVar(&opts.AppRoot, "app-root", opts.AppRoot, "installed app plugin package root")
	cmd.Flags().BoolVar(&opts.JSON, "json", opts.JSON, "write install result as JSON")
	return cmd
}

// newToolsImportOpenAPICommand creates a REST schema importer command.
func newToolsImportOpenAPICommand(stdout io.Writer) *cobra.Command {
	opts := toolOpenAPIImportOptions{}
	cmd := &cobra.Command{
		Use:   "import-openapi",
		Short: "Generate a command-backed REST API tool package from OpenAPI",
		RunE: func(cmd *cobra.Command, args []string) error {
			if strings.TrimSpace(opts.SchemaPath) == "" {
				return fmt.Errorf("--schema is required")
			}
			content, err := os.ReadFile(opts.SchemaPath)
			if err != nil {
				return fmt.Errorf("read OpenAPI schema: %w", err)
			}
			tools, err := openapiimporter.Import(content, openapiimporter.Options{
				Name:    opts.Name,
				BaseURL: opts.BaseURL,
			})
			if err != nil {
				return err
			}
			if err := tools.Validate(); err != nil {
				return fmt.Errorf("generated tool package is invalid: %w", err)
			}
			encoded, err := openapiimporter.MarshalYAML(tools)
			if err != nil {
				return fmt.Errorf("encode tool package: %w", err)
			}
			if strings.TrimSpace(opts.OutputPath) == "" {
				_, err = stdout.Write(encoded)
				return err
			}
			if err := os.MkdirAll(filepath.Dir(opts.OutputPath), 0o700); err != nil {
				return fmt.Errorf("create output directory: %w", err)
			}
			if err := os.WriteFile(opts.OutputPath, encoded, 0o600); err != nil {
				return fmt.Errorf("write tool package: %w", err)
			}
			_, err = fmt.Fprintf(stdout, "wrote %s\n", opts.OutputPath)
			return err
		},
	}
	cmd.Flags().StringVar(&opts.SchemaPath, "schema", opts.SchemaPath, "OpenAPI schema file path")
	cmd.Flags().StringVar(&opts.OutputPath, "out", opts.OutputPath, "generated tool package output path; stdout when empty")
	cmd.Flags().StringVar(&opts.Name, "name", opts.Name, "override generated tool package name")
	cmd.Flags().StringVar(&opts.BaseURL, "base-url", opts.BaseURL, "override OpenAPI server base URL")
	return cmd
}

// newToolsValidateCommand creates the portable tool validation runner command.
func newToolsValidateCommand(
	ctx context.Context,
	stdout io.Writer,
	validator toolValidationRunner,
) *cobra.Command {
	opts := toolValidationOptions{
		ToolPath: config.DefaultToolPath(),
		Runtime:  defaultAppOptions(),
	}
	cmd := &cobra.Command{
		Use:   "validate",
		Short: "Run portable validations from tool packages",
		RunE: func(cmd *cobra.Command, args []string) error {
			mode, err := normalizeToolValidationMode(opts.Mode)
			if err != nil {
				return err
			}
			opts.Mode = mode
			activeValidator := validator
			if toolValidationRuntimeFlagsChanged(cmd) {
				activeValidator = func(ctx context.Context, path string, validationIDs []string, mode string) (toolvalidation.SuiteResult, error) {
					runtime := opts.Runtime
					runtime.ToolPath = path
					runtime.ToolSet = true
					if !cmd.Flags().Changed("command-data-dir") {
						runtime.CommandDataDir = ""
					}
					return runToolValidationSuiteWithRuntime(ctx, path, validationIDs, mode, runtime)
				}
			}
			if opts.ToolDir != "" {
				if cmd.Flags().Changed("tool") {
					return fmt.Errorf("--tool and --tool-dir cannot be combined")
				}
				var validationErr error
				result, err := runToolValidationDirectory(ctx, opts.ToolDir, opts.ValidationIDs, opts.Mode, activeValidator, opts.RequireAssertions)
				if err != nil {
					var missing toolvalidation.MissingValidationError
					if errors.As(err, &missing) {
						validationErr = err
					} else {
						result = toolValidationLibraryFailureResult(opts.ToolDir, err)
						validationErr = err
					}
				}
				applyToolCoverageFailures(&result, opts.RequireCoverage)
				applyToolInputSchemaFailures(&result, opts.RequireInputSchemas)
				if opts.JSON {
					if err := json.NewEncoder(stdout).Encode(result); err != nil {
						return err
					}
				} else {
					if err := writeToolValidationLibrarySummary(stdout, result); err != nil {
						return err
					}
				}
				if opts.JUnitPath != "" {
					if err := writeJUnitReport(opts.JUnitPath, toolValidationJUnitForLibrary(result, opts.RequireCoverage, opts.RequireInputSchemas)); err != nil {
						return err
					}
				}
				if validationErr != nil {
					return validationErr
				}
				if result.Failed > 0 || result.Unsupported > 0 || result.FailedPackages > 0 || result.UnsupportedPackages > 0 || (opts.RequireCoverage && result.CoverageMissing > 0) || (opts.RequireInputSchemas && result.InputSchemaMissing > 0) || (opts.RequireAssertions && result.MissingAssertions > 0) {
					return fmt.Errorf("tool validations did not pass: failed=%d unsupported=%d failed_packages=%d unsupported_packages=%d coverage_missing=%d input_schema_missing=%d missing_assertions=%d", result.Failed, result.Unsupported, result.FailedPackages, result.UnsupportedPackages, result.CoverageMissing, result.InputSchemaMissing, result.MissingAssertions)
				}
				return nil
			}
			result, err := activeValidator(ctx, opts.ToolPath, opts.ValidationIDs, opts.Mode)
			var validationErr error
			if err != nil {
				result = toolValidationFailureSuite(err)
				validationErr = err
			}
			if opts.RequireAssertions && validationErr == nil {
				markToolValidationMissingAssertions(&result)
			}
			if opts.JSON {
				if err := json.NewEncoder(stdout).Encode(result); err != nil {
					return err
				}
			} else {
				if err := writeToolValidationSummary(stdout, result); err != nil {
					return err
				}
			}
			if opts.JUnitPath != "" {
				if err := writeJUnitReport(opts.JUnitPath, toolValidationJUnitForSuite(opts.ToolPath, result, opts.RequireCoverage, opts.RequireInputSchemas)); err != nil {
					return err
				}
			}
			if validationErr != nil {
				return validationErr
			}
			if result.Failed > 0 || result.Unsupported > 0 || (opts.RequireCoverage && len(result.Coverage.Missing) > 0) || (opts.RequireInputSchemas && len(result.InputSchemaCoverage.Missing) > 0) || (opts.RequireAssertions && len(result.MissingAssertions) > 0) {
				return fmt.Errorf("tool validations did not pass: failed=%d unsupported=%d coverage_missing=%d input_schema_missing=%d missing_assertions=%d", result.Failed, result.Unsupported, len(result.Coverage.Missing), len(result.InputSchemaCoverage.Missing), len(result.MissingAssertions))
			}
			return nil
		},
	}
	cmd.Flags().StringVar(&opts.ToolPath, "tool", opts.ToolPath, "tool config path")
	cmd.Flags().StringVar(&opts.ToolDir, "tool-dir", opts.ToolDir, "tool package directory to validate")
	cmd.Flags().StringArrayVar(&opts.ValidationIDs, "validation", opts.ValidationIDs, "validation ID to run; repeat for multiple IDs")
	cmd.Flags().StringVar(&opts.Mode, "mode", opts.Mode, "validation mode to run: all, mocked, or live")
	cmd.Flags().StringVar(&opts.Runtime.AgentConfigPath, "agent", opts.Runtime.AgentConfigPath, "agent config path for live agent-tool-call validations")
	cmd.Flags().StringVar(&opts.Runtime.ModelConfigPath, "model", opts.Runtime.ModelConfigPath, "model config path for live agent-tool-call validations")
	cmd.Flags().StringVar(&opts.Runtime.ProviderName, "provider", opts.Runtime.ProviderName, "provider name from config for live agent-tool-call validations")
	cmd.Flags().StringVar(&opts.Runtime.ModelID, "model-id", opts.Runtime.ModelID, "model id from provider config for live agent-tool-call validations")
	cmd.Flags().StringVar(&opts.Runtime.CommandDataDir, "command-data-dir", opts.Runtime.CommandDataDir, "command service data directory for live agent-tool-call validations")
	cmd.Flags().StringArrayVar(&opts.Runtime.CommandAllowedWorkdirs, "command-allow-workdir", opts.Runtime.CommandAllowedWorkdirs, "allowed command working directory root for live agent-tool-call validations")
	cmd.Flags().StringArrayVar(&opts.Runtime.CommandAllowedEnv, "command-allow-env", opts.Runtime.CommandAllowedEnv, "allowed process environment variable for live agent-tool-call validations")
	cmd.Flags().StringVar(&opts.Runtime.CommandTemplatesJSON, "command-templates-json", opts.Runtime.CommandTemplatesJSON, "JSON command template list for live agent-tool-call validations")
	cmd.Flags().StringVar(&opts.Runtime.CommandParserDir, "command-parser-dir", opts.Runtime.CommandParserDir, "Starlark command parser directory for live agent-tool-call validations")
	cmd.Flags().DurationVar(&opts.Runtime.CommandDefaultTimeout, "command-timeout", opts.Runtime.CommandDefaultTimeout, "default command timeout for live agent-tool-call validations")
	cmd.Flags().Int64Var(&opts.Runtime.CommandMaxOutputBytes, "command-max-output-bytes", opts.Runtime.CommandMaxOutputBytes, "default command output tail byte limit for live agent-tool-call validations")
	cmd.Flags().BoolVar(&opts.RequireCoverage, "require-coverage", opts.RequireCoverage, "fail when configured operations, agent calls, runbook nodes, or MCP tools lack validations")
	cmd.Flags().BoolVar(&opts.RequireInputSchemas, "require-input-schemas", opts.RequireInputSchemas, "fail when command operations lack input schemas")
	cmd.Flags().BoolVar(&opts.RequireAssertions, "require-assertions", opts.RequireAssertions, "fail when tool validations have no real assertions")
	cmd.Flags().StringVar(&opts.JUnitPath, "junit", opts.JUnitPath, "write JUnit XML validation results to this path")
	cmd.Flags().BoolVar(&opts.JSON, "json", opts.JSON, "write validation results as JSON")
	return cmd
}

// normalizeToolValidationMode validates optional tool validation mode filters.
func normalizeToolValidationMode(value string) (string, error) {
	switch strings.TrimSpace(value) {
	case "", "all":
		return "", nil
	case "mocked":
		return "mocked", nil
	case "live":
		return "live", nil
	default:
		return "", fmt.Errorf("tool validation mode must be all, mocked, or live")
	}
}

// toolValidationFailureSuite stores a setup failure as a validation result.
func toolValidationFailureSuite(err error) toolvalidation.SuiteResult {
	return toolvalidation.SuiteResult{
		Total:  1,
		Failed: 1,
		Results: []toolvalidation.Result{{
			ID:     "package.load",
			Label:  "Package load",
			Status: toolvalidation.StatusFailed,
			Diagnostics: []toolvalidation.Diagnostic{{
				Severity: "error",
				Message:  err.Error(),
			}},
		}},
	}
}

// toolValidationLibraryFailureResult stores a setup failure as an expandable package-load result.
func toolValidationLibraryFailureResult(path string, err error) toolValidationLibraryResult {
	result := toolValidationLibraryResult{
		Packages: []toolValidationPackageResult{},
	}
	addToolValidationPackageResult(&result, toolValidationPackageFailure(path, err))
	return result
}

// toolValidationPackageFailure normalizes package setup errors into validation-row evidence.
func toolValidationPackageFailure(path string, err error) toolValidationPackageResult {
	return toolValidationPackageResult{
		Path:   filepath.Clean(path),
		Result: toolValidationFailureSuite(err),
		Error:  err.Error(),
	}
}

// addToolValidationPackageResult folds one package result into a library summary.
func addToolValidationPackageResult(result *toolValidationLibraryResult, item toolValidationPackageResult) {
	if result == nil {
		return
	}
	result.TotalPackages++
	result.Total += item.Result.Total
	result.Passed += item.Result.Passed
	result.Failed += item.Result.Failed
	result.Unsupported += item.Result.Unsupported
	result.CoverageRequired += item.Result.Coverage.Required
	result.CoverageCovered += item.Result.Coverage.Covered
	result.CoverageMissing += len(item.Result.Coverage.Missing)
	result.InputSchemaRequired += item.Result.InputSchemaCoverage.Required
	result.InputSchemaCovered += item.Result.InputSchemaCoverage.Covered
	result.InputSchemaMissing += len(item.Result.InputSchemaCoverage.Missing)
	result.MissingAssertions += len(item.Result.MissingAssertions)

	switch {
	case item.Error != "" || item.Result.Failed > 0:
		result.FailedPackages++
	case item.Result.Unsupported > 0:
		result.UnsupportedPackages++
	default:
		result.PassedPackages++
	}

	result.Packages = append(result.Packages, item)
}

// toolValidationRuntimeFlagsChanged reports whether caller supplied live-agent runtime options.
func toolValidationRuntimeFlagsChanged(cmd *cobra.Command) bool {
	for _, name := range []string{
		"agent",
		"model",
		"provider",
		"model-id",
		"command-data-dir",
		"command-allow-workdir",
		"command-allow-env",
		"command-templates-json",
		"command-parser-dir",
		"command-timeout",
		"command-max-output-bytes",
	} {
		if cmd.Flags().Changed(name) {
			return true
		}
	}
	return false
}

// runToolValidationSuite loads one tool package and runs its validations.
func runToolValidationSuite(ctx context.Context, toolPath string, validationIDs []string, mode string) (toolvalidation.SuiteResult, error) {
	runtime := defaultAppOptions()
	runtime.ToolPath = toolPath
	runtime.ToolSet = true
	runtime.CommandDataDir = ""
	return runToolValidationSuiteWithRuntime(ctx, toolPath, validationIDs, mode, runtime)
}

// runToolValidationSuiteWithRuntime runs validations with optional live agent support.
func runToolValidationSuiteWithRuntime(
	ctx context.Context,
	toolPath string,
	validationIDs []string,
	mode string,
	runtime app.Options,
) (toolvalidation.SuiteResult, error) {
	tools, err := config.LoadToolPackage(toolPath)
	if err != nil {
		return toolvalidation.SuiteResult{}, err
	}
	commandService, cleanup, err := openToolValidationCommandService(tools)
	if err != nil {
		return toolvalidation.SuiteResult{}, err
	}
	defer cleanup()
	needsAgentHost := toolValidationsNeedLiveAgentHost(*tools, validationIDs, mode)
	needsMCPHost := toolValidationsNeedLiveMCPHost(*tools, validationIDs, mode)
	if !needsAgentHost && !needsMCPHost {
		return toolvalidation.NewRunner(commandService).RunSelectedModes(ctx, *tools, validationIDs, mode)
	}
	var agent schema.Agent
	var host *app.AgentValidationHost
	if needsAgentHost {
		agent, err = config.LoadAgent(runtime.AgentConfigPath)
		if err != nil {
			return toolvalidation.SuiteResult{}, err
		}
		runtime.ToolPath = toolPath
		runtime.ToolSet = true
		runtime, runtimeCleanup, err := isolateToolValidationRuntime(runtime)
		if err != nil {
			return toolvalidation.SuiteResult{}, err
		}
		defer runtimeCleanup()
		host, err = app.NewAgentValidationHost(ctx, runtime)
		if err != nil {
			return toolvalidation.SuiteResult{}, err
		}
		defer func() { _ = host.Close() }()
	}
	var mcpHost toolvalidation.MCPExecutor
	if needsMCPHost {
		mcpHost = toolValidationMCPExecutor{tools: *tools}
	}
	return toolvalidation.NewRunnerWithBoundaries(commandService, mcpHost, agent, host).RunSelectedModes(ctx, *tools, validationIDs, mode)
}

// toolValidationsNeedLiveAgentHost reports whether selected cases call agents live.
func toolValidationsNeedLiveAgentHost(tools schema.Tools, validationIDs []string, mode string) bool {
	ids := map[string]bool{}
	for _, id := range validationIDs {
		if trimmed := strings.TrimSpace(id); trimmed != "" {
			ids[trimmed] = true
		}
	}
	for _, validation := range tools.Validations {
		if len(ids) > 0 && !ids[strings.TrimSpace(validation.ID)] {
			continue
		}
		if !toolValidationMatchesMode(validation.Mode, mode) {
			continue
		}
		if strings.TrimSpace(validation.Mode) == "live" &&
			strings.TrimSpace(validation.Target.Type) == "agent-tool-call" {
			return true
		}
	}
	return false
}

// toolValidationsNeedLiveMCPHost reports whether selected cases call MCP live.
func toolValidationsNeedLiveMCPHost(tools schema.Tools, validationIDs []string, mode string) bool {
	ids := map[string]bool{}
	for _, id := range validationIDs {
		if trimmed := strings.TrimSpace(id); trimmed != "" {
			ids[trimmed] = true
		}
	}
	for _, validation := range tools.Validations {
		if len(ids) > 0 && !ids[strings.TrimSpace(validation.ID)] {
			continue
		}
		if !toolValidationMatchesMode(validation.Mode, mode) {
			continue
		}
		if strings.TrimSpace(validation.Mode) != "live" {
			continue
		}
		target := validation.Target
		if strings.TrimSpace(target.Type) == "mcp-tool" {
			return true
		}
		if strings.TrimSpace(target.Type) == "runbook-node" &&
			(strings.TrimSpace(target.MCPServer) != "" || strings.TrimSpace(target.MCPTool) != "") {
			return true
		}
		if strings.TrimSpace(target.Type) == "runbook-node" &&
			toolValidationPresetUsesMCP(tools.NodePresets, target.PresetID) {
			return true
		}
	}
	return false
}

// toolValidationMatchesMode reports whether a validation belongs to a CLI mode.
func toolValidationMatchesMode(value string, mode string) bool {
	filter := ""
	switch strings.TrimSpace(mode) {
	case "mocked":
		filter = "mocked"
	case "live":
		filter = "live"
	}
	if filter == "" {
		return true
	}
	if strings.TrimSpace(value) == "live" {
		return filter == "live"
	}
	return filter == "mocked"
}

// toolValidationPresetUsesMCP reports whether one node preset uses mcp.call.
func toolValidationPresetUsesMCP(presets []schema.NodePreset, presetID string) bool {
	for _, preset := range presets {
		if strings.TrimSpace(preset.ID) == strings.TrimSpace(presetID) {
			return strings.TrimSpace(preset.Action) == "mcp.call"
		}
	}
	return false
}

// toolValidationMCPExecutor calls configured MCP tools for live package tests.
type toolValidationMCPExecutor struct {
	tools schema.Tools
}

// CallMCP invokes one configured MCP tool and returns assertion-friendly output.
func (e toolValidationMCPExecutor) CallMCP(ctx context.Context, req actions.MCPRequest) (map[string]any, error) {
	server, err := e.server(req)
	if err != nil {
		return nil, err
	}
	session, err := mcpclient.Connect(ctx, server, "agent-awesome-tool-validation", "dev")
	if err != nil {
		return nil, err
	}
	defer session.Close()
	result, err := session.CallTool(ctx, &mcp.CallToolParams{
		Name:      strings.TrimSpace(req.Tool),
		Arguments: req.Arguments,
	})
	if err != nil {
		return nil, err
	}
	output := mcpToolValidationOutput(result)
	if result != nil && result.IsError {
		return output, fmt.Errorf("MCP tool %s failed: %s", strings.TrimSpace(req.Tool), stringFromMap(output, "text"))
	}
	return output, nil
}

// server resolves the configured server or endpoint for one MCP request.
func (e toolValidationMCPExecutor) server(req actions.MCPRequest) (schema.MCPServer, error) {
	serverID := strings.TrimSpace(req.ServerID)
	if serverID != "" {
		for _, server := range e.tools.MCP.Servers {
			if strings.TrimSpace(server.Name) == serverID {
				return server, nil
			}
		}
		return schema.MCPServer{}, fmt.Errorf("mcp.call server %q is not configured", serverID)
	}
	if endpoint := strings.TrimSpace(req.Endpoint); endpoint != "" {
		return schema.MCPServer{Transport: "streamable-http", Endpoint: endpoint}, nil
	}
	return schema.MCPServer{}, fmt.Errorf("mcp.call server or endpoint is required")
}

// mcpToolValidationOutput converts SDK MCP results into stable validation data.
func mcpToolValidationOutput(result *mcp.CallToolResult) map[string]any {
	if result == nil {
		return map[string]any{}
	}
	output := map[string]any{}
	if structured, ok := normalizeMCPValue(result.StructuredContent).(map[string]any); ok {
		for key, value := range structured {
			output[key] = value
		}
	} else if result.StructuredContent != nil {
		output["structuredContent"] = normalizeMCPValue(result.StructuredContent)
	}
	content := mcpContentList(result.Content)
	if len(content) > 0 {
		output["content"] = content
	}
	if text := mcpTextContent(result.Content); text != "" {
		output["text"] = text
	}
	output["is_error"] = result.IsError
	return output
}

// mcpContentList normalizes MCP content blocks into JSON-like maps.
func mcpContentList(content []mcp.Content) []any {
	items := make([]any, 0, len(content))
	for _, item := range content {
		if item == nil {
			continue
		}
		data, err := item.MarshalJSON()
		if err != nil {
			continue
		}
		var decoded any
		if err := json.Unmarshal(data, &decoded); err != nil {
			continue
		}
		items = append(items, normalizeMCPValue(decoded))
	}
	return items
}

// mcpTextContent concatenates text blocks from MCP content.
func mcpTextContent(content []mcp.Content) string {
	var out strings.Builder
	for _, item := range content {
		text, ok := item.(*mcp.TextContent)
		if !ok {
			continue
		}
		out.WriteString(text.Text)
	}
	return strings.TrimSpace(out.String())
}

// normalizeMCPValue converts SDK/YAML map values to JSON-like maps.
func normalizeMCPValue(value any) any {
	switch typed := value.(type) {
	case map[string]any:
		out := make(map[string]any, len(typed))
		for key, item := range typed {
			out[key] = normalizeMCPValue(item)
		}
		return out
	case map[any]any:
		out := make(map[string]any, len(typed))
		for key, item := range typed {
			out[fmt.Sprint(key)] = normalizeMCPValue(item)
		}
		return out
	case []any:
		out := make([]any, len(typed))
		for index, item := range typed {
			out[index] = normalizeMCPValue(item)
		}
		return out
	default:
		return value
	}
}

// stringFromMap reads one trimmed string field.
func stringFromMap(values map[string]any, key string) string {
	value, _ := values[key].(string)
	return strings.TrimSpace(value)
}

// isolateToolValidationRuntime keeps live agent validation runtime state disposable.
func isolateToolValidationRuntime(runtime app.Options) (app.Options, func(), error) {
	if strings.TrimSpace(runtime.CommandDataDir) != "" {
		return runtime, func() {}, nil
	}
	dataDir, err := os.MkdirTemp("", "agent-awesome-agent-tool-validation-*")
	if err != nil {
		return app.Options{}, nil, fmt.Errorf("create live agent-tool validation data dir: %w", err)
	}
	runtime.CommandDataDir = dataDir
	return runtime, func() { _ = os.RemoveAll(dataDir) }, nil
}

// openToolValidationCommandService opens an isolated command service for live tests.
func openToolValidationCommandService(tools *schema.Tools) (*commandservice.Service, func(), error) {
	if tools == nil || !tools.LocalExec.Enabled {
		return nil, func() {}, nil
	}
	dataDir, err := os.MkdirTemp("", "agent-awesome-command-validation-*")
	if err != nil {
		return nil, nil, fmt.Errorf("create command validation data dir: %w", err)
	}
	cleanup := func() {
		_ = os.RemoveAll(dataDir)
	}
	service, err := app.OpenCommandServiceForTools(app.Options{
		CommandDataDir:         dataDir,
		CommandAllowedWorkdirs: []string{".", os.TempDir()},
		CommandAllowedEnv:      []string{"PATH", "HOME", "USER", "TMPDIR"},
		CommandParserDir:       config.DefaultCommandParserDir(),
	}, tools)
	if err != nil {
		cleanup()
		return nil, nil, err
	}
	return service, func() {
		if service != nil {
			service.Close()
		}
		cleanup()
	}, nil
}

// runToolValidationDirectory validates every package in one tool library directory.
func runToolValidationDirectory(
	ctx context.Context,
	toolDir string,
	validationIDs []string,
	mode string,
	validator toolValidationRunner,
	requireAssertions bool,
) (toolValidationLibraryResult, error) {
	paths, err := toolPackageConfigPaths(toolDir)
	if err != nil {
		return toolValidationLibraryResult{}, err
	}
	return runToolValidationPackagePaths(ctx, toolDir, paths, validationIDs, mode, validator, requireAssertions)
}

// runMCPValidationDirectory validates every MCP package in one library directory.
func runMCPValidationDirectory(
	ctx context.Context,
	mcpDir string,
	validationIDs []string,
	mode string,
	validator toolValidationRunner,
	requireAssertions bool,
) (toolValidationLibraryResult, error) {
	paths, err := mcpPackageConfigPaths(mcpDir)
	if err != nil {
		return toolValidationLibraryResult{}, err
	}
	return runToolValidationPackagePaths(ctx, mcpDir, paths, validationIDs, mode, validator, requireAssertions)
}

// runToolValidationPackagePaths validates a stable list of tool-shaped packages.
func runToolValidationPackagePaths(
	ctx context.Context,
	sourcePath string,
	paths []string,
	validationIDs []string,
	mode string,
	validator toolValidationRunner,
	requireAssertions bool,
) (toolValidationLibraryResult, error) {
	result := toolValidationLibraryResult{
		Packages: make([]toolValidationPackageResult, 0, len(paths)),
	}
	found := map[string]bool{}
	for _, path := range paths {
		suite, err := validator(ctx, path, validationIDs, mode)
		var missing toolvalidation.MissingValidationError
		if len(validationIDs) > 0 && errors.As(err, &missing) && suite.Total == 0 {
			continue
		}
		if err != nil {
			if !(len(validationIDs) > 0 && errors.As(err, &missing)) {
				addToolValidationPackageResult(&result, toolValidationPackageFailure(path, err))
				continue
			}
		}
		if requireAssertions {
			markToolValidationMissingAssertions(&suite)
		}
		for _, validation := range suite.Results {
			found[validation.ID] = true
		}
		addToolValidationPackageResult(&result, toolValidationPackageResult{
			Path:   filepath.Clean(path),
			Result: suite,
		})
	}
	missingIDs := missingSelectedValidationIDs(validationIDs, found)
	if len(missingIDs) > 0 {
		err := toolvalidation.MissingValidationError{IDs: missingIDs}
		addToolValidationPackageResult(&result, toolValidationPackageFailure(sourcePath, err))
		return result, err
	}
	return result, nil
}

// markToolValidationMissingAssertions fails validations that do not prove behavior.
func markToolValidationMissingAssertions(suite *toolvalidation.SuiteResult) []string {
	if suite == nil || len(suite.Results) == 0 {
		return nil
	}
	missing := make([]string, 0)
	for index := range suite.Results {
		if toolValidationHasRealAssertion(suite.Results[index]) {
			continue
		}
		name := firstNonEmptyAgentValidationValue(suite.Results[index].ID, suite.Results[index].Label, "validation")
		missing = append(missing, name)
		suite.Results[index].Assertions = append(suite.Results[index].Assertions, toolvalidation.AssertionResult{
			Type:    "required-assertion",
			Passed:  false,
			Message: "tool validation has no real assertions",
		})
		if suite.Results[index].Status == toolvalidation.StatusPassed {
			suite.Results[index].Status = toolvalidation.StatusFailed
		}
	}
	if len(missing) == 0 {
		return nil
	}
	suite.MissingAssertions = mergeToolMissingAssertions(suite.MissingAssertions, missing)
	recountToolValidationSuite(suite)
	return missing
}

// toolValidationHasRealAssertion reports whether a result contains a behavior check.
func toolValidationHasRealAssertion(result toolvalidation.Result) bool {
	for _, assertion := range result.Assertions {
		assertionType := strings.TrimSpace(assertion.Type)
		if assertionType == "" || assertionType == "configured" || assertionType == "required-assertion" {
			continue
		}
		return true
	}
	return false
}

// mergeToolMissingAssertions appends unique missing-assertion validation names.
func mergeToolMissingAssertions(existing []string, next []string) []string {
	seen := map[string]struct{}{}
	for _, value := range existing {
		if trimmed := strings.TrimSpace(value); trimmed != "" {
			seen[trimmed] = struct{}{}
		}
	}
	for _, value := range next {
		trimmed := strings.TrimSpace(value)
		if trimmed == "" {
			continue
		}
		if _, ok := seen[trimmed]; ok {
			continue
		}
		seen[trimmed] = struct{}{}
		existing = append(existing, trimmed)
	}
	return existing
}

// recountToolValidationSuite recomputes package counters after strict gates.
func recountToolValidationSuite(suite *toolvalidation.SuiteResult) {
	if suite == nil {
		return
	}
	suite.Total = len(suite.Results)
	suite.Passed = 0
	suite.Failed = 0
	suite.Unsupported = 0
	for _, result := range suite.Results {
		switch result.Status {
		case toolvalidation.StatusPassed:
			suite.Passed++
		case toolvalidation.StatusUnsupported:
			suite.Unsupported++
		default:
			suite.Failed++
		}
	}
}

// missingSelectedValidationIDs returns requested validations absent from a library run.
func missingSelectedValidationIDs(validationIDs []string, found map[string]bool) []string {
	missing := make([]string, 0, len(validationIDs))
	seen := map[string]bool{}
	for _, value := range validationIDs {
		id := strings.TrimSpace(value)
		if id == "" || seen[id] {
			continue
		}
		seen[id] = true
		if !found[id] {
			missing = append(missing, id)
		}
	}
	return missing
}

// toolPackageConfigPaths finds package config files inside a library directory.
func toolPackageConfigPaths(toolDir string) ([]string, error) {
	if toolDir == "" {
		return nil, fmt.Errorf("tool package directory is required")
	}
	return packageConfigPaths(toolDir, schema.DefaultToolFilename)
}

// mcpPackageConfigPaths finds MCP package config files inside a library directory.
func mcpPackageConfigPaths(mcpDir string) ([]string, error) {
	if mcpDir == "" {
		return nil, fmt.Errorf("MCP package directory is required")
	}
	return packageConfigPaths(mcpDir, schema.DefaultMCPFilename)
}

// packageConfigPaths finds package config files inside a library directory.
func packageConfigPaths(directory string, filename string) ([]string, error) {
	var paths []string
	root := filepath.Clean(directory)
	err := filepath.WalkDir(root, func(path string, entry os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if entry.IsDir() {
			if path != root && ignoredConfigLibraryDir(entry.Name()) {
				return filepath.SkipDir
			}
			return nil
		}
		if entry.Name() == filename {
			paths = append(paths, path)
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	sort.Strings(paths)
	if len(paths) == 0 {
		return nil, fmt.Errorf("no %s files found under %s", filename, directory)
	}
	return paths, nil
}

// ignoredConfigLibraryDir reports whether discovery should skip one subtree.
func ignoredConfigLibraryDir(name string) bool {
	if strings.HasPrefix(name, ".") {
		return true
	}
	switch name {
	case "build", "logs", "node_modules":
		return true
	default:
		return false
	}
}

// writeToolValidationSummary writes a compact human-readable validation report.
func writeToolValidationSummary(stdout io.Writer, result toolvalidation.SuiteResult) error {
	if _, err := fmt.Fprintf(
		stdout,
		"Tool validations: total=%d passed=%d failed=%d unsupported=%d coverage=%d/%d missing=%d input_schemas=%d/%d missing=%d assertions_missing=%d\n",
		result.Total,
		result.Passed,
		result.Failed,
		result.Unsupported,
		result.Coverage.Covered,
		result.Coverage.Required,
		len(result.Coverage.Missing),
		result.InputSchemaCoverage.Covered,
		result.InputSchemaCoverage.Required,
		len(result.InputSchemaCoverage.Missing),
		len(result.MissingAssertions),
	); err != nil {
		return err
	}
	if err := writeToolValidationAgentCallSummary(stdout, "", result.AgentToolCalls); err != nil {
		return err
	}
	for _, item := range result.Results {
		if _, err := fmt.Fprintf(stdout, "%s %s", item.Status, item.ID); err != nil {
			return err
		}
		if item.Label != "" {
			if _, err := fmt.Fprintf(stdout, " - %s", item.Label); err != nil {
				return err
			}
		}
		if _, err := fmt.Fprintln(stdout); err != nil {
			return err
		}
	}
	for _, missing := range result.Coverage.Missing {
		if _, err := fmt.Fprintf(stdout, "missing coverage %s %s\n", missing.Type, missing.ID); err != nil {
			return err
		}
	}
	for _, missing := range result.InputSchemaCoverage.Missing {
		if _, err := fmt.Fprintf(stdout, "missing input schema %s\n", missing.ID); err != nil {
			return err
		}
	}
	if len(result.MissingAssertions) > 0 {
		if _, err := fmt.Fprintf(stdout, "tool validations without assertions: %s\n", strings.Join(result.MissingAssertions, ", ")); err != nil {
			return err
		}
	}
	return nil
}

// writeToolValidationLibrarySummary writes a compact report for a tool library.
func writeToolValidationLibrarySummary(stdout io.Writer, result toolValidationLibraryResult) error {
	if _, err := fmt.Fprintf(
		stdout,
		"Tool library validations: packages=%d passed=%d failed=%d unsupported=%d total=%d passed=%d failed=%d unsupported=%d coverage=%d/%d missing=%d input_schemas=%d/%d missing=%d assertions_missing=%d\n",
		result.TotalPackages,
		result.PassedPackages,
		result.FailedPackages,
		result.UnsupportedPackages,
		result.Total,
		result.Passed,
		result.Failed,
		result.Unsupported,
		result.CoverageCovered,
		result.CoverageRequired,
		result.CoverageMissing,
		result.InputSchemaCovered,
		result.InputSchemaRequired,
		result.InputSchemaMissing,
		result.MissingAssertions,
	); err != nil {
		return err
	}
	for _, item := range result.Packages {
		if err := writeToolValidationLibraryPackageSummary(stdout, item); err != nil {
			return err
		}
	}
	return nil
}

// writeToolValidationLibraryPackageSummary writes one package block.
func writeToolValidationLibraryPackageSummary(stdout io.Writer, item toolValidationPackageResult) error {
	if item.Error != "" {
		if _, err := fmt.Fprintf(stdout, "failed %s - %s\n", item.Path, item.Error); err != nil {
			return err
		}
		return nil
	}
	if _, err := fmt.Fprintf(
		stdout,
		"package %s: total=%d passed=%d failed=%d unsupported=%d\n",
		item.Path,
		item.Result.Total,
		item.Result.Passed,
		item.Result.Failed,
		item.Result.Unsupported,
	); err != nil {
		return err
	}
	if err := writeToolValidationAgentCallSummary(stdout, "  ", item.Result.AgentToolCalls); err != nil {
		return err
	}
	for _, validation := range item.Result.Results {
		if _, err := fmt.Fprintf(stdout, "  %s %s", validation.Status, validation.ID); err != nil {
			return err
		}
		if validation.Label != "" {
			if _, err := fmt.Fprintf(stdout, " - %s", validation.Label); err != nil {
				return err
			}
		}
		if _, err := fmt.Fprintln(stdout); err != nil {
			return err
		}
	}
	for _, missing := range item.Result.Coverage.Missing {
		if _, err := fmt.Fprintf(stdout, "  missing coverage %s %s\n", missing.Type, missing.ID); err != nil {
			return err
		}
	}
	for _, missing := range item.Result.InputSchemaCoverage.Missing {
		if _, err := fmt.Fprintf(stdout, "  missing input schema %s\n", missing.ID); err != nil {
			return err
		}
	}
	if len(item.Result.MissingAssertions) > 0 {
		if _, err := fmt.Fprintf(stdout, "  tool validations without assertions: %s\n", strings.Join(item.Result.MissingAssertions, ", ")); err != nil {
			return err
		}
	}
	return nil
}

// writeToolValidationAgentCallSummary writes model-visible tool-call ids.
func writeToolValidationAgentCallSummary(stdout io.Writer, indent string, ids []string) error {
	if len(ids) == 0 {
		return nil
	}
	if _, err := fmt.Fprintf(stdout, "%sagent tool calls: %s\n", indent, strings.Join(ids, ", ")); err != nil {
		return err
	}
	return nil
}

// junitSuites stores CI-friendly JUnit XML output.
type junitSuites struct {
	XMLName  xml.Name     `xml:"testsuites"`
	Name     string       `xml:"name,attr,omitempty"`
	Tests    int          `xml:"tests,attr"`
	Failures int          `xml:"failures,attr"`
	Skipped  int          `xml:"skipped,attr"`
	Suites   []junitSuite `xml:"testsuite"`
}

// junitSuite stores one package report.
type junitSuite struct {
	Name      string      `xml:"name,attr"`
	Tests     int         `xml:"tests,attr"`
	Failures  int         `xml:"failures,attr"`
	Skipped   int         `xml:"skipped,attr"`
	TestCases []junitCase `xml:"testcase"`
}

// junitCase stores one validation, coverage, or package load result.
type junitCase struct {
	Name      string        `xml:"name,attr"`
	ClassName string        `xml:"classname,attr,omitempty"`
	Failure   *junitFailure `xml:"failure,omitempty"`
	Skipped   *junitSkipped `xml:"skipped,omitempty"`
}

// junitFailure stores one failing validation message.
type junitFailure struct {
	Message string `xml:"message,attr,omitempty"`
	Text    string `xml:",chardata"`
}

// junitSkipped stores one skipped or unsupported validation.
type junitSkipped struct {
	Message string `xml:"message,attr,omitempty"`
	Text    string `xml:",chardata"`
}

// toolValidationJUnitForSuite converts one package validation result to JUnit XML.
func toolValidationJUnitForSuite(
	path string,
	result toolvalidation.SuiteResult,
	requireCoverage bool,
	requireInputSchemas bool,
) junitSuites {
	suite := junitSuiteForPackage(toolValidationPackageResult{Path: path, Result: result}, requireCoverage, requireInputSchemas)
	return finalizeJUnit(junitSuites{
		Name:   "tool-validations",
		Suites: []junitSuite{suite},
	})
}

// toolValidationJUnitForLibrary converts a library validation result to JUnit XML.
func toolValidationJUnitForLibrary(
	result toolValidationLibraryResult,
	requireCoverage bool,
	requireInputSchemas bool,
) junitSuites {
	report := junitSuites{
		Name:   "tool-library-validations",
		Suites: make([]junitSuite, 0, len(result.Packages)),
	}
	for _, item := range result.Packages {
		report.Suites = append(report.Suites, junitSuiteForPackage(item, requireCoverage, requireInputSchemas))
	}
	return finalizeJUnit(report)
}

// junitSuiteForPackage converts one package result to a test suite.
func junitSuiteForPackage(
	item toolValidationPackageResult,
	requireCoverage bool,
	requireInputSchemas bool,
) junitSuite {
	suite := junitSuite{Name: strings.TrimSpace(item.Path)}
	if suite.Name == "" {
		suite.Name = "tool-package"
	}
	if item.Error != "" && len(item.Result.Results) == 0 {
		suite.TestCases = append(suite.TestCases, junitCase{
			Name:      "package.load",
			ClassName: suite.Name,
			Failure: &junitFailure{
				Message: "package validation failed",
				Text:    item.Error,
			},
		})
		return finalizeJUnitSuite(suite)
	}
	for _, result := range item.Result.Results {
		suite.TestCases = append(suite.TestCases, junitCaseForResult(suite.Name, result))
	}
	for _, missing := range item.Result.Coverage.Missing {
		suite.TestCases = append(suite.TestCases, junitCaseForCoverage(suite.Name, missing, requireCoverage))
	}
	for _, missing := range item.Result.InputSchemaCoverage.Missing {
		suite.TestCases = append(suite.TestCases, junitCaseForInputSchema(suite.Name, missing, requireInputSchemas))
	}
	return finalizeJUnitSuite(suite)
}

// junitCaseForResult converts one validation result to a test case.
func junitCaseForResult(className string, result toolvalidation.Result) junitCase {
	name := strings.TrimSpace(result.ID)
	if name == "" {
		name = strings.TrimSpace(result.Label)
	}
	if name == "" {
		name = "validation"
	}
	item := junitCase{Name: name, ClassName: className}
	switch result.Status {
	case toolvalidation.StatusPassed:
		return item
	case toolvalidation.StatusUnsupported:
		item.Skipped = &junitSkipped{
			Message: "validation unsupported",
			Text:    toolValidationJUnitResultMessage(result),
		}
	default:
		item.Failure = &junitFailure{
			Message: "validation failed",
			Text:    toolValidationJUnitResultMessage(result),
		}
	}
	return item
}

// junitCaseForCoverage converts one missing target to a test case.
func junitCaseForCoverage(className string, missing toolvalidation.CoverageItem, requireCoverage bool) junitCase {
	name := "coverage." + strings.TrimSpace(missing.Type) + "." + strings.TrimSpace(missing.ID)
	text := fmt.Sprintf("missing coverage for %s %s", missing.Type, missing.ID)
	item := junitCase{Name: name, ClassName: className}
	if requireCoverage {
		item.Failure = &junitFailure{Message: "missing validation coverage", Text: text}
	} else {
		item.Skipped = &junitSkipped{Message: "missing validation coverage", Text: text}
	}
	return item
}

// junitCaseForInputSchema converts one missing input schema to a test case.
func junitCaseForInputSchema(className string, missing toolvalidation.CoverageItem, requireInputSchemas bool) junitCase {
	name := "input-schema." + strings.TrimSpace(missing.ID)
	text := fmt.Sprintf("missing input schema for %s", missing.ID)
	item := junitCase{Name: name, ClassName: className}
	if requireInputSchemas {
		item.Failure = &junitFailure{Message: "missing input schema", Text: text}
	} else {
		item.Skipped = &junitSkipped{Message: "missing input schema", Text: text}
	}
	return item
}

// toolValidationJUnitResultMessage returns diagnostics and assertion details.
func toolValidationJUnitResultMessage(result toolvalidation.Result) string {
	var parts []string
	for _, diagnostic := range result.Diagnostics {
		parts = append(parts, strings.TrimSpace(diagnostic.Severity)+": "+strings.TrimSpace(diagnostic.Message))
	}
	for _, assertion := range result.Assertions {
		if assertion.Passed {
			continue
		}
		parts = append(parts, fmt.Sprintf(
			"assertion %s path=%s expected=%v actual=%v message=%s",
			assertion.Type,
			assertion.Path,
			assertion.Expected,
			assertion.Actual,
			assertion.Message,
		))
	}
	if len(parts) == 0 {
		parts = append(parts, "status: "+strings.TrimSpace(result.Status))
	}
	return strings.Join(parts, "\n")
}

// finalizeJUnit updates aggregate report counters.
func finalizeJUnit(report junitSuites) junitSuites {
	for index := range report.Suites {
		report.Suites[index] = finalizeJUnitSuite(report.Suites[index])
		report.Tests += report.Suites[index].Tests
		report.Failures += report.Suites[index].Failures
		report.Skipped += report.Suites[index].Skipped
	}
	return report
}

// finalizeJUnitSuite updates one suite's counters.
func finalizeJUnitSuite(suite junitSuite) junitSuite {
	suite.Tests = len(suite.TestCases)
	suite.Failures = 0
	suite.Skipped = 0
	for _, item := range suite.TestCases {
		if item.Failure != nil {
			suite.Failures++
		}
		if item.Skipped != nil {
			suite.Skipped++
		}
	}
	return suite
}

// writeJUnitReport writes one JUnit XML report to disk.
func writeJUnitReport(path string, report junitSuites) error {
	if strings.TrimSpace(path) == "" {
		return nil
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return fmt.Errorf("create junit report directory: %w", err)
	}
	encoded, err := xml.MarshalIndent(report, "", "  ")
	if err != nil {
		return fmt.Errorf("encode junit report: %w", err)
	}
	data := append([]byte(xml.Header), encoded...)
	data = append(data, '\n')
	if err := os.WriteFile(path, data, 0o600); err != nil {
		return fmt.Errorf("write junit report: %w", err)
	}
	return nil
}
