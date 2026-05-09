// This file tests reviewed arbitrary command proposals.
package requestcommand

import (
	"bytes"
	"context"
	"errors"
	"os"
	"os/exec"
	"strings"
	"testing"

	"agentawesome/internal/config/schema"
	"agentawesome/internal/tools/localexec/execspec"
	"google.golang.org/adk/tool/toolconfirmation"
)

func TestMain(m *testing.M) {
	dir, err := os.MkdirTemp("", "agent-awesome-localexec-test-")
	if err != nil {
		panic(err)
	}
	_ = os.Setenv("XDG_CONFIG_HOME", dir)
	code := m.Run()
	_ = os.RemoveAll(dir)
	os.Exit(code)
}

func TestRequestCommandRequestsReviewWithoutExecuting(t *testing.T) {
	root := t.TempDir()
	t.Chdir(root)
	requestTool := newRequestCommandToolForTest()
	ctx := newFakeToolContext(nil)

	got, err := requestTool.runWithConfirmation(ctx, RequestCommandInput{
		Executable: "printf",
		Args:       []string{"hello"},
		CWD:        ".",
		Reason:     "Print a test value.",
		Risk:       "read_only",
	})
	if err != nil {
		t.Fatalf("run() error = %v", err)
	}
	if got.Status != "pending_review" || got.Result != nil {
		t.Fatalf("run() = %#v, want pending review without result", got)
	}
	if ctx.requestCount != 1 {
		t.Fatalf("RequestConfirmation count = %d, want 1", ctx.requestCount)
	}
	if !strings.Contains(ctx.hint, "The agent wants to run:") || !strings.Contains(ctx.hint, "printf hello") {
		t.Fatalf("confirmation hint = %q, want rendered command", ctx.hint)
	}

	payload, ok := ctx.payload.(ReviewRequestPayload)
	if !ok {
		t.Fatalf("confirmation payload = %T, want ReviewRequestPayload", ctx.payload)
	}
	if payload.Proposal.Executable != "printf" || payload.Proposal.CommandLine != "printf hello" {
		t.Fatalf("payload proposal = %#v, want printf proposal", payload.Proposal)
	}
	if got, want := optionActions(payload.Options), []string{
		"deny",
		"approve_once",
		"always_exact_session",
		"always_prefix_session",
		"always_tool_session",
	}; strings.Join(got, ",") != strings.Join(want, ",") {
		t.Fatalf("option actions = %#v, want %#v", got, want)
	}
	if payload.PersistentApprovals.Enabled {
		t.Fatalf("PersistentApprovals.Enabled = true, want false")
	}
	if !strings.Contains(ctx.hint, "Persistent approvals") || !strings.Contains(ctx.hint, "disabled") {
		t.Fatalf("confirmation hint = %q, want disabled persistent approval state", ctx.hint)
	}
}

func TestRequestCommandPersistentOptionsRequireExplicitConfig(t *testing.T) {
	root := t.TempDir()
	t.Chdir(root)
	requestTool := newRequestCommandToolForTestWithConfig(requestCommandTestConfig(true))
	ctx := newFakeToolContext(nil)

	got, err := requestTool.runWithConfirmation(ctx, RequestCommandInput{
		Executable: "printf",
		Args:       []string{"hello"},
		CWD:        ".",
		Reason:     "Print a test value.",
		Risk:       "read_only",
	})
	if err != nil {
		t.Fatalf("run() error = %v", err)
	}
	if got.Status != "pending_review" {
		t.Fatalf("status = %q, want pending_review", got.Status)
	}

	payload, ok := ctx.payload.(ReviewRequestPayload)
	if !ok {
		t.Fatalf("confirmation payload = %T, want ReviewRequestPayload", ctx.payload)
	}
	if !payload.PersistentApprovals.Enabled {
		t.Fatalf("PersistentApprovals.Enabled = false, want true")
	}
	if payload.PersistentApprovals.WorkspacePolicyPath == "" {
		t.Fatalf("WorkspacePolicyPath = empty, want policy path")
	}
	if got, want := optionActions(payload.Options), []string{
		"deny",
		"approve_once",
		"always_exact_session",
		"always_prefix_session",
		"always_tool_session",
		"always_exact_workspace",
		"always_prefix_workspace",
		"always_tool_workspace",
		"always_tool",
	}; strings.Join(got, ",") != strings.Join(want, ",") {
		t.Fatalf("option actions = %#v, want %#v", got, want)
	}
	if !strings.Contains(ctx.hint, "enabled") || !strings.Contains(ctx.hint, "Workspace policy file") {
		t.Fatalf("confirmation hint = %q, want enabled persistent approval state", ctx.hint)
	}
}

