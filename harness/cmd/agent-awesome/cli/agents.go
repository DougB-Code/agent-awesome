// This file defines agent configuration validation CLI commands.
package cli

import (
	"context"
	"encoding/json"
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
	"agentawesome/internal/services/agentvalidation"
	"agentawesome/internal/services/toolvalidation"
	"github.com/spf13/cobra"
)

// agentValidationOptions stores CLI options for validating agent configs.
type agentValidationOptions struct {
	AgentPath            string
	AgentDir             string
	ValidationIDs        []string
	Mode                 string
	Live                 bool
	Runtime              app.Options
	JSON                 bool
	JUnitPath            string
	RequireValidations   bool
	RequireAssertions    bool
	RequireToolCalls     bool
	RequireToolContracts bool
}

// agentValidationRunnerFactory creates the runner for mocked or live checks.
type agentValidationRunnerFactory func(context.Context, agentValidationOptions) (*agentvalidation.Runner, func(), error)

// agentValidationLoader loads one agent config file.
type agentValidationLoader func(string) (schema.Agent, error)

// agentValidationResult stores one or more agent validation checks.
type agentValidationResult struct {
	Total                 int                         `json:"total"`
	Passed                int                         `json:"passed"`
	Failed                int                         `json:"failed"`
	Unsupported           int                         `json:"unsupported"`
	ValidationTotal       int                         `json:"validation_total"`
	ValidationPassed      int                         `json:"validation_passed"`
	ValidationFailed      int                         `json:"validation_failed"`
	ValidationUnsupported int                         `json:"validation_unsupported"`
	ToolCallReferences    []string                    `json:"tool_call_references,omitempty"`
	Agents                []agentValidationFileResult `json:"agents"`
}

// agentValidationFileResult stores one agent config validation result.
type agentValidationFileResult struct {
	Path              string                      `json:"path"`
	Name              string                      `json:"name,omitempty"`
	Passed            bool                        `json:"passed"`
	Unsupported       bool                        `json:"unsupported,omitempty"`
	Error             string                      `json:"error,omitempty"`
	MissingAssertions []string                    `json:"missing_assertions,omitempty"`
	MissingToolCalls  []string                    `json:"missing_tool_calls,omitempty"`
	UnknownToolCalls  []string                    `json:"unknown_tool_calls,omitempty"`
	InvalidToolArgs   []string                    `json:"invalid_tool_arguments,omitempty"`
	Result            agentvalidation.SuiteResult `json:"result"`
	MissingSelection  bool                        `json:"-"`
}

// newAgentsCommand creates agent package commands.
func newAgentsCommand(ctx context.Context) *cobra.Command {
	return newAgentsCommandWithLoader(ctx, os.Stdout, config.LoadAgent)
}

// newAgentsCommandWithLoader creates agent commands with injectable behavior.
func newAgentsCommandWithLoader(
	ctx context.Context,
	stdout io.Writer,
	loader agentValidationLoader,
) *cobra.Command {
	return newAgentsCommandWithLoaderAndRunner(ctx, stdout, loader, defaultAgentValidationRunner)
}

// newAgentsCommandWithLoaderAndRunner creates agent commands with injectable validation runtime behavior.
func newAgentsCommandWithLoaderAndRunner(
	ctx context.Context,
	stdout io.Writer,
	loader agentValidationLoader,
	runnerFactory agentValidationRunnerFactory,
) *cobra.Command {
	cmd := &cobra.Command{
		Use:   "agents",
		Short: "Validate configured agent packages",
	}
	cmd.AddCommand(newAgentsValidateCommand(ctx, stdout, loader, runnerFactory))
	return cmd
}

