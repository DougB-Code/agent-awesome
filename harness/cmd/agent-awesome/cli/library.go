// This file defines shared package-library validation CLI commands.
package cli

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"agentawesome/internal/app"
	"agentawesome/internal/config"
	"agentawesome/internal/services/agentvalidation"
	commandservice "agentawesome/internal/services/command/command"
	"agentawesome/internal/services/toolvalidation"
	"github.com/spf13/cobra"
)

// libraryValidationOptions stores CLI options for validating package libraries.
type libraryValidationOptions struct {
	Root                      string
	AgentPath                 string
	AgentDir                  string
	ToolPath                  string
	ToolDir                   string
	MCPDir                    string
	AgentMode                 string
	ToolMode                  string
	LiveAgents                bool
	Runtime                   app.Options
	RuntimeAgentPath          string
	RuntimeToolPath           string
	JSON                      bool
	JUnitPath                 string
	RequireAgentValidations   bool
	RequireAgentAssertions    bool
	RequireAgentToolCalls     bool
	RequireToolCoverage       bool
	RequireToolInputSchemas   bool
	RequireToolAssertions     bool
	RequireAgentToolContracts bool
}

// libraryValidationResult stores aggregate validation results for one package library.
type libraryValidationResult struct {
	Root        string                       `json:"root"`
	AgentPath   string                       `json:"agent_path,omitempty"`
	AgentDir    string                       `json:"agent_dir,omitempty"`
	ToolPath    string                       `json:"tool_path,omitempty"`
	ToolDir     string                       `json:"tool_dir,omitempty"`
	MCPDir      string                       `json:"mcp_dir,omitempty"`
	Error       string                       `json:"error,omitempty"`
	Total       int                          `json:"total"`
	Passed      int                          `json:"passed"`
	Failed      int                          `json:"failed"`
	Unsupported int                          `json:"unsupported"`
	Agents      *agentValidationResult       `json:"agents,omitempty"`
	Tools       *toolValidationLibraryResult `json:"tools,omitempty"`
}

// libraryAgentValidationRunnerFactory creates the runner for agent library checks.
type libraryAgentValidationRunnerFactory func(context.Context, libraryValidationOptions) (*agentvalidation.Runner, func(), error)

// newLibraryCommand creates package-library validation commands.
func newLibraryCommand(ctx context.Context) *cobra.Command {
	return newLibraryCommandWithValidators(ctx, os.Stdout, config.LoadAgent, runToolValidationSuite)
}

// newLibraryCommandWithValidators creates package-library commands with injectable behavior.
func newLibraryCommandWithValidators(
	ctx context.Context,
	stdout io.Writer,
	agentLoader agentValidationLoader,
	toolValidator toolValidationRunner,
) *cobra.Command {
	return newLibraryCommandWithValidatorsAndAgentRunner(
		ctx,
		stdout,
		agentLoader,
		toolValidator,
		defaultLibraryAgentValidationRunner,
	)
}

// newLibraryCommandWithValidatorsAndAgentRunner creates library commands with injectable agent validation behavior.
func newLibraryCommandWithValidatorsAndAgentRunner(
	ctx context.Context,
	stdout io.Writer,
	agentLoader agentValidationLoader,
	toolValidator toolValidationRunner,
	agentRunnerFactory libraryAgentValidationRunnerFactory,
) *cobra.Command {
	cmd := &cobra.Command{
		Use:   "library",
		Short: "Validate shared agent and tool package libraries",
	}
	cmd.AddCommand(newLibraryValidateCommand(ctx, stdout, agentLoader, toolValidator, agentRunnerFactory))
	return cmd
}