func TestRequestCommandReviewIncludesStdin(t *testing.T) {
	root := t.TempDir()
	t.Chdir(root)
	requestTool := newRequestCommandToolForTest()
	ctx := newFakeToolContext(nil)

	got, err := requestTool.runWithConfirmation(ctx, RequestCommandInput{
		Executable: "sh",
		Args:       []string{"-s"},
		CWD:        ".",
		Stdin:      "echo reviewed",
		Reason:     "Run a reviewed script.",
		Risk:       "executes stdin",
	})
	if err != nil {
		t.Fatalf("run() error = %v", err)
	}
	if got.Status != "pending_review" {
		t.Fatalf("status = %q, want pending_review", got.Status)
	}
	if !strings.Contains(ctx.hint, "Stdin") || !strings.Contains(ctx.hint, "echo reviewed") {
		t.Fatalf("confirmation hint = %q, want stdin preview", ctx.hint)
	}

	payload, ok := ctx.payload.(ReviewRequestPayload)
	if !ok {
		t.Fatalf("confirmation payload = %T, want ReviewRequestPayload", ctx.payload)
	}
	if payload.Proposal.Stdin != "echo reviewed" {
		t.Fatalf("payload proposal stdin = %q, want echo reviewed", payload.Proposal.Stdin)
	}
}

func TestRequestCommandProposalQuotesDisplayedArgs(t *testing.T) {
	proposal := newProposal(RequestCommandInput{
		Executable: "jq",
		Args:       []string{".items[] | {name, version}", "data.json"},
		CWD:        ".",
		Reason:     "Inspect JSON.",
		Risk:       "read_only",
	})

	if got, want := proposal.CommandLine, "jq '.items[] | {name, version}' data.json"; got != want {
		t.Fatalf("command line = %q, want %q", got, want)
	}
}

func TestRequestCommandApproveOnceExecutesReviewedCommand(t *testing.T) {
	root := t.TempDir()
	t.Chdir(root)
	requestTool := newRequestCommandToolForTest()
	ctx := newFakeToolContext(&toolconfirmation.ToolConfirmation{
		Confirmed: true,
		Payload:   ReviewDecision{Action: "approve_once"},
	})

	got, err := requestTool.runWithConfirmation(ctx, RequestCommandInput{
		Executable: "printf",
		Args:       []string{"hello"},
		CWD:        ".",
		Reason:     "Print a test value.",
		Risk:       "read_only",
	})
	if err != nil {
		t.Fatalf("run() error = %v", err)
	}
	if got.Status != "executed" || got.Result == nil || got.Result.Stdout != "hello" {
		t.Fatalf("run() = %#v, want executed hello output", got)
	}
	if ctx.requestCount != 0 {
		t.Fatalf("RequestConfirmation count = %d, want 0 when confirmation is already present", ctx.requestCount)
	}
}