// newAgentsValidateCommand creates the agent config validation command.
func newAgentsValidateCommand(ctx context.Context, stdout io.Writer, loader agentValidationLoader, runnerFactory agentValidationRunnerFactory) *cobra.Command {
	opts := agentValidationOptions{
		AgentPath: config.DefaultAgentPath(),
		Runtime:   defaultAppOptions(),
	}
	cmd := &cobra.Command{
		Use:   "validate",
		Short: "Validate agent configuration files",
		RunE: func(cmd *cobra.Command, args []string) error {
			opts.Runtime.AgentConfigPath = opts.AgentPath
			opts.Runtime.ToolSet = cmd.Flags().Changed("tool")
			mode, err := normalizeAgentValidationMode(opts.Mode)
			if err != nil {
				return err
			}
			opts.Mode = mode
			runner, cleanup, err := runnerFactory(ctx, opts)
			if err != nil {
				return returnAgentValidationSetupError(stdout, opts, err)
			}
			if cleanup != nil {
				defer cleanup()
			}
			var result agentValidationResult
			var validationErr error
			if opts.AgentDir != "" {
				if cmd.Flags().Changed("agent") {
					return fmt.Errorf("--agent and --agent-dir cannot be combined")
				}
				result, err = runAgentValidationDirectory(ctx, opts.AgentDir, loader, runner, opts.ValidationIDs, mode, opts.RequireValidations, opts.RequireAssertions)
				if err != nil {
					var missing agentvalidation.MissingValidationError
					if errors.As(err, &missing) {
						validationErr = err
					} else {
						result = agentValidationFailureResult(opts.AgentDir, err)
						validationErr = err
					}
				}
			} else {
				result = runAgentValidationFiles(ctx, []string{opts.AgentPath}, loader, runner, opts.ValidationIDs, mode, opts.RequireValidations, opts.RequireAssertions)
			}
			if opts.RequireToolCalls {
				applyAgentToolCallFailures(&result)
			}
			if opts.RequireToolContracts {
				if err := applyAgentToolContractFailuresFromConfig(&result, opts.Runtime.ToolPath, opts.Runtime.ToolSet); err != nil {
					markAgentValidationToolContractSetupError(&result, err)
					validationErr = err
				}
			}
			if opts.JSON {
				if err := json.NewEncoder(stdout).Encode(result); err != nil {
					return err
				}
			} else {
				if err := writeAgentValidationSummary(stdout, result); err != nil {
					return err
				}
			}
			if opts.JUnitPath != "" {
				if err := writeJUnitReport(opts.JUnitPath, agentValidationJUnit(result)); err != nil {
					return err
				}
			}
			if validationErr != nil {
				return validationErr
			}
			if result.Failed > 0 || result.Unsupported > 0 {
				return fmt.Errorf("agent validations did not pass: failed=%d unsupported=%d", result.Failed, result.Unsupported)
			}
			return nil
		},
	}
	cmd.Flags().StringVar(&opts.AgentPath, "agent", opts.AgentPath, "agent config path")
	cmd.Flags().StringVar(&opts.AgentDir, "agent-dir", opts.AgentDir, "agent package directory to validate")
	cmd.Flags().StringArrayVar(&opts.ValidationIDs, "validation", opts.ValidationIDs, "validation ID to run; repeat for multiple IDs")
	cmd.Flags().StringVar(&opts.Mode, "mode", opts.Mode, "validation mode to run: all, mocked, or live")
	cmd.Flags().BoolVar(&opts.Live, "live", opts.Live, "run live agent validations through the configured runtime")
	cmd.Flags().StringVar(&opts.Runtime.ModelConfigPath, "model", opts.Runtime.ModelConfigPath, "model config path for live validations")
	cmd.Flags().StringVar(&opts.Runtime.ToolPath, "tool", opts.Runtime.ToolPath, "tool config path for live validations or contract checks")
	cmd.Flags().StringVar(&opts.Runtime.ProviderName, "provider", opts.Runtime.ProviderName, "provider name from config for live validations")
	cmd.Flags().StringVar(&opts.Runtime.ModelID, "model-id", opts.Runtime.ModelID, "model id from provider config for live validations")
	cmd.Flags().StringVar(&opts.Runtime.CommandDataDir, "command-data-dir", opts.Runtime.CommandDataDir, "command service data directory for live validations")
	cmd.Flags().StringArrayVar(&opts.Runtime.CommandAllowedWorkdirs, "command-allow-workdir", opts.Runtime.CommandAllowedWorkdirs, "allowed command working directory root for live validations")
	cmd.Flags().StringArrayVar(&opts.Runtime.CommandAllowedEnv, "command-allow-env", opts.Runtime.CommandAllowedEnv, "allowed process environment variable for live validations")
	cmd.Flags().StringVar(&opts.Runtime.CommandTemplatesJSON, "command-templates-json", opts.Runtime.CommandTemplatesJSON, "JSON command template list for live validations")
	cmd.Flags().StringVar(&opts.Runtime.CommandParserDir, "command-parser-dir", opts.Runtime.CommandParserDir, "Starlark command parser directory for live validations")
	cmd.Flags().DurationVar(&opts.Runtime.CommandDefaultTimeout, "command-timeout", opts.Runtime.CommandDefaultTimeout, "default command timeout for live validations")
	cmd.Flags().Int64Var(&opts.Runtime.CommandMaxOutputBytes, "command-max-output-bytes", opts.Runtime.CommandMaxOutputBytes, "default command output tail byte limit for live validations")
	cmd.Flags().BoolVar(&opts.RequireValidations, "require-validations", opts.RequireValidations, "fail when an agent package has no behavior validations")
	cmd.Flags().BoolVar(&opts.RequireAssertions, "require-assertions", opts.RequireAssertions, "fail when an agent behavior validation has no real assertions")
	cmd.Flags().BoolVar(&opts.RequireToolCalls, "require-tool-calls", opts.RequireToolCalls, "fail when an agent package has no validation proving or capturing tool selection")
	cmd.Flags().BoolVar(&opts.RequireToolContracts, "require-tool-contracts", opts.RequireToolContracts, "fail when agent validations reference tool calls not declared by the active tool config")
	cmd.Flags().StringVar(&opts.JUnitPath, "junit", opts.JUnitPath, "write JUnit XML validation results to this path")
	cmd.Flags().BoolVar(&opts.JSON, "json", opts.JSON, "write validation results as JSON")
	return cmd
}