// newLibraryValidateCommand creates the combined package-library validation command.
func newLibraryValidateCommand(
	ctx context.Context,
	stdout io.Writer,
	agentLoader agentValidationLoader,
	toolValidator toolValidationRunner,
	agentRunnerFactory libraryAgentValidationRunnerFactory,
) *cobra.Command {
	opts := libraryValidationOptions{
		Root:     ".",
		AgentDir: "agents",
		ToolDir:  "tools",
		MCPDir:   "mcp",
		Runtime:  defaultAppOptions(),
	}
	cmd := &cobra.Command{
		Use:   "validate",
		Short: "Validate shared agent and tool packages",
		RunE: func(cmd *cobra.Command, args []string) error {
			if err := normalizeLibraryValidationOptions(cmd, &opts); err != nil {
				return returnLibraryValidationSetupError(stdout, opts, err)
			}
			agentRunner, cleanup, err := agentRunnerFactory(ctx, opts)
			if err != nil {
				return returnLibraryValidationSetupError(stdout, opts, err)
			}
			if cleanup != nil {
				defer cleanup()
			}
			result, err := runLibraryValidation(ctx, opts, agentLoader, libraryToolValidator(cmd, opts, toolValidator), agentRunner)
			if err != nil {
				return returnLibraryValidationSetupError(stdout, opts, err)
			}
			if opts.JSON {
				if err := json.NewEncoder(stdout).Encode(result); err != nil {
					return err
				}
			} else {
				if err := writeLibraryValidationSummary(stdout, result); err != nil {
					return err
				}
			}
			if opts.JUnitPath != "" {
				if err := writeJUnitReport(opts.JUnitPath, libraryValidationJUnit(result, opts.RequireToolCoverage, opts.RequireToolInputSchemas)); err != nil {
					return err
				}
			}
			if result.Failed > 0 || result.Unsupported > 0 {
				return fmt.Errorf("library validations did not pass: failed=%d unsupported=%d", result.Failed, result.Unsupported)
			}
			return nil
		},
	}
	cmd.Flags().StringVar(&opts.Root, "root", opts.Root, "package library root directory")
	cmd.Flags().StringVar(&opts.AgentPath, "agent", opts.AgentPath, "single agent config path relative to root or absolute")
	cmd.Flags().StringVar(&opts.AgentDir, "agent-dir", opts.AgentDir, "agent package directory relative to root; empty disables agent validation")
	cmd.Flags().StringVar(&opts.ToolPath, "tool", opts.ToolPath, "single tool config path relative to root or absolute")
	cmd.Flags().StringVar(&opts.ToolDir, "tool-dir", opts.ToolDir, "tool package directory relative to root; empty disables tool validation")
	cmd.Flags().StringVar(&opts.MCPDir, "mcp-dir", opts.MCPDir, "MCP package directory relative to root; empty disables MCP package validation")
	cmd.Flags().StringVar(&opts.AgentMode, "agent-mode", opts.AgentMode, "agent validation mode to run: all, mocked, or live")
	cmd.Flags().StringVar(&opts.ToolMode, "tool-mode", opts.ToolMode, "tool validation mode to run: all, mocked, or live")
	cmd.Flags().BoolVar(&opts.LiveAgents, "live-agents", opts.LiveAgents, "run agent validations through the configured live runtime")
	cmd.Flags().StringVar(&opts.Runtime.ModelConfigPath, "model", opts.Runtime.ModelConfigPath, "model config path for live agent validations")
	cmd.Flags().StringVar(&opts.RuntimeAgentPath, "runtime-agent", opts.RuntimeAgentPath, "agent config path for live tool agent-call validations; defaults to --agent for single-agent runs")
	cmd.Flags().StringVar(&opts.RuntimeToolPath, "runtime-tool", opts.RuntimeToolPath, "tool config path for live agent validations; defaults to --tool for single-tool runs")
	cmd.Flags().StringVar(&opts.Runtime.ProviderName, "provider", opts.Runtime.ProviderName, "provider name from config for live agent validations")
	cmd.Flags().StringVar(&opts.Runtime.ModelID, "model-id", opts.Runtime.ModelID, "model id from provider config for live agent validations")
	cmd.Flags().StringVar(&opts.Runtime.CommandDataDir, "command-data-dir", opts.Runtime.CommandDataDir, "command service data directory for live agent validations")
	cmd.Flags().StringArrayVar(&opts.Runtime.CommandAllowedWorkdirs, "command-allow-workdir", opts.Runtime.CommandAllowedWorkdirs, "allowed command working directory root for live agent validations")
	cmd.Flags().StringArrayVar(&opts.Runtime.CommandAllowedEnv, "command-allow-env", opts.Runtime.CommandAllowedEnv, "allowed process environment variable for live agent validations")
	cmd.Flags().StringVar(&opts.Runtime.CommandTemplatesJSON, "command-templates-json", opts.Runtime.CommandTemplatesJSON, "JSON command template list for live agent validations")
	cmd.Flags().StringVar(&opts.Runtime.CommandParserDir, "command-parser-dir", opts.Runtime.CommandParserDir, "Starlark command parser directory for live agent validations")
	cmd.Flags().DurationVar(&opts.Runtime.CommandDefaultTimeout, "command-timeout", opts.Runtime.CommandDefaultTimeout, "default command timeout for live agent validations")
	cmd.Flags().Int64Var(&opts.Runtime.CommandMaxOutputBytes, "command-max-output-bytes", opts.Runtime.CommandMaxOutputBytes, "default command output tail byte limit for live agent validations")
	cmd.Flags().BoolVar(&opts.RequireAgentValidations, "require-agent-validations", opts.RequireAgentValidations, "fail when an agent package has no behavior validations")
	cmd.Flags().BoolVar(&opts.RequireAgentAssertions, "require-agent-assertions", opts.RequireAgentAssertions, "fail when an agent behavior validation has no real assertions")
	cmd.Flags().BoolVar(&opts.RequireAgentToolCalls, "require-agent-tool-calls", opts.RequireAgentToolCalls, "fail when an agent package has no validation proving or capturing tool selection")
	cmd.Flags().BoolVar(&opts.RequireToolCoverage, "require-tool-coverage", opts.RequireToolCoverage, "fail when tool package operations, agent calls, workflow nodes, or MCP tools lack validations")
	cmd.Flags().BoolVar(&opts.RequireToolInputSchemas, "require-tool-input-schemas", opts.RequireToolInputSchemas, "fail when packaged command operations lack input schemas")
	cmd.Flags().BoolVar(&opts.RequireToolAssertions, "require-tool-assertions", opts.RequireToolAssertions, "fail when tool validations have no real assertions")
	cmd.Flags().BoolVar(&opts.RequireAgentToolContracts, "require-agent-tool-contracts", opts.RequireAgentToolContracts, "fail when agent validations reference tool calls not declared by packaged tools")
	cmd.Flags().StringVar(&opts.JUnitPath, "junit", opts.JUnitPath, "write JUnit XML validation results to this path")
	cmd.Flags().BoolVar(&opts.JSON, "json", opts.JSON, "write validation results as JSON")
	return cmd
}

// returnLibraryValidationSetupError writes CI artifacts for setup failures.
func returnLibraryValidationSetupError(stdout io.Writer, opts libraryValidationOptions, err error) error {
	if err == nil {
		return nil
	}
	result := libraryValidationFailureResult(opts, err)
	if opts.JSON {
		if writeErr := json.NewEncoder(stdout).Encode(result); writeErr != nil {
			return fmt.Errorf("%w; additionally failed to write library validation JSON: %v", err, writeErr)
		}
	}
	if opts.JUnitPath != "" {
		if writeErr := writeJUnitReport(opts.JUnitPath, libraryValidationJUnit(result, opts.RequireToolCoverage, opts.RequireToolInputSchemas)); writeErr != nil {
			return fmt.Errorf("%w; additionally failed to write library validation JUnit: %v", err, writeErr)
		}
	}
	return err
}

