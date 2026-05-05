// This file implements configured local command alias tools.
package localexec

import (
	"context"
	"fmt"
	"sort"
	"strings"

	"agent-awesome.com/harnessinternal/config/schema"
	"agent-awesome.com/harnessinternal/tools/localexec/execspec"
	"agent-awesome.com/harnessinternal/tools/localexec/requestcommand"
	"google.golang.org/adk/tool"
	"google.golang.org/adk/tool/functiontool"
)

// This file implements configured local command aliases. Arbitrary reviewed
// commands live in request_command.go.

// ToolName is the configured-command local execution tool name.
const ToolName = "local_exec"

// Input is the JSON payload accepted by the local_exec tool.
type Input struct {
	Command string `json:"command"`       // configured command alias to run
	CWD     string `json:"cwd,omitempty"` // optional working directory under an allowed root
	Stdin   string `json:"stdin,omitempty"`
}

// runner holds normalized local-exec config and the command alias index.
type runner struct {
	catalog commandCatalog
}

// NewTool creates the configured-command local_exec tool.
func NewTool(cfg schema.LocalExec) (tool.Tool, error) {
	r, err := newRunner(cfg)
	if err != nil {
		return nil, err
	}
	return functiontool.New(functiontool.Config{
		Name:        ToolName,
		Description: r.description(),
	}, r.run)
}

// NewTools returns all local execution tools enabled by the tools schema.
func NewTools(cfg *schema.Tools) ([]tool.Tool, error) {
	if cfg == nil || !cfg.LocalExec.Enabled {
		return nil, nil
	}
	t, err := NewTool(cfg.LocalExec)
	if err != nil {
		return nil, err
	}
	requestTool, err := requestcommand.NewTool(cfg.LocalExec, processExecutor{})
	if err != nil {
		return nil, err
	}
	return []tool.Tool{t, requestTool}, nil
}

// newRunner normalizes configured command names and executables into a lookup
// map used while serving tool calls.
func newRunner(cfg schema.LocalExec) (*runner, error) {
	return &runner{
		catalog: newCommandCatalog(cfg),
	}, nil
}

// description builds the model-facing description listing every configured
// command alias the agent may request.
func (r *runner) description() string {
	names := make([]string, 0, len(r.catalog.commands))
	for name := range r.catalog.commands {
		names = append(names, name)
	}
	sort.Strings(names)

	var b strings.Builder
	b.WriteString("Run one allowlisted local OS command by configured alias. Available commands:")
	for _, name := range names {
		command := r.catalog.commands[name]
		b.WriteString("\n- ")
		b.WriteString(name)
		b.WriteString(": ")
		b.WriteString(strings.TrimSpace(command.Description))
	}
	return b.String()
}

// run handles one local_exec invocation, asking for confirmation when the
// command is not covered by config-level approval rules.
func (r *runner) run(ctx tool.Context, input Input) (execspec.Output, error) {
	return r.runWithConfirmation(ctx, input)
}

// runWithConfirmation contains the local_exec workflow behind the narrow
// confirmation interface used by the ADK adapter.
func (r *runner) runWithConfirmation(ctx confirmationRequester, input Input) (execspec.Output, error) {
	if r.requiresConfirmation(input) {
		confirmation := ctx.ToolConfirmation()
		if confirmation == nil {
			if err := ctx.RequestConfirmation(r.confirmationHint(input), r.confirmationPayload(input)); err != nil {
				return execspec.Output{}, err
			}
			return execspec.Output{}, nil
		}
		if !confirmation.Confirmed {
			return execspec.Output{}, fmt.Errorf("user denied local_exec command %q", strings.TrimSpace(input.Command))
		}
	}
	return r.execute(ctx, input)
}

// execute validates the requested alias, resolves its working directory, and
// runs the configured command with the applicable timeout/output limits.
func (r *runner) execute(ctx context.Context, input Input) (execspec.Output, error) {
	call, err := r.catalog.configuredToolCall(input)
	if err != nil {
		return execspec.Output{}, err
	}
	return processExecutor{}.Execute(ctx, call)
}