// normalizeAgentValidationMode validates optional agent validation mode filters.
func normalizeAgentValidationMode(value string) (string, error) {
	switch strings.TrimSpace(value) {
	case "", "all":
		return "", nil
	case "mocked":
		return "mocked", nil
	case "live":
		return "live", nil
	default:
		return "", fmt.Errorf("agent validation mode must be all, mocked, or live")
	}
}

// returnAgentValidationSetupError writes CI artifacts for setup failures.
func returnAgentValidationSetupError(stdout io.Writer, opts agentValidationOptions, err error) error {
	if err == nil {
		return nil
	}
	path := opts.AgentPath
	if strings.TrimSpace(opts.AgentDir) != "" {
		path = opts.AgentDir
	}
	result := agentValidationFailureResult(path, err)
	if opts.JSON {
		if writeErr := json.NewEncoder(stdout).Encode(result); writeErr != nil {
			return fmt.Errorf("%w; additionally failed to write agent validation JSON: %v", err, writeErr)
		}
	}
	if opts.JUnitPath != "" {
		if writeErr := writeJUnitReport(opts.JUnitPath, agentValidationJUnit(result)); writeErr != nil {
			return fmt.Errorf("%w; additionally failed to write agent validation JUnit: %v", err, writeErr)
		}
	}
	return err
}

// agentValidationFailureResult stores a setup error as a package failure.
func agentValidationFailureResult(path string, err error) agentValidationResult {
	result := agentValidationResult{Agents: []agentValidationFileResult{}}
	addAgentValidationFileResult(&result, agentValidationFileResult{
		Path:  filepath.Clean(path),
		Error: err.Error(),
	})
	return result
}

// defaultAgentValidationRunner creates the production mocked or live runner.
func defaultAgentValidationRunner(ctx context.Context, opts agentValidationOptions) (*agentvalidation.Runner, func(), error) {
	if !opts.Live || opts.Mode == "mocked" {
		return agentvalidation.NewRunner(), nil, nil
	}
	host, err := app.NewAgentValidationHost(ctx, opts.Runtime)
	if err != nil {
		return nil, nil, err
	}
	return agentvalidation.NewRunnerWithHost(host), func() { _ = host.Close() }, nil
}