// libraryValidationFailureResult stores a setup failure as a validation result.
func libraryValidationFailureResult(opts libraryValidationOptions, err error) libraryValidationResult {
	root := filepath.Clean(opts.Root)
	result := libraryValidationResult{
		Root:   root,
		Error:  err.Error(),
		Total:  1,
		Failed: 1,
	}
	if strings.TrimSpace(opts.AgentPath) != "" {
		result.AgentPath = libraryChildPath(root, opts.AgentPath)
	} else if strings.TrimSpace(opts.AgentDir) != "" {
		result.AgentDir = libraryChildPath(root, opts.AgentDir)
	}
	if strings.TrimSpace(opts.ToolPath) != "" {
		result.ToolPath = libraryChildPath(root, opts.ToolPath)
	} else {
		if strings.TrimSpace(opts.ToolDir) != "" {
			result.ToolDir = libraryChildPath(root, opts.ToolDir)
		}
		if strings.TrimSpace(opts.MCPDir) != "" {
			result.MCPDir = libraryChildPath(root, opts.MCPDir)
		}
	}
	return result
}

// normalizeLibraryValidationOptions makes explicit files override package dirs.
func normalizeLibraryValidationOptions(cmd *cobra.Command, opts *libraryValidationOptions) error {
	if opts == nil {
		return nil
	}
	mode, err := normalizeAgentValidationMode(opts.AgentMode)
	if err != nil {
		return err
	}
	opts.AgentMode = mode
	toolMode, err := normalizeToolValidationMode(opts.ToolMode)
	if err != nil {
		return err
	}
	opts.ToolMode = toolMode
	if strings.TrimSpace(opts.AgentPath) != "" {
		if cmd.Flags().Changed("agent-dir") && strings.TrimSpace(opts.AgentDir) != "" {
			return fmt.Errorf("--agent and --agent-dir cannot be combined")
		}
		opts.AgentDir = ""
	}
	if strings.TrimSpace(opts.ToolPath) != "" {
		if cmd.Flags().Changed("tool-dir") && strings.TrimSpace(opts.ToolDir) != "" {
			return fmt.Errorf("--tool and --tool-dir cannot be combined")
		}
		if cmd.Flags().Changed("mcp-dir") && strings.TrimSpace(opts.MCPDir) != "" {
			return fmt.Errorf("--tool and --mcp-dir cannot be combined")
		}
		opts.ToolDir = ""
		opts.MCPDir = ""
	}
	return nil
}

// defaultLibraryAgentValidationRunner creates the mocked or live agent runner for library checks.
func defaultLibraryAgentValidationRunner(ctx context.Context, opts libraryValidationOptions) (*agentvalidation.Runner, func(), error) {
	if !opts.LiveAgents || opts.AgentMode == "mocked" || !libraryHasRunnableAgentSource(opts) {
		return agentvalidation.NewRunner(), nil, nil
	}
	runtime := opts.Runtime
	toolPath, explicitTool := libraryAgentRuntimeToolPath(filepath.Clean(opts.Root), opts)
	runtime.ToolPath = toolPath
	runtime.ToolSet = explicitTool
	host, err := app.NewAgentValidationHost(ctx, runtime)
	if err != nil {
		return nil, nil, err
	}
	return agentvalidation.NewRunnerWithHost(host), func() { _ = host.Close() }, nil
}

// libraryHasRunnableAgentSource reports whether this invocation will load agent packages.
func libraryHasRunnableAgentSource(opts libraryValidationOptions) bool {
	root := filepath.Clean(opts.Root)
	if strings.TrimSpace(opts.AgentPath) != "" {
		return true
	}
	if strings.TrimSpace(opts.AgentDir) == "" {
		return false
	}
	return directoryExists(libraryChildPath(root, opts.AgentDir))
}

// libraryAgentRuntimeToolPath resolves the active tool config for live agent library checks.
func libraryAgentRuntimeToolPath(root string, opts libraryValidationOptions) (string, bool) {
	if strings.TrimSpace(opts.RuntimeToolPath) != "" {
		return libraryChildPath(root, opts.RuntimeToolPath), true
	}
	if strings.TrimSpace(opts.ToolPath) != "" {
		return libraryChildPath(root, opts.ToolPath), true
	}
	return opts.Runtime.ToolPath, false
}

// libraryToolValidator injects live runtime options for tool validation lanes.
func libraryToolValidator(cmd *cobra.Command, opts libraryValidationOptions, fallback toolValidationRunner) toolValidationRunner {
	if fallback == nil {
		fallback = runToolValidationSuite
	}
	if !libraryToolValidationNeedsRuntime(cmd, opts) {
		return fallback
	}
	return func(ctx context.Context, path string, validationIDs []string, mode string) (toolvalidation.SuiteResult, error) {
		runtime := libraryToolValidationRuntime(filepath.Clean(opts.Root), path, opts)
		if !cmd.Flags().Changed("command-data-dir") {
			runtime.CommandDataDir = ""
		}
		return runToolValidationSuiteWithRuntime(ctx, path, validationIDs, mode, runtime)
	}
}