func TestRequestCommandAlwaysExactSessionSkipsLaterReview(t *testing.T) {
	root := t.TempDir()
	t.Chdir(root)
	requestTool := newRequestCommandToolForTest()
	input := RequestCommandInput{
		Executable: "printf",
		Args:       []string{"hello"},
		CWD:        ".",
		Reason:     "Print a test value.",
		Risk:       "read_only",
	}

	first, err := requestTool.runWithConfirmation(newFakeToolContext(&toolconfirmation.ToolConfirmation{
		Confirmed: true,
		Payload:   map[string]any{"action": "always_exact_session"},
	}), input)
	if err != nil {
		t.Fatalf("first run() error = %v", err)
	}
	if first.Status != "executed" {
		t.Fatalf("first status = %q, want executed", first.Status)
	}

	ctx := newFakeToolContext(nil)
	second, err := requestTool.runWithConfirmation(ctx, input)
	if err != nil {
		t.Fatalf("second run() error = %v", err)
	}
	if second.Status != "executed" || second.Result == nil || second.Result.Stdout != "hello" {
		t.Fatalf("second run() = %#v, want remembered execution", second)
	}
	if ctx.requestCount != 0 {
		t.Fatalf("RequestConfirmation count = %d, want 0 after session approval", ctx.requestCount)
	}
}

func TestRequestCommandAlwaysExactWorkspaceSkipsLaterReview(t *testing.T) {
	root := t.TempDir()
	t.Chdir(root)
	input := RequestCommandInput{
		Executable: "printf",
		Args:       []string{"hello"},
		CWD:        ".",
		Reason:     "Print a test value.",
		Risk:       "read_only",
	}

	firstTool := newRequestCommandToolForTestWithConfig(requestCommandTestConfig(true))
	first, err := firstTool.runWithConfirmation(newFakeToolContext(&toolconfirmation.ToolConfirmation{
		Confirmed: true,
		Payload:   ReviewDecision{Action: "always_exact_workspace"},
	}), input)
	if err != nil {
		t.Fatalf("first run() error = %v", err)
	}
	if first.Status != "executed" {
		t.Fatalf("first status = %q, want executed", first.Status)
	}
	policies, err := loadWorkspacePolicies(root)
	if err != nil {
		t.Fatalf("loadWorkspacePolicies() error = %v", err)
	}
	if len(policies.Exact) != 1 {
		t.Fatalf("workspace exact approvals = %#v, want one approval", policies.Exact)
	}
	approval := policies.Exact[0]
	if approval.Executable != "printf" || strings.Join(approval.Args, ",") != "hello" || approval.CWD != "." || approval.CommandLine != "printf hello" {
		t.Fatalf("workspace approval = %#v, want stored command details", approval)
	}

	secondTool := newRequestCommandToolForTestWithConfig(requestCommandTestConfig(true))
	ctx := newFakeToolContext(nil)
	second, err := secondTool.runWithConfirmation(ctx, input)
	if err != nil {
		t.Fatalf("second run() error = %v", err)
	}
	if second.Status != "executed" || second.Result == nil || second.Result.Stdout != "hello" {
		t.Fatalf("second run() = %#v, want workspace-approved execution", second)
	}
	if ctx.requestCount != 0 {
		t.Fatalf("RequestConfirmation count = %d, want 0 after workspace approval", ctx.requestCount)
	}
}

func TestRequestCommandRejectsPersistentDecisionWhenDisabled(t *testing.T) {
	root := t.TempDir()
	t.Chdir(root)
	requestTool := newRequestCommandToolForTest()

	got, err := requestTool.runWithConfirmation(newFakeToolContext(&toolconfirmation.ToolConfirmation{
		Confirmed: true,
		Payload:   ReviewDecision{Action: "always_exact_workspace"},
	}), RequestCommandInput{
		Executable: "printf",
		Args:       []string{"hello"},
		CWD:        ".",
		Reason:     "Print a test value.",
		Risk:       "read_only",
	})
	if err == nil || !strings.Contains(err.Error(), "allow-persistent-approvals") {
		t.Fatalf("run() error = %v, want persistent approval config error", err)
	}
	if got.Status != "error" {
		t.Fatalf("status = %q, want error", got.Status)
	}
	policies, err := loadWorkspacePolicies(root)
	if err != nil {
		t.Fatalf("loadWorkspacePolicies() error = %v", err)
	}
	if len(policies.Exact) != 0 {
		t.Fatalf("workspace exact approvals = %#v, want none", policies.Exact)
	}
}