// runAgentValidationDirectory validates every agent config in one library tree.
func runAgentValidationDirectory(
	ctx context.Context,
	agentDir string,
	loader agentValidationLoader,
	runner *agentvalidation.Runner,
	validationIDs []string,
	mode string,
	requireValidations bool,
	requireAssertions bool,
) (agentValidationResult, error) {
	paths, err := agentConfigPaths(agentDir)
	if err != nil {
		return agentValidationResult{}, err
	}
	result := agentValidationResult{
		Agents: make([]agentValidationFileResult, 0, len(paths)),
	}
	found := map[string]bool{}
	for _, path := range paths {
		item := runAgentValidationFile(ctx, path, loader, runner, validationIDs, mode, requireValidations, requireAssertions)
		if len(validationIDs) > 0 && item.MissingSelection && item.Result.Total == 0 {
			continue
		}
		addAgentValidationFileResult(&result, item)
		for _, validation := range item.Result.Results {
			found[validation.ID] = true
		}
	}
	missingIDs := missingSelectedValidationIDs(validationIDs, found)
	if len(missingIDs) > 0 {
		err := agentvalidation.MissingValidationError{IDs: missingIDs}
		addAgentValidationFileResult(&result, agentValidationFileResult{
			Path:  filepath.Clean(agentDir),
			Error: err.Error(),
		})
		return result, err
	}
	return result, nil
}

// runAgentValidationFiles validates specific agent config files.
func runAgentValidationFiles(
	ctx context.Context,
	paths []string,
	loader agentValidationLoader,
	runner *agentvalidation.Runner,
	validationIDs []string,
	mode string,
	requireValidations bool,
	requireAssertions bool,
) agentValidationResult {
	result := agentValidationResult{
		Agents: make([]agentValidationFileResult, 0, len(paths)),
	}
	for _, path := range paths {
		item := runAgentValidationFile(ctx, path, loader, runner, validationIDs, mode, requireValidations, requireAssertions)
		addAgentValidationFileResult(&result, item)
	}
	return result
}

// addAgentValidationFileResult folds one agent package result into a summary.
func addAgentValidationFileResult(result *agentValidationResult, item agentValidationFileResult) {
	result.Total++
	result.ValidationTotal += item.Result.Total
	result.ValidationPassed += item.Result.Passed
	result.ValidationFailed += item.Result.Failed
	result.ValidationUnsupported += item.Result.Unsupported
	result.ToolCallReferences = mergeAgentToolCallReferences(result.ToolCallReferences, item.Result.ToolCallReferences)
	if item.Passed {
		result.Passed++
	} else if item.Unsupported {
		result.Unsupported++
	} else {
		result.Failed++
	}
	result.Agents = append(result.Agents, item)
}

// recountAgentValidationResult recomputes aggregate counters after strict gates.
func recountAgentValidationResult(result *agentValidationResult) {
	if result == nil {
		return
	}
	items := result.Agents
	result.Total = 0
	result.Passed = 0
	result.Failed = 0
	result.Unsupported = 0
	result.ValidationTotal = 0
	result.ValidationPassed = 0
	result.ValidationFailed = 0
	result.ValidationUnsupported = 0
	result.ToolCallReferences = nil
	result.Agents = make([]agentValidationFileResult, 0, len(items))
	for _, item := range items {
		item.Unsupported = item.Result.Unsupported > 0
		item.Passed = item.Error == "" && item.Result.Failed == 0 && item.Result.Unsupported == 0
		addAgentValidationFileResult(result, item)
	}
}

// markAgentValidationToolContractSetupError stores tool contract setup failures.
func markAgentValidationToolContractSetupError(result *agentValidationResult, err error) {
	if result == nil || err == nil {
		return
	}
	message := "tool contract setup failed: " + err.Error()
	if len(result.Agents) == 0 {
		addAgentValidationFileResult(result, agentValidationFileResult{
			Path:  "agent validation",
			Error: message,
		})
		return
	}
	for index := range result.Agents {
		result.Agents[index].Error = appendAgentValidationError(result.Agents[index].Error, message)
	}
	recountAgentValidationResult(result)
}