// libraryToolValidationNeedsRuntime reports whether library options must override tool validation runtime.
func libraryToolValidationNeedsRuntime(cmd *cobra.Command, opts libraryValidationOptions) bool {
	if opts.ToolMode != "live" {
		return false
	}
	if strings.TrimSpace(opts.AgentPath) != "" || strings.TrimSpace(opts.RuntimeAgentPath) != "" {
		return true
	}
	return libraryToolValidationRuntimeFlagsChanged(cmd)
}

// libraryToolValidationRuntime resolves runtime options for live tool tests.
func libraryToolValidationRuntime(root string, toolPath string, opts libraryValidationOptions) app.Options {
	runtime := opts.Runtime
	runtime.AgentConfigPath = libraryToolRuntimeAgentPath(root, opts)
	runtime.ToolPath = toolPath
	runtime.ToolSet = true
	return runtime
}

// libraryToolRuntimeAgentPath resolves the active agent config for live tool tests.
func libraryToolRuntimeAgentPath(root string, opts libraryValidationOptions) string {
	if strings.TrimSpace(opts.RuntimeAgentPath) != "" {
		return libraryChildPath(root, opts.RuntimeAgentPath)
	}
	if strings.TrimSpace(opts.AgentPath) != "" {
		return libraryChildPath(root, opts.AgentPath)
	}
	return opts.Runtime.AgentConfigPath
}