func TestRequestCommandPersistentApprovalIgnoredWhenDisabled(t *testing.T) {
	root := t.TempDir()
	t.Chdir(root)
	err := updateWorkspacePolicies(root, func(policies *workspacePolicies) {
		policies.Exact = appendUniqueExact(policies.Exact, newProposal(RequestCommandInput{
			Executable: "printf",
			Args:       []string{"stored"},
			CWD:        ".",
			Reason:     "Print stored.",
			Risk:       "read_only",
		}))
	})
	if err != nil {
		t.Fatalf("updateWorkspacePolicies() error = %v", err)
	}

	requestTool := newRequestCommandToolForTest()
	ctx := newFakeToolContext(nil)
	got, err := requestTool.runWithConfirmation(ctx, RequestCommandInput{
		Executable: "printf",
		Args:       []string{"stored"},
		CWD:        ".",
		Reason:     "Print stored.",
		Risk:       "read_only",
	})
	if err != nil {
		t.Fatalf("run() error = %v", err)
	}
	if got.Status != "pending_review" {
		t.Fatalf("status = %q, want pending_review", got.Status)
	}
	if ctx.requestCount != 1 {
		t.Fatalf("RequestConfirmation count = %d, want review when persistent approvals are disabled", ctx.requestCount)
	}
}

func TestRequestCommandWorkspaceExactApprovalCanBeEdited(t *testing.T) {
	root := t.TempDir()
	t.Chdir(root)
	err := updateWorkspacePolicies(root, func(policies *workspacePolicies) {
		policies.Exact = append(policies.Exact, workspaceExactApproval{
			Executable:  "printf",
			Args:        []string{"edited"},
			CWD:         ".",
			CommandLine: "printf edited",
		})
	})
	if err != nil {
		t.Fatalf("updateWorkspacePolicies() error = %v", err)
	}

	requestTool := newRequestCommandToolForTestWithConfig(requestCommandTestConfig(true))
	ctx := newFakeToolContext(nil)
	got, err := requestTool.runWithConfirmation(ctx, RequestCommandInput{
		Executable: "printf",
		Args:       []string{"edited"},
		CWD:        ".",
		Reason:     "Print an edited approval.",
		Risk:       "read_only",
	})
	if err != nil {
		t.Fatalf("run() error = %v", err)
	}
	if got.Status != "executed" || got.Result == nil || got.Result.Stdout != "edited" {
		t.Fatalf("run() = %#v, want edited workspace approval", got)
	}
	if ctx.requestCount != 0 {
		t.Fatalf("RequestConfirmation count = %d, want 0 for edited workspace approval", ctx.requestCount)
	}
}

func TestRequestCommandAlwaysPrefixSessionSkipsMatchingLaterReview(t *testing.T) {
	root := t.TempDir()
	t.Chdir(root)
	requestTool := newRequestCommandToolForTest()

	first, err := requestTool.runWithConfirmation(newFakeToolContext(&toolconfirmation.ToolConfirmation{
		Confirmed: true,
		Payload:   ReviewDecision{Action: "always_prefix_session"},
	}), RequestCommandInput{
		Executable: "echo",
		Args:       []string{"first"},
		CWD:        ".",
		Reason:     "Print a test value.",
		Risk:       "read_only",
	})
	if err != nil {
		t.Fatalf("first run() error = %v", err)
	}
	if first.Status != "executed" {
		t.Fatalf("first status = %q, want executed", first.Status)
	}

	ctx := newFakeToolContext(nil)
	second, err := requestTool.runWithConfirmation(ctx, RequestCommandInput{
		Executable: "echo",
		Args:       []string{"first", "again"},
		CWD:        ".",
		Reason:     "Print another value.",
		Risk:       "read_only",
	})
	if err != nil {
		t.Fatalf("second run() error = %v", err)
	}
	if second.Status != "executed" || second.Result == nil || strings.TrimSpace(second.Result.Stdout) != "first again" {
		t.Fatalf("second run() = %#v, want prefix-approved execution", second)
	}
	if ctx.requestCount != 0 {
		t.Fatalf("RequestConfirmation count = %d, want 0 after prefix approval", ctx.requestCount)
	}
}