// applyAgentToolContractFailuresFromConfig validates agent calls against active tools.
func applyAgentToolContractFailuresFromConfig(
	result *agentValidationResult,
	toolPath string,
	explicit bool,
) error {
	tools, err := loadAgentToolContractConfig(toolPath, explicit)
	if err != nil {
		return err
	}
	available := agentToolCallSetForTools(*tools)
	contracts := toolvalidation.AgentToolContractsFor(*tools)
	applyAgentToolContractSetFailures(result, available, contracts)
	return nil
}

// loadAgentToolContractConfig loads contract metadata for direct agent checks.
func loadAgentToolContractConfig(toolPath string, explicit bool) (*schema.Tools, error) {
	if explicit {
		return config.LoadToolPackage(toolPath)
	}
	return config.LoadTools(toolPath, explicit)
}

// agentToolCallSetForTools collects callable ids from one active tool config.
func agentToolCallSetForTools(tools schema.Tools) map[string]struct{} {
	available := map[string]struct{}{}
	for _, id := range toolvalidation.AgentToolCallIDsFor(tools) {
		if trimmed := strings.TrimSpace(id); trimmed != "" {
			available[trimmed] = struct{}{}
		}
	}
	return available
}

// applyAgentToolContractSetFailures fails agent cases with unknown or bad calls.
func applyAgentToolContractSetFailures(
	result *agentValidationResult,
	available map[string]struct{},
	contracts map[string]toolvalidation.AgentToolContract,
) {
	if result == nil {
		return
	}
	for index := range result.Agents {
		item := &result.Agents[index]
		unknown := markUnknownAgentToolCalls(&item.Result, available)
		if len(unknown) > 0 {
			item.UnknownToolCalls = append(item.UnknownToolCalls, unknown...)
		}
		invalidArguments := markInvalidAgentToolArguments(&item.Result, contracts)
		if len(invalidArguments) > 0 {
			item.InvalidToolArgs = append(item.InvalidToolArgs, invalidArguments...)
		}
	}
	recountAgentValidationResult(result)
}

// runAgentValidationFile loads and validates one agent config file.
func runAgentValidationFile(
	ctx context.Context,
	path string,
	loader agentValidationLoader,
	runner *agentvalidation.Runner,
	validationIDs []string,
	mode string,
	requireValidations bool,
	requireAssertions bool,
) agentValidationFileResult {
	item := agentValidationFileResult{Path: path}
	agent, err := loader(path)
	if err != nil {
		item.Error = err.Error()
		return item
	}
	item.Name = strings.TrimSpace(agent.Name)
	if runner == nil {
		runner = agentvalidation.NewRunner()
	}
	suite, err := runner.RunSelectedModes(ctx, agent, validationIDs, mode)
	item.Result = suite
	if err != nil {
		var missing agentvalidation.MissingValidationError
		if errors.As(err, &missing) {
			item.MissingSelection = true
		}
		item.Error = err.Error()
	}
	if requireValidations && suite.Total == 0 {
		item.Error = appendAgentValidationError(item.Error, "agent has no behavior validations")
	}
	if requireAssertions {
		item.MissingAssertions = markAgentValidationMissingAssertions(&suite, agent.Validations, validationIDs, mode)
		item.Result = suite
	}
	item.Unsupported = suite.Unsupported > 0
	item.Passed = item.Error == "" && suite.Failed == 0 && suite.Unsupported == 0
	return item
}

// markAgentValidationMissingAssertions fails passing cases with no configured checks.
func markAgentValidationMissingAssertions(
	suite *agentvalidation.SuiteResult,
	validations []schema.AgentValidation,
	validationIDs []string,
	mode string,
) []string {
	if suite == nil || len(suite.Results) == 0 {
		return nil
	}
	missingByID := agentValidationsWithoutAssertions(validations, validationIDs, mode)
	if len(missingByID) == 0 {
		return nil
	}
	missing := make([]string, 0)
	for index := range suite.Results {
		id := strings.TrimSpace(suite.Results[index].ID)
		name, ok := missingByID[id]
		if !ok {
			continue
		}
		missing = append(missing, name)
		suite.Results[index].Assertions = append(suite.Results[index].Assertions, agentvalidation.AssertionResult{
			Type:    "required-assertion",
			Passed:  false,
			Message: "agent validation has no real assertions",
		})
		if suite.Results[index].Status == agentvalidation.StatusPassed {
			suite.Results[index].Status = agentvalidation.StatusFailed
		}
	}
	if len(missing) == 0 {
		return nil
	}
	recountAgentValidationSuite(suite)
	return missing
}