// libraryToolValidationRuntimeFlagsChanged reports whether live tool runtime flags were supplied.
func libraryToolValidationRuntimeFlagsChanged(cmd *cobra.Command) bool {
	for _, name := range []string{
		"runtime-agent",
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

// runLibraryValidation validates conventional package-library directories.
func runLibraryValidation(
	ctx context.Context,
	opts libraryValidationOptions,
	agentLoader agentValidationLoader,
	toolValidator toolValidationRunner,
	agentRunner *agentvalidation.Runner,
) (libraryValidationResult, error) {
	root := filepath.Clean(opts.Root)
	result := libraryValidationResult{Root: root}
	if agentRunner == nil {
		agentRunner = agentvalidation.NewRunner()
	}
	if opts.RequireAgentToolContracts && (!libraryHasAgentSource(opts) || !libraryHasToolSource(opts)) {
		return libraryValidationResult{}, fmt.Errorf("--require-agent-tool-contracts requires both agent and tool package sources")
	}
	runners := 0
	requireAgentDir := opts.RequireAgentValidations ||
		opts.RequireAgentAssertions ||
		opts.RequireAgentToolCalls ||
		opts.RequireAgentToolContracts
	requireToolSource := opts.RequireToolCoverage || opts.RequireToolInputSchemas || opts.RequireToolAssertions || opts.RequireAgentToolContracts
	if opts.AgentPath != "" {
		path := libraryChildPath(root, opts.AgentPath)
		agents := runAgentValidationFiles(ctx, []string{path}, agentLoader, agentRunner, nil, opts.AgentMode, opts.RequireAgentValidations, opts.RequireAgentAssertions)
		result.AgentPath = path
		result.Agents = &agents
		result.addAgentResult(agents)
		runners++
	} else if opts.AgentDir != "" {
		path := libraryChildPath(root, opts.AgentDir)
		if !directoryExists(path) {
			if requireAgentDir {
				return libraryValidationResult{}, fmt.Errorf("required agent package directory not found: %s", path)
			}
		} else {
			if err := addLibraryAgentResults(ctx, &result, path, agentLoader, agentRunner, opts); err != nil {
				return libraryValidationResult{}, err
			}
			runners++
		}
	}
	toolResults := toolValidationLibraryResult{Packages: []toolValidationPackageResult{}}
	toolRunners := 0
	if opts.ToolPath != "" {
		path := libraryChildPath(root, opts.ToolPath)
		tools := runSingleToolValidationPackage(ctx, path, nil, opts.ToolMode, toolValidator, opts.RequireToolAssertions)
		applyToolCoverageFailures(&tools, opts.RequireToolCoverage)
		applyToolInputSchemaFailures(&tools, opts.RequireToolInputSchemas)
		result.ToolPath = path
		mergeToolValidationLibraryResults(&toolResults, tools)
		toolRunners++
	} else {
		if opts.ToolDir != "" {
			path := libraryChildPath(root, opts.ToolDir)
			if directoryExists(path) {
				tools, err := runToolValidationDirectory(ctx, path, nil, opts.ToolMode, toolValidator, opts.RequireToolAssertions)
				var missing toolvalidation.MissingValidationError
				if err != nil && !errors.As(err, &missing) {
					return libraryValidationResult{}, err
				}
				applyToolCoverageFailures(&tools, opts.RequireToolCoverage)
				applyToolInputSchemaFailures(&tools, opts.RequireToolInputSchemas)
				result.ToolDir = path
				mergeToolValidationLibraryResults(&toolResults, tools)
				toolRunners++
			}
		}
		if opts.MCPDir != "" {
			path := libraryChildPath(root, opts.MCPDir)
			if directoryExists(path) {
				tools, err := runMCPValidationDirectory(ctx, path, nil, opts.ToolMode, toolValidator, opts.RequireToolAssertions)
				var missing toolvalidation.MissingValidationError
				if err != nil && !errors.As(err, &missing) {
					return libraryValidationResult{}, err
				}
				applyToolCoverageFailures(&tools, opts.RequireToolCoverage)
				applyToolInputSchemaFailures(&tools, opts.RequireToolInputSchemas)
				result.MCPDir = path
				mergeToolValidationLibraryResults(&toolResults, tools)
				toolRunners++
			}
		}
	}
	if toolRunners > 0 {
		result.Tools = &toolResults
		result.addToolResult(toolResults)
		runners++
	} else if requireToolSource {
		return libraryValidationResult{}, fmt.Errorf("required tool package directory not found: %s", libraryChildPath(root, firstNonEmptyAgentValidationValue(opts.ToolDir, "tools")))
	}
	if runners == 0 {
		return libraryValidationResult{}, fmt.Errorf("no agent or tool package sources found under %s", root)
	}
	if opts.RequireAgentToolCalls {
		applyAgentToolCallFailures(result.Agents)
		recountLibraryValidationResult(&result)
	}
	if opts.RequireAgentToolContracts {
		applyAgentToolContractFailures(&result)
		recountLibraryValidationResult(&result)
	}
	return result, nil
}

// libraryHasAgentSource reports whether validation has an agent input.
func libraryHasAgentSource(opts libraryValidationOptions) bool {
	return strings.TrimSpace(opts.AgentPath) != "" || strings.TrimSpace(opts.AgentDir) != ""
}

// libraryHasToolSource reports whether validation has a tool input.
func libraryHasToolSource(opts libraryValidationOptions) bool {
	return strings.TrimSpace(opts.ToolPath) != "" ||
		strings.TrimSpace(opts.ToolDir) != "" ||
		strings.TrimSpace(opts.MCPDir) != ""
}

// addLibraryAgentResults validates and stores agent package library results.
func addLibraryAgentResults(
	ctx context.Context,
	result *libraryValidationResult,
	path string,
	agentLoader agentValidationLoader,
	agentRunner *agentvalidation.Runner,
	opts libraryValidationOptions,
) error {
	if agentRunner == nil {
		agentRunner = agentvalidation.NewRunner()
	}
	agents, err := runAgentValidationDirectory(ctx, path, agentLoader, agentRunner, nil, opts.AgentMode, opts.RequireAgentValidations, opts.RequireAgentAssertions)
	if err != nil {
		return err
	}
	result.AgentDir = path
	result.Agents = &agents
	result.addAgentResult(agents)
	return nil
}

// runSingleToolValidationPackage adapts one tool config file into library results.
func runSingleToolValidationPackage(
	ctx context.Context,
	path string,
	validationIDs []string,
	mode string,
	validator toolValidationRunner,
	requireAssertions bool,
) toolValidationLibraryResult {
	suite, err := validator(ctx, path, validationIDs, mode)
	var missing toolvalidation.MissingValidationError
	result := toolValidationLibraryResult{Packages: []toolValidationPackageResult{}}
	if err != nil && !(len(validationIDs) > 0 && errors.As(err, &missing)) {
		addToolValidationPackageResult(&result, toolValidationPackageFailure(path, err))
		return result
	}
	if requireAssertions {
		markToolValidationMissingAssertions(&suite)
	}
	addToolValidationPackageResult(&result, toolValidationPackageResult{
		Path:   filepath.Clean(path),
		Result: suite,
	})
	return result
}

// mergeToolValidationLibraryResults appends one package-library run into another.
func mergeToolValidationLibraryResults(result *toolValidationLibraryResult, next toolValidationLibraryResult) {
	if result == nil {
		return
	}
	result.TotalPackages += next.TotalPackages
	result.PassedPackages += next.PassedPackages
	result.FailedPackages += next.FailedPackages
	result.UnsupportedPackages += next.UnsupportedPackages
	result.Total += next.Total
	result.Passed += next.Passed
	result.Failed += next.Failed
	result.Unsupported += next.Unsupported
	result.CoverageRequired += next.CoverageRequired
	result.CoverageCovered += next.CoverageCovered
	result.CoverageMissing += next.CoverageMissing
	result.InputSchemaRequired += next.InputSchemaRequired
	result.InputSchemaCovered += next.InputSchemaCovered
	result.InputSchemaMissing += next.InputSchemaMissing
	result.MissingAssertions += next.MissingAssertions
	result.Packages = append(result.Packages, next.Packages...)
}

// applyAgentToolCallFailures fails packages with no proved tool-call behavior.
func applyAgentToolCallFailures(result *agentValidationResult) {
	if result == nil {
		return
	}
	for index := range result.Agents {
		item := &result.Agents[index]
		if len(item.Result.ToolCallReferences) > 0 {
			continue
		}
		name := firstNonEmptyAgentValidationValue(item.Name, item.Path, "agent")
		item.MissingToolCalls = append(item.MissingToolCalls, name)
		if len(item.Result.Results) == 0 {
			item.Error = appendAgentValidationError(item.Error, "agent validations do not prove any tool calls")
			continue
		}
		item.Result.Results[0].Assertions = append(item.Result.Results[0].Assertions, agentvalidation.AssertionResult{
			Type:    "required-tool-call",
			Passed:  false,
			Message: "agent package validations do not prove any tool calls",
		})
		item.Result.Results[0].Status = agentvalidation.StatusFailed
		recountAgentValidationSuite(&item.Result)
	}
	recountAgentValidationResult(result)
}

// addAgentResult folds agent validation results into the library summary.
func (r *libraryValidationResult) addAgentResult(result agentValidationResult) {
	r.Total += result.Total
	r.Passed += result.Passed
	r.Failed += result.Failed
	r.Unsupported += result.Unsupported
}

// addToolResult folds tool validation results into the library summary.
func (r *libraryValidationResult) addToolResult(result toolValidationLibraryResult) {
	r.Total += result.TotalPackages
	r.Passed += result.PassedPackages
	r.Failed += result.FailedPackages
	r.Unsupported += result.UnsupportedPackages
}

// applyToolCoverageFailures reclassifies otherwise passing packages missing coverage.
func applyToolCoverageFailures(result *toolValidationLibraryResult, requireCoverage bool) {
	if result == nil || !requireCoverage {
		return
	}
	for _, item := range result.Packages {
		if item.Error != "" || len(item.Result.Coverage.Missing) == 0 || item.Result.Failed > 0 || item.Result.Unsupported > 0 {
			continue
		}
		if result.PassedPackages > 0 {
			result.PassedPackages--
		}
		result.FailedPackages++
	}
}

// applyToolInputSchemaFailures reclassifies passing packages missing schemas.
func applyToolInputSchemaFailures(result *toolValidationLibraryResult, requireInputSchemas bool) {
	if result == nil || !requireInputSchemas {
		return
	}
	for _, item := range result.Packages {
		if item.Error != "" ||
			len(item.Result.InputSchemaCoverage.Missing) == 0 ||
			item.Result.Failed > 0 ||
			item.Result.Unsupported > 0 {
			continue
		}
		if result.PassedPackages > 0 {
			result.PassedPackages--
		}
		result.FailedPackages++
	}
}

// applyAgentToolContractFailures fails agent cases that reference absent tools.
func applyAgentToolContractFailures(result *libraryValidationResult) {
	if result == nil || result.Agents == nil || result.Tools == nil {
		return
	}
	available := availableAgentToolCallSet(result.Tools)
	contracts := availableAgentToolContractSet(result.Tools)
	applyAgentToolContractSetFailures(result.Agents, available, contracts)
}

// availableAgentToolCallSet collects callable ids exposed by packaged tools.
func availableAgentToolCallSet(result *toolValidationLibraryResult) map[string]struct{} {
	available := map[string]struct{}{}
	if result == nil {
		return available
	}
	for _, item := range result.Packages {
		for _, id := range item.Result.AgentToolCalls {
			if trimmed := strings.TrimSpace(id); trimmed != "" {
				available[trimmed] = struct{}{}
			}
		}
	}
	return available
}

// availableAgentToolContractSet collects packaged tool contracts by id.
func availableAgentToolContractSet(result *toolValidationLibraryResult) map[string]toolvalidation.AgentToolContract {
	available := map[string]toolvalidation.AgentToolContract{}
	if result == nil {
		return available
	}
	for _, item := range result.Packages {
		for id, contract := range item.Result.AgentToolContracts {
			key := strings.TrimSpace(id)
			if key == "" {
				key = strings.TrimSpace(contract.ID)
			}
			if key == "" {
				continue
			}
			available[key] = contract
		}
	}
	return available
}

// markUnknownAgentToolCalls adds assertion failures for unknown tool references.
func markUnknownAgentToolCalls(
	suite *agentvalidation.SuiteResult,
	available map[string]struct{},
) []string {
	if suite == nil || len(suite.Results) == 0 {
		return nil
	}
	unknown := make([]string, 0)
	seen := map[string]struct{}{}
	for index := range suite.Results {
		refs := agentToolCallReferences(suite.Results[index])
		for _, ref := range refs {
			if agentToolCallKnown(ref, available) {
				continue
			}
			key := suite.Results[index].ID + ":" + ref.Display
			if _, ok := seen[key]; ok {
				continue
			}
			seen[key] = struct{}{}
			name := firstNonEmptyAgentValidationValue(suite.Results[index].ID, suite.Results[index].Label, "validation")
			unknown = append(unknown, name+": "+ref.Display)
			suite.Results[index].Assertions = append(suite.Results[index].Assertions, agentvalidation.AssertionResult{
				Type:     "tool-contract",
				Path:     "response.tool_calls",
				Passed:   false,
				Expected: ref.Display,
				Message:  "agent validation references a tool call that is not declared by packaged tools",
			})
			suite.Results[index].Status = agentvalidation.StatusFailed
		}
	}
	if len(unknown) > 0 {
		recountAgentValidationSuite(suite)
	}
	return unknown
}

// markInvalidAgentToolArguments adds assertion failures for bad tool arguments.
func markInvalidAgentToolArguments(
	suite *agentvalidation.SuiteResult,
	contracts map[string]toolvalidation.AgentToolContract,
) []string {
	if suite == nil || len(suite.Results) == 0 {
		return nil
	}
	failures := make([]string, 0)
	for resultIndex := range suite.Results {
		result := &suite.Results[resultIndex]
		if result.Response == nil {
			continue
		}
		for _, call := range result.Response.ToolCalls {
			ref, contract, ok := knownAgentToolCallContract(call, contracts)
			if !ok || len(contract.InputSchema) == 0 {
				continue
			}
			parameters := agentToolCallParameters(call)
			validation := commandservice.ValidateOutput(parameters, contract.InputSchema)
			if validation.Valid {
				continue
			}
			name := firstNonEmptyAgentValidationValue(result.ID, result.Label, "validation")
			message := "agent tool call arguments do not match packaged tool input schema: " + strings.Join(validation.Errors, "; ")
			failures = append(failures, name+": "+ref.Display)
			result.Assertions = append(result.Assertions, agentvalidation.AssertionResult{
				Type:     "tool-arguments",
				Path:     "response.tool_calls",
				Passed:   false,
				Expected: ref.Display,
				Actual:   parameters,
				Message:  message,
			})
			result.Status = agentvalidation.StatusFailed
		}
	}
	if len(failures) > 0 {
		recountAgentValidationSuite(suite)
	}
	return failures
}

// agentToolCallReference stores one reference and compatible lookup forms.
type agentToolCallReference struct {
	Display    string
	Candidates []string
}

// agentToolCallReferences extracts expected and observed tool-call contracts.
func agentToolCallReferences(result agentvalidation.Result) []agentToolCallReference {
	refs := make([]agentToolCallReference, 0)
	for _, assertion := range result.Assertions {
		if strings.TrimSpace(assertion.Type) != "tool-call" {
			continue
		}
		if ref, ok := agentToolCallReferenceFromValue(fmt.Sprint(assertion.Expected)); ok {
			refs = append(refs, ref)
		}
	}
	if result.Response != nil {
		for _, call := range result.Response.ToolCalls {
			refs = append(refs, agentToolCallReferencesFromCall(call)...)
		}
	}
	return dedupeAgentToolCallReferences(refs)
}

// agentToolCallReferenceFromValue normalizes one configured tool reference.
func agentToolCallReferenceFromValue(value string) (agentToolCallReference, bool) {
	display := strings.TrimSpace(value)
	candidates := agentToolCallCandidates(display)
	return agentToolCallReference{Display: display, Candidates: candidates}, display != "" && len(candidates) > 0
}

// agentToolCallReferencesFromCall normalizes one captured agent tool call.
func agentToolCallReferencesFromCall(call agentvalidation.ToolCall) []agentToolCallReference {
	refs := make([]agentToolCallReference, 0, 2)
	if templateID := stringFromLibraryAny(call.Arguments["template_id"]); templateID != "" {
		if ref, ok := agentToolCallReferenceFromValue("command:" + templateID); ok {
			refs = append(refs, ref)
		}
	}
	if ref, ok := agentToolCallReferenceFromValue(call.Name); ok && isSpecificToolCallReference(ref.Display) {
		refs = append(refs, ref)
	}
	if ref, ok := agentToolCallReferenceFromValue(call.ID); ok && isSpecificToolCallReference(ref.Display) {
		refs = append(refs, ref)
	}
	return refs
}

// knownAgentToolCallContract returns the packaged contract for one call.
func knownAgentToolCallContract(
	call agentvalidation.ToolCall,
	contracts map[string]toolvalidation.AgentToolContract,
) (agentToolCallReference, toolvalidation.AgentToolContract, bool) {
	for _, ref := range agentToolCallReferencesFromCall(call) {
		if contract, ok := agentToolCallContract(ref, contracts); ok {
			return ref, contract, true
		}
	}
	return agentToolCallReference{}, toolvalidation.AgentToolContract{}, false
}

// agentToolCallContract returns a matching contract for compatible ids.
func agentToolCallContract(
	ref agentToolCallReference,
	contracts map[string]toolvalidation.AgentToolContract,
) (toolvalidation.AgentToolContract, bool) {
	for _, candidate := range ref.Candidates {
		if contract, ok := contracts[candidate]; ok {
			return contract, true
		}
	}
	return toolvalidation.AgentToolContract{}, false
}

// agentToolCallParameters returns parameters passed to a captured tool call.
func agentToolCallParameters(call agentvalidation.ToolCall) map[string]any {
	if parameters, ok := mapFromLibraryAny(call.Arguments["parameters"]); ok {
		return parameters
	}
	parameters := make(map[string]any, len(call.Arguments))
	for key, value := range call.Arguments {
		if strings.TrimSpace(key) == "template_id" {
			continue
		}
		parameters[key] = value
	}
	return parameters
}

// agentToolCallCandidates returns compatible ids for a tool-call reference.
func agentToolCallCandidates(value string) []string {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return nil
	}
	candidates := []string{trimmed}
	if !strings.Contains(trimmed, ":") && strings.Contains(trimmed, ".") {
		candidates = append(candidates, "command:"+trimmed)
	}
	return candidates
}

// agentToolCallKnown reports whether any candidate is packaged.
func agentToolCallKnown(ref agentToolCallReference, available map[string]struct{}) bool {
	for _, candidate := range ref.Candidates {
		if _, ok := available[candidate]; ok {
			return true
		}
	}
	return false
}

// dedupeAgentToolCallReferences removes repeated references from one result.
func dedupeAgentToolCallReferences(refs []agentToolCallReference) []agentToolCallReference {
	out := make([]agentToolCallReference, 0, len(refs))
	seen := map[string]struct{}{}
	for _, ref := range refs {
		key := strings.TrimSpace(ref.Display)
		if key == "" {
			continue
		}
		if _, ok := seen[key]; ok {
			continue
		}
		seen[key] = struct{}{}
		out = append(out, ref)
	}
	return out
}

// isSpecificToolCallReference filters provider call ids from contract ids.
func isSpecificToolCallReference(value string) bool {
	trimmed := strings.TrimSpace(value)
	return strings.HasPrefix(trimmed, "command:") ||
		strings.HasPrefix(trimmed, "mcp:") ||
		(!strings.Contains(trimmed, ":") && strings.Contains(trimmed, "."))
}

// stringFromLibraryAny returns a compact string for generic validation data.
func stringFromLibraryAny(value any) string {
	if value == nil {
		return ""
	}
	if text, ok := value.(string); ok {
		return strings.TrimSpace(text)
	}
	return strings.TrimSpace(fmt.Sprint(value))
}

// mapFromLibraryAny returns a generic map for validation argument payloads.
func mapFromLibraryAny(value any) (map[string]any, bool) {
	switch typed := value.(type) {
	case map[string]any:
		return typed, true
	case map[string]string:
		out := make(map[string]any, len(typed))
		for key, item := range typed {
			out[key] = item
		}
		return out, true
	default:
		return nil, false
	}
}

// recountLibraryValidationResult recomputes aggregate counters after gates.
func recountLibraryValidationResult(result *libraryValidationResult) {
	if result == nil {
		return
	}
	result.Total = 0
	result.Passed = 0
	result.Failed = 0
	result.Unsupported = 0
	if result.Agents != nil {
		result.addAgentResult(*result.Agents)
	}
	if result.Tools != nil {
		result.addToolResult(*result.Tools)
	}
}

// libraryChildPath resolves relative library child paths.
func libraryChildPath(root string, child string) string {
	if filepath.IsAbs(child) {
		return filepath.Clean(child)
	}
	return filepath.Join(root, child)
}

// directoryExists reports whether path exists as a directory.
func directoryExists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.IsDir()
}