func TestRequestCommandRejectsBroadenedPrefixDecision(t *testing.T) {
	root := t.TempDir()
	t.Chdir(root)
	requestTool := newRequestCommandToolForTest()

	got, err := requestTool.runWithConfirmation(newFakeToolContext(&toolconfirmation.ToolConfirmation{
		Confirmed: true,
		Payload: ReviewDecision{
			Action: "always_prefix_session",
			Prefix: "echo",
		},
	}), RequestCommandInput{
		Executable: "echo",
		Args:       []string{"first"},
		CWD:        ".",
		Reason:     "Print a test value.",
		Risk:       "read_only",
	})
	if err == nil || !strings.Contains(err.Error(), "must match the reviewed command line") {
		t.Fatalf("run() error = %v, want broadened prefix rejection", err)
	}
	if got.Status != "error" {
		t.Fatalf("status = %q, want error", got.Status)
	}
}

func TestRequestCommandAlwaysToolSessionSkipsLaterReview(t *testing.T) {
	root := t.TempDir()
	t.Chdir(root)
	requestTool := newRequestCommandToolForTest()

	first, err := requestTool.runWithConfirmation(newFakeToolContext(&toolconfirmation.ToolConfirmation{
		Confirmed: true,
		Payload:   ReviewDecision{Action: "always_tool_session"},
	}), RequestCommandInput{
		Executable: "printf",
		Args:       []string{"first"},
		CWD:        ".",
		Reason:     "Print a test value.",
		Risk:       "read_only",
	})
	if err != nil {
		t.Fatalf("first run() error = %v", err)
	}
	if first.Status != "executed" {
		t.Fatalf("first status = %q, want executed", first.Status)
	}

	ctx := newFakeToolContext(nil)
	second, err := requestTool.runWithConfirmation(ctx, RequestCommandInput{
		Executable: "printf",
		Args:       []string{"second"},
		CWD:        ".",
		Reason:     "Print another value.",
		Risk:       "read_only",
	})
	if err != nil {
		t.Fatalf("second run() error = %v", err)
	}
	if second.Status != "executed" || second.Result == nil || second.Result.Stdout != "second" {
		t.Fatalf("second run() = %#v, want tool-approved execution", second)
	}
	if ctx.requestCount != 0 {
		t.Fatalf("RequestConfirmation count = %d, want 0 after tool approval", ctx.requestCount)
	}
}

func TestRequestCommandToolApprovalDoesNotSkipStdinReview(t *testing.T) {
	root := t.TempDir()
	t.Chdir(root)
	requestTool := newRequestCommandToolForTest()

	first, err := requestTool.runWithConfirmation(newFakeToolContext(&toolconfirmation.ToolConfirmation{
		Confirmed: true,
		Payload:   ReviewDecision{Action: "always_tool_session"},
	}), RequestCommandInput{
		Executable: "printf",
		Args:       []string{"first"},
		CWD:        ".",
		Reason:     "Print a test value.",
		Risk:       "read_only",
	})
	if err != nil {
		t.Fatalf("first run() error = %v", err)
	}
	if first.Status != "executed" {
		t.Fatalf("first status = %q, want executed", first.Status)
	}

	ctx := newFakeToolContext(nil)
	second, err := requestTool.runWithConfirmation(ctx, RequestCommandInput{
		Executable: "sh",
		Args:       []string{"-s"},
		CWD:        ".",
		Stdin:      "echo second",
		Reason:     "Run a script from stdin.",
		Risk:       "executes stdin",
	})
	if err != nil {
		t.Fatalf("second run() error = %v", err)
	}
	if second.Status != "pending_review" {
		t.Fatalf("second status = %q, want pending_review", second.Status)
	}
	if ctx.requestCount != 1 {
		t.Fatalf("RequestConfirmation count = %d, want 1 for stdin command", ctx.requestCount)
	}
}