// agentValidationsWithoutAssertions returns selected cases lacking checks.
func agentValidationsWithoutAssertions(
	validations []schema.AgentValidation,
	validationIDs []string,
	mode string,
) map[string]string {
	selected := selectedAgentValidationIDSet(validationIDs)
	modeFilter := agentValidationModeFilterForMatch(mode)
	missing := map[string]string{}
	for _, validation := range validations {
		id := strings.TrimSpace(validation.ID)
		if id == "" {
			continue
		}
		if modeFilter != "" && agentValidationStoredModeForMatch(validation.Mode) != modeFilter {
			continue
		}
		if len(selected) > 0 {
			if _, ok := selected[id]; !ok {
				continue
			}
		}
		if agentValidationHasConfiguredAssertion(validation) {
			continue
		}
		missing[id] = firstNonEmptyAgentValidationValue(id, validation.Label)
	}
	return missing
}

// agentValidationModeFilterForMatch normalizes an optional mode gate.
func agentValidationModeFilterForMatch(value string) string {
	switch strings.TrimSpace(value) {
	case "mocked":
		return "mocked"
	case "live":
		return "live"
	default:
		return ""
	}
}

// agentValidationStoredModeForMatch normalizes stored validation modes.
func agentValidationStoredModeForMatch(value string) string {
	switch strings.TrimSpace(value) {
	case "live":
		return "live"
	default:
		return "mocked"
	}
}

// selectedAgentValidationIDSet normalizes selected validation IDs for lookup.
func selectedAgentValidationIDSet(validationIDs []string) map[string]struct{} {
	selected := map[string]struct{}{}
	for _, value := range validationIDs {
		id := strings.TrimSpace(value)
		if id == "" {
			continue
		}
		selected[id] = struct{}{}
	}
	if len(selected) == 0 {
		return nil
	}
	return selected
}

// agentValidationHasConfiguredAssertion reports whether config asserts behavior.
func agentValidationHasConfiguredAssertion(validation schema.AgentValidation) bool {
	if len(validation.Assertions) > 0 {
		return true
	}
	for key, value := range validation.Expected {
		switch strings.TrimSpace(key) {
		case "response_contains", "tool_call":
			if strings.TrimSpace(fmt.Sprint(value)) != "" {
				return true
			}
		default:
			continue
		}
	}
	return false
}

// recountAgentValidationSuite recomputes package counters after CLI gates.
func recountAgentValidationSuite(suite *agentvalidation.SuiteResult) {
	suite.Total = len(suite.Results)
	suite.Passed = 0
	suite.Failed = 0
	suite.Unsupported = 0
	for _, result := range suite.Results {
		switch result.Status {
		case agentvalidation.StatusPassed:
			suite.Passed++
		case agentvalidation.StatusUnsupported:
			suite.Unsupported++
		default:
			suite.Failed++
		}
	}
}