// writeLibraryValidationSummary writes a compact report for a package library.
func writeLibraryValidationSummary(stdout io.Writer, result libraryValidationResult) error {
	if _, err := fmt.Fprintf(
		stdout,
		"Library validations: total=%d passed=%d failed=%d unsupported=%d\n",
		result.Total,
		result.Passed,
		result.Failed,
		result.Unsupported,
	); err != nil {
		return err
	}
	if result.Agents != nil {
		if _, err := fmt.Fprintf(
			stdout,
			"agents %s: total=%d passed=%d failed=%d unsupported=%d cases=%d passed=%d failed=%d unsupported=%d\n",
			librarySourceLabel(result.AgentDir, result.AgentPath),
			result.Agents.Total,
			result.Agents.Passed,
			result.Agents.Failed,
			result.Agents.Unsupported,
			result.Agents.ValidationTotal,
			result.Agents.ValidationPassed,
			result.Agents.ValidationFailed,
			result.Agents.ValidationUnsupported,
		); err != nil {
			return err
		}
		for _, item := range result.Agents.Agents {
			if item.Passed {
				continue
			}
			if err := writeAgentValidationFileSummary(stdout, item); err != nil {
				return err
			}
		}
	}
	if result.Tools != nil {
		if _, err := fmt.Fprintf(
			stdout,
			"tools %s: packages=%d passed=%d failed=%d unsupported=%d total=%d passed=%d failed=%d unsupported=%d coverage=%d/%d missing=%d input_schemas=%d/%d missing=%d assertions_missing=%d\n",
			libraryToolSourceLabel(result.ToolDir, result.MCPDir, result.ToolPath),
			result.Tools.TotalPackages,
			result.Tools.PassedPackages,
			result.Tools.FailedPackages,
			result.Tools.UnsupportedPackages,
			result.Tools.Total,
			result.Tools.Passed,
			result.Tools.Failed,
			result.Tools.Unsupported,
			result.Tools.CoverageCovered,
			result.Tools.CoverageRequired,
			result.Tools.CoverageMissing,
			result.Tools.InputSchemaCovered,
			result.Tools.InputSchemaRequired,
			result.Tools.InputSchemaMissing,
			result.Tools.MissingAssertions,
		); err != nil {
			return err
		}
		for _, item := range result.Tools.Packages {
			if toolValidationPackagePassed(item) {
				continue
			}
			if err := writeToolValidationLibraryPackageSummary(stdout, item); err != nil {
				return err
			}
		}
	}
	return nil
}