func TestRequestCommandAlwaysToolWorkspaceSkipsLaterReview(t *testing.T) {
	root := t.TempDir()
	t.Chdir(root)

	firstTool := newRequestCommandToolForTestWithConfig(requestCommandTestConfig(true))
	first, err := firstTool.runWithConfirmation(newFakeToolContext(&toolconfirmation.ToolConfirmation{
		Confirmed: true,
		Payload:   ReviewDecision{Action: "always_tool_workspace"},
	}), RequestCommandInput{
		Executable: "printf",
		Args:       []string{"first"},
		CWD:        ".",
		Reason:     "Print a test value.",
		Risk:       "read_only",
	})
	if err != nil {
		t.Fatalf("first run() error = %v", err)
	}
	if first.Status != "executed" {
		t.Fatalf("first status = %q, want executed", first.Status)
	}

	secondTool := newRequestCommandToolForTestWithConfig(requestCommandTestConfig(true))
	ctx := newFakeToolContext(nil)
	second, err := secondTool.runWithConfirmation(ctx, RequestCommandInput{
		Executable: "printf",
		Args:       []string{"second"},
		CWD:        ".",
		Reason:     "Print another value.",
		Risk:       "read_only",
	})
	if err != nil {
		t.Fatalf("second run() error = %v", err)
	}
	if second.Status != "executed" || second.Result == nil || second.Result.Stdout != "second" {
		t.Fatalf("second run() = %#v, want workspace tool-approved execution", second)
	}
	if ctx.requestCount != 0 {
		t.Fatalf("RequestConfirmation count = %d, want 0 after workspace tool approval", ctx.requestCount)
	}
}

func TestRequestCommandAlwaysToolGlobalSkipsLaterReview(t *testing.T) {
	t.Cleanup(func() {
		_ = updateGlobalPolicies(func(policies *globalPolicies) {
			policies.AlwaysTool = false
		})
	})
	root := t.TempDir()
	t.Chdir(root)

	firstTool := newRequestCommandToolForTestWithConfig(requestCommandTestConfig(true))
	first, err := firstTool.runWithConfirmation(newFakeToolContext(&toolconfirmation.ToolConfirmation{
		Confirmed: true,
		Payload:   ReviewDecision{Action: "always_tool"},
	}), RequestCommandInput{
		Executable: "printf",
		Args:       []string{"first"},
		CWD:        ".",
		Reason:     "Print a test value.",
		Risk:       "read_only",
	})
	if err != nil {
		t.Fatalf("first run() error = %v", err)
	}
	if first.Status != "executed" {
		t.Fatalf("first status = %q, want executed", first.Status)
	}

	otherRoot := t.TempDir()
	t.Chdir(otherRoot)
	secondTool := newRequestCommandToolForTestWithConfig(requestCommandTestConfig(true))
	ctx := newFakeToolContext(nil)
	second, err := secondTool.runWithConfirmation(ctx, RequestCommandInput{
		Executable: "printf",
		Args:       []string{"second"},
		CWD:        ".",
		Reason:     "Print another value.",
		Risk:       "read_only",
	})
	if err != nil {
		t.Fatalf("second run() error = %v", err)
	}
	if second.Status != "executed" || second.Result == nil || second.Result.Stdout != "second" {
		t.Fatalf("second run() = %#v, want global tool-approved execution", second)
	}
	if ctx.requestCount != 0 {
		t.Fatalf("RequestConfirmation count = %d, want 0 after global tool approval", ctx.requestCount)
	}
}

func TestRequestCommandRejectsCWDEscapeBeforeReview(t *testing.T) {
	root := t.TempDir()
	t.Chdir(root)
	requestTool := newRequestCommandToolForTest()
	ctx := newFakeToolContext(nil)

	got, err := requestTool.runWithConfirmation(ctx, RequestCommandInput{
		Executable: "printf",
		Args:       []string{"hello"},
		CWD:        "..",
		Reason:     "Print a test value.",
		Risk:       "read_only",
	})
	if err == nil {
		t.Fatalf("run() error = nil, want cwd escape error")
	}
	if got.Status != "error" {
		t.Fatalf("status = %q, want error", got.Status)
	}
	if ctx.requestCount != 0 {
		t.Fatalf("RequestConfirmation count = %d, want 0 for rejected cwd", ctx.requestCount)
	}
}