// agentConfigPaths finds package-shaped and collection-shaped agent configs.
func agentConfigPaths(agentDir string) ([]string, error) {
	if agentDir == "" {
		return nil, fmt.Errorf("agent package directory is required")
	}
	var paths []string
	root := filepath.Clean(agentDir)
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
		if isAgentConfigPath(path, root, entry.Name()) {
			paths = append(paths, path)
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	sort.Strings(paths)
	if len(paths) == 0 {
		return nil, fmt.Errorf("no agent config files found under %s", agentDir)
	}
	return paths, nil
}

// isAgentConfigPath reports whether path is a package or collection agent config.
func isAgentConfigPath(path string, root string, filename string) bool {
	if filename == schema.DefaultAgentFilename {
		return true
	}
	if filepath.Dir(path) != root {
		return false
	}
	return isAgentConfigFilename(filename)
}

// isAgentConfigFilename reports whether filename uses a supported config extension.
func isAgentConfigFilename(filename string) bool {
	lower := strings.ToLower(filename)
	return strings.HasSuffix(lower, ".yaml") ||
		strings.HasSuffix(lower, ".yml") ||
		strings.HasSuffix(lower, ".json")
}

// writeAgentValidationSummary writes a compact human-readable validation report.
func writeAgentValidationSummary(stdout io.Writer, result agentValidationResult) error {
	if _, err := fmt.Fprintf(
		stdout,
		"Agent validations: total=%d passed=%d failed=%d unsupported=%d cases=%d passed=%d failed=%d unsupported=%d\n",
		result.Total,
		result.Passed,
		result.Failed,
		result.Unsupported,
		result.ValidationTotal,
		result.ValidationPassed,
		result.ValidationFailed,
		result.ValidationUnsupported,
	); err != nil {
		return err
	}
	if len(result.ToolCallReferences) > 0 {
		if _, err := fmt.Fprintf(stdout, "agent tool calls: %s\n", strings.Join(result.ToolCallReferences, ", ")); err != nil {
			return err
		}
	}
	for _, item := range result.Agents {
		if err := writeAgentValidationFileSummary(stdout, item); err != nil {
			return err
		}
	}
	return nil
}

// writeAgentValidationFileSummary writes one agent package validation line.
func writeAgentValidationFileSummary(stdout io.Writer, item agentValidationFileResult) error {
	status := "failed"
	if item.Passed {
		status = "passed"
	}
	if _, err := fmt.Fprintf(stdout, "%s %s", status, item.Path); err != nil {
		return err
	}
	if item.Name != "" {
		if _, err := fmt.Fprintf(stdout, " - %s", item.Name); err != nil {
			return err
		}
	}
	if item.Error != "" {
		if _, err := fmt.Fprintf(stdout, " - %s", item.Error); err != nil {
			return err
		}
	}
	if len(item.MissingAssertions) > 0 {
		if _, err := fmt.Fprintf(stdout, " - agent validations without assertions: %s", strings.Join(item.MissingAssertions, ", ")); err != nil {
			return err
		}
	}
	if len(item.MissingToolCalls) > 0 {
		if _, err := fmt.Fprintf(stdout, " - agent validations without tool calls: %s", strings.Join(item.MissingToolCalls, ", ")); err != nil {
			return err
		}
	}
	if len(item.UnknownToolCalls) > 0 {
		if _, err := fmt.Fprintf(stdout, " - agent validations with unknown tool calls: %s", strings.Join(item.UnknownToolCalls, ", ")); err != nil {
			return err
		}
	}
	if len(item.InvalidToolArgs) > 0 {
		if _, err := fmt.Fprintf(stdout, " - agent validations with invalid tool arguments: %s", strings.Join(item.InvalidToolArgs, ", ")); err != nil {
			return err
		}
	}
	if len(item.Result.ToolCallReferences) > 0 {
		if _, err := fmt.Fprintf(stdout, " - tool calls: %s", strings.Join(item.Result.ToolCallReferences, ", ")); err != nil {
			return err
		}
	}
	if item.Result.Total > 0 {
		if _, err := fmt.Fprintf(
			stdout,
			": validations=%d passed=%d failed=%d unsupported=%d",
			item.Result.Total,
			item.Result.Passed,
			item.Result.Failed,
			item.Result.Unsupported,
		); err != nil {
			return err
		}
	}
	if _, err := fmt.Fprintln(stdout); err != nil {
		return err
	}
	return nil
}

// mergeAgentToolCallReferences appends unique agent tool-call references.
func mergeAgentToolCallReferences(existing []string, next []string) []string {
	if len(next) == 0 {
		return existing
	}
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

// agentValidationJUnit converts agent validation results to JUnit XML.
func agentValidationJUnit(result agentValidationResult) junitSuites {
	report := junitSuites{
		Name:   "agent-validations",
		Suites: make([]junitSuite, 0, len(result.Agents)),
	}
	for _, item := range result.Agents {
		report.Suites = append(report.Suites, agentValidationJUnitSuite(item))
	}
	return finalizeJUnit(report)
}

// agentValidationJUnitSuite converts one agent result to a JUnit suite.
func agentValidationJUnitSuite(item agentValidationFileResult) junitSuite {
	name := strings.TrimSpace(item.Path)
	if name == "" {
		name = "agent"
	}
	testCases := []junitCase{{Name: "agent.load", ClassName: name}}
	if !item.Passed {
		if item.Result.Total == 0 {
			testCases[0].Failure = &junitFailure{
				Message: "agent validation failed",
				Text:    item.Error,
			}
		} else if item.Error != "" {
			testCases = append(testCases, junitCase{
				Name:      "agent.validations.required",
				ClassName: name,
				Failure: &junitFailure{
					Message: "agent validation failed",
					Text:    item.Error,
				},
			})
		}
	}
	for _, result := range item.Result.Results {
		testCases = append(testCases, junitCaseForAgentValidation(name, result))
	}
	return finalizeJUnitSuite(junitSuite{
		Name:      name,
		TestCases: testCases,
	})
}

// junitCaseForAgentValidation converts one agent validation result to a test case.
func junitCaseForAgentValidation(className string, result agentvalidation.Result) junitCase {
	name := strings.TrimSpace(result.ID)
	if name == "" {
		name = strings.TrimSpace(result.Label)
	}
	if name == "" {
		name = "validation"
	}
	item := junitCase{Name: name, ClassName: className}
	switch result.Status {
	case agentvalidation.StatusPassed:
		return item
	case agentvalidation.StatusUnsupported:
		item.Skipped = &junitSkipped{
			Message: "validation unsupported",
			Text:    agentValidationJUnitResultMessage(result),
		}
	default:
		item.Failure = &junitFailure{
			Message: "validation failed",
			Text:    agentValidationJUnitResultMessage(result),
		}
	}
	return item
}

// agentValidationJUnitResultMessage returns diagnostics and assertion details.
func agentValidationJUnitResultMessage(result agentvalidation.Result) string {
	var parts []string
	if mode := strings.TrimSpace(result.Mode); mode != "" {
		parts = append(parts, "mode: "+mode)
	}
	if prompt := strings.TrimSpace(result.Prompt); prompt != "" {
		parts = append(parts, "prompt: "+prompt)
	}
	if result.Response != nil {
		if text := strings.TrimSpace(result.Response.Text); text != "" {
			parts = append(parts, "response: "+text)
		}
		for _, ref := range agentvalidation.ToolCallReferencesFor([]agentvalidation.Result{result}) {
			parts = append(parts, "tool-contract: "+ref)
		}
		for _, call := range result.Response.ToolCalls {
			name := firstNonEmptyAgentValidationValue(call.ID, call.Name)
			if name == "" {
				name = "tool-call"
			}
			detail := "tool-call: " + name
			if len(call.Arguments) > 0 {
				detail += " arguments=" + agentValidationJUnitJSON(call.Arguments)
			}
			parts = append(parts, detail)
		}
		if result.Response.Output != nil {
			parts = append(parts, "output: "+agentValidationJUnitJSON(result.Response.Output))
		}
	}
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

// firstNonEmptyAgentValidationValue returns the first non-empty display value.
func firstNonEmptyAgentValidationValue(values ...string) string {
	for _, value := range values {
		if trimmed := strings.TrimSpace(value); trimmed != "" {
			return trimmed
		}
	}
	return ""
}

// agentValidationJUnitJSON returns compact JSON for structured JUnit evidence.
func agentValidationJUnitJSON(value any) string {
	encoded, err := json.Marshal(value)
	if err != nil {
		return fmt.Sprint(value)
	}
	return string(encoded)
}

// appendAgentValidationError combines validation error text.
func appendAgentValidationError(current string, next string) string {
	if strings.TrimSpace(current) == "" {
		return strings.TrimSpace(next)
	}
	if strings.TrimSpace(next) == "" {
		return strings.TrimSpace(current)
	}
	return strings.TrimSpace(current) + "; " + strings.TrimSpace(next)
}