// libraryToolSourceLabel returns the displayed tool and MCP package sources.
func libraryToolSourceLabel(toolDir string, mcpDir string, file string) string {
	sources := make([]string, 0, 2)
	if strings.TrimSpace(toolDir) != "" {
		sources = append(sources, toolDir)
	}
	if strings.TrimSpace(mcpDir) != "" {
		sources = append(sources, mcpDir)
	}
	if len(sources) > 0 {
		return strings.Join(sources, " + ")
	}
	return file
}

// librarySourceLabel returns the displayed package source for summaries.
func librarySourceLabel(directory string, file string) string {
	if strings.TrimSpace(directory) != "" {
		return directory
	}
	return file
}

// toolValidationPackagePassed reports whether a package needs no detail line.
func toolValidationPackagePassed(item toolValidationPackageResult) bool {
	return item.Error == "" &&
		item.Result.Failed == 0 &&
		item.Result.Unsupported == 0 &&
		len(item.Result.Coverage.Missing) == 0 &&
		len(item.Result.InputSchemaCoverage.Missing) == 0 &&
		len(item.Result.MissingAssertions) == 0
}

// libraryValidationJUnit converts a combined library result to JUnit XML.
func libraryValidationJUnit(
	result libraryValidationResult,
	requireToolCoverage bool,
	requireToolInputSchemas bool,
) junitSuites {
	report := junitSuites{Name: "library-validations"}
	if strings.TrimSpace(result.Error) != "" {
		report.Suites = append(report.Suites, libraryValidationSetupJUnit(result))
	}
	if result.Agents != nil {
		report.Suites = append(report.Suites, agentValidationJUnit(*result.Agents).Suites...)
	}
	if result.Tools != nil {
		report.Suites = append(report.Suites, toolValidationJUnitForLibrary(*result.Tools, requireToolCoverage, requireToolInputSchemas).Suites...)
	}
	return finalizeJUnit(report)
}

// libraryValidationSetupJUnit converts a library setup failure to JUnit.
func libraryValidationSetupJUnit(result libraryValidationResult) junitSuite {
	name := strings.TrimSpace(result.Root)
	if name == "" {
		name = "library"
	}
	return finalizeJUnitSuite(junitSuite{
		Name: name,
		TestCases: []junitCase{{
			Name:      "library.setup",
			ClassName: name,
			Failure: &junitFailure{
				Message: "library validation setup failed",
				Text:    result.Error,
			},
		}},
	})
}