func TestRequestCommandPassesStdin(t *testing.T) {
	root := t.TempDir()
	t.Chdir(root)
	requestTool := newRequestCommandToolForTest()
	ctx := newFakeToolContext(&toolconfirmation.ToolConfirmation{
		Confirmed: true,
		Payload:   ReviewDecision{Action: "approve_once"},
	})

	got, err := requestTool.runWithConfirmation(ctx, RequestCommandInput{
		Executable: "cat",
		CWD:        ".",
		Stdin:      "input text",
		Reason:     "Echo provided stdin.",
		Risk:       "read_only",
	})
	if err != nil {
		t.Fatalf("run() error = %v", err)
	}
	if got.Status != "executed" || got.Result == nil || got.Result.Stdout != "input text" {
		t.Fatalf("run() = %#v, want stdin echoed", got)
	}
}

// newRequestCommandToolForTest creates a test tool with persistent approvals disabled.
func newRequestCommandToolForTest() *requestCommandTool {
	return newRequestCommandToolForTestWithConfig(requestCommandTestConfig(false))
}

// newRequestCommandToolForTestWithConfig creates a test tool with custom config.
func newRequestCommandToolForTestWithConfig(cfg schema.LocalExec) *requestCommandTool {
	return &requestCommandTool{
		cfg:      cfg,
		policies: newReviewPolicies(),
		executor: testProcessExecutor{},
	}
}

// requestCommandTestConfig returns baseline local-exec config for request tests.
func requestCommandTestConfig(allowPersistentApprovals bool) schema.LocalExec {
	return schema.LocalExec{
		Enabled:                  true,
		AllowPersistentApprovals: allowPersistentApprovals,
		DefaultTimeout:           "1s",
		DefaultMaxOutputBytes:    1024,
		AllowedWorkdirs:          []string{"."},
	}
}

type testProcessExecutor struct{}

func (testProcessExecutor) Execute(ctx context.Context, call execspec.ToolCall) (execspec.Output, error) {
	execCtx, cancel := context.WithTimeout(ctx, call.Timeout)
	defer cancel()

	cmd := exec.CommandContext(execCtx, call.Executable, call.Args...)
	cmd.Dir = call.CWD
	if call.Stdin != "" {
		cmd.Stdin = strings.NewReader(call.Stdin)
	}

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	err := cmd.Run()
	timedOut := errors.Is(execCtx.Err(), context.DeadlineExceeded)
	out := execspec.Output{
		ExitCode: exitCode(err, timedOut),
		Stdout:   stdout.String(),
		Stderr:   stderr.String(),
		TimedOut: timedOut,
	}
	if err != nil && !isExitError(err) && !timedOut {
		return out, err
	}
	return out, nil
}

func exitCode(err error, timedOut bool) int {
	if err == nil {
		return 0
	}
	if timedOut {
		return -1
	}
	var exitErr *exec.ExitError
	if errors.As(err, &exitErr) {
		return exitErr.ExitCode()
	}
	return -1
}

func isExitError(err error) bool {
	var exitErr *exec.ExitError
	return errors.As(err, &exitErr)
}

func optionActions(options []ApprovalOption) []string {
	actions := make([]string, 0, len(options))
	for _, option := range options {
		actions = append(actions, option.Action)
	}
	return actions
}

type fakeToolContext struct {
	context.Context

	confirmation *toolconfirmation.ToolConfirmation
	hint         string
	payload      any
	requestCount int
}

func newFakeToolContext(confirmation *toolconfirmation.ToolConfirmation) *fakeToolContext {
	return &fakeToolContext{
		Context:      context.Background(),
		confirmation: confirmation,
	}
}

func (c *fakeToolContext) ToolConfirmation() *toolconfirmation.ToolConfirmation {
	return c.confirmation
}

func (c *fakeToolContext) RequestConfirmation(hint string, payload any) error {
	c.hint = hint
	c.payload = payload
	c.requestCount++
	return nil
}
