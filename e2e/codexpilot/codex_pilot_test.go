// This file drives the Codex CLI pilot workflow through harness-hosted service boundaries.
package codexpilot

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"time"
)

// TestCodexCLIPilotFakeCLIsEndToEnd runs fake external CLIs through generic AA boundaries.
func TestCodexCLIPilotFakeCLIsEndToEnd(t *testing.T) {
	if os.Getenv("AGENTAWESOME_RUN_CODEX_PILOT_E2E") != "1" {
		t.Skip("set AGENTAWESOME_RUN_CODEX_PILOT_E2E=1 to run fake-CLI daemon integration test")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
	defer cancel()
	root := repoRoot(t)
	tempRoot := t.TempDir()
	binDir := filepath.Join(tempRoot, "bin")
	if err := os.MkdirAll(binDir, 0o700); err != nil {
		t.Fatalf("MkdirAll() error = %v", err)
	}
	fakeCodex := writeExecutable(t, binDir, "fake-codex", fakeCodexScript())
	fakeTest := writeExecutable(t, binDir, "fake-test", `#!/bin/sh
printf '{"passed":true}'
`)
	fakeGH := writeExecutable(t, binDir, "fake-gh", `#!/bin/sh
printf '{"url":"https://example.test/pull/1"}'
`)
	repo := initRepo(t, tempRoot)
	remote := filepath.Join(tempRoot, "remote.git")
	runCmd(t, "", "git", "init", "--bare", remote)
	runCmd(t, repo, "git", "remote", "add", "origin", remote)
	worktree := filepath.Join(tempRoot, "build", "sourcecontrol", "worktrees", "feature-codex-pilot")

	commandAddr := freeAddr(t)
	mcpAddr := freeAddr(t)
	workflowAddr := freeAddr(t)
	webAddr := freeAddr(t)
	sourcecontrol := startSourceControlMCP(t)
	defer sourcecontrol.Close()
	sourcecontrolURL := sourcecontrol.URL + "/mcp"
	commandURL := "http://" + commandAddr + "/mcp"
	mcpURL := "http://" + mcpAddr + "/mcp"
	workflowURL := "http://" + workflowAddr

	definitionsDir := filepath.Join(tempRoot, "workflows")
	if err := os.MkdirAll(definitionsDir, 0o700); err != nil {
		t.Fatalf("MkdirAll() error = %v", err)
	}
	writeWorkflowDefinition(t, filepath.Join(definitionsDir, "codex-pilot.yaml"), mcpURL)

	templatesJSON := commandTemplatesJSON(t, fakeCodex, fakeTest, fakeGH)
	serversJSON := mcpServersJSON(t, sourcecontrolURL, commandURL)
	harnessCmd := startHarness(ctx, t, filepath.Join(root, "harness"), tempRoot,
		"--command-mcp-addr", commandAddr,
		"--command-data-dir", filepath.Join(tempRoot, "command-data"),
		"--command-parser-dir", filepath.Join(tempRoot, "command-parsers"),
		"--command-allow-workdir", tempRoot,
		"--command-templates-json", templatesJSON,
		"--mcp-manager-addr", mcpAddr,
		"--mcp-servers-json", serversJSON,
		"--workflow-api-addr", workflowAddr,
		"--workflow-definitions", definitionsDir,
		"--workflow-db", filepath.Join(tempRoot, "workflow.db"),
		"--session-db", filepath.Join(tempRoot, "sessions.db"),
		"--", "web", "--port", portFromAddr(t, webAddr), "api", "--webui_address", webAddr,
	)
	defer stopDaemon(harnessCmd)
	waitHealth(t, "http://"+commandAddr+"/healthz")
	waitHealth(t, "http://"+mcpAddr+"/healthz")
	waitHealth(t, workflowURL+"/healthz")

	runID := startWorkflow(t, workflowURL, map[string]any{
		"definition_id": "codex_cli_pilot",
		"input": map[string]any{
			"repository_path": repo,
			"worktree_path":   worktree,
			"branch":          "feature/codex-pilot",
			"base_ref":        "HEAD",
			"remote":          "origin",
			"commit_message":  "Codex CLI pilot changes",
		},
	})
	run := waitWorkflow(t, workflowURL, runID)
	if run["status"] != "succeeded" {
		history := getJSON(t, workflowURL+"/api/workflows/runs/"+runID+"/history")
		t.Fatalf("workflow run = %#v, history = %#v", run, history)
	}
	runCmd(t, "", "git", "--git-dir", remote, "rev-parse", "feature/codex-pilot")
}

// TestRealCodexCLICommandBoundarySmoke verifies the harness command boundary can launch the configured Codex binary.
func TestRealCodexCLICommandBoundarySmoke(t *testing.T) {
	if os.Getenv("AGENTAWESOME_RUN_REAL_CODEX_SMOKE") != "1" {
		t.Skip("set AGENTAWESOME_RUN_REAL_CODEX_SMOKE=1 to verify the real Codex executable through the harness command boundary")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	root := repoRoot(t)
	tempRoot := t.TempDir()
	codexExecutable := strings.TrimSpace(os.Getenv("AGENTAWESOME_CODEX_EXECUTABLE"))
	if codexExecutable == "" {
		codexExecutable = "codex"
	}
	commandAddr := freeAddr(t)
	webAddr := freeAddr(t)
	commandURL := "http://" + commandAddr + "/mcp"
	templatesJSON := realCodexSmokeTemplatesJSON(t, codexExecutable)
	harnessCmd := startHarness(ctx, t, filepath.Join(root, "harness"), tempRoot,
		"--command-mcp-addr", commandAddr,
		"--command-data-dir", filepath.Join(tempRoot, "command-data"),
		"--command-parser-dir", filepath.Join(tempRoot, "command-parsers"),
		"--command-allow-workdir", tempRoot,
		"--command-templates-json", templatesJSON,
		"--session-db", filepath.Join(tempRoot, "sessions.db"),
		"--", "web", "--port", portFromAddr(t, webAddr), "api", "--webui_address", webAddr,
	)
	defer stopDaemon(harnessCmd)
	waitHealth(t, "http://"+commandAddr+"/healthz")

	status := callCommandExecute(t, commandURL, map[string]any{
		"template_id": "codex_version",
		"cwd":         tempRoot,
	})
	if status["status"] != "succeeded" {
		t.Fatalf("real Codex command status = %#v, want succeeded", status)
	}
	stdout, _ := status["stdout_tail"].(string)
	stderr, _ := status["stderr_tail"].(string)
	if strings.TrimSpace(stdout) == "" && strings.TrimSpace(stderr) == "" {
		t.Fatalf("real Codex version command returned no visible output: %#v", status)
	}
}

// commandTemplatesJSON returns command templates for fake external CLIs.
func commandTemplatesJSON(t *testing.T, fakeCodex string, fakeTest string, fakeGH string) string {
	t.Helper()
	templates := []map[string]any{
		commandTemplate("codex_plan", fakeCodex, []string{"plan"}),
		commandTemplate("codex_implement", fakeCodex, []string{"implement"}),
		commandTemplate("codex_review", fakeCodex, []string{"review"}),
		commandTemplate("codex_cleanup", fakeCodex, []string{"cleanup"}),
		commandTemplate("test", fakeTest, nil),
		commandTemplate("gh_pr_create", fakeGH, []string{"pr", "create"}),
	}
	data, err := json.Marshal(templates)
	if err != nil {
		t.Fatalf("Marshal() error = %v", err)
	}
	return string(data)
}

// realCodexSmokeTemplatesJSON returns a command template for the configured Codex binary.
func realCodexSmokeTemplatesJSON(t *testing.T, codexExecutable string) string {
	t.Helper()
	templates := []map[string]any{
		{
			"id":              "codex_version",
			"description":     "Verify the configured Codex executable can launch.",
			"executable":      codexExecutable,
			"args":            []string{"--version"},
			"timeout":         "15s",
			"output_contract": map[string]any{"format": "text", "source": "stdout"},
		},
	}
	data, err := json.Marshal(templates)
	if err != nil {
		t.Fatalf("Marshal() error = %v", err)
	}
	return string(data)
}

// commandTemplate builds one JSON-output command template.
func commandTemplate(id string, executable string, args []string) map[string]any {
	return map[string]any{
		"id":              id,
		"executable":      executable,
		"args":            args,
		"output_contract": map[string]any{"format": "json", "source": "stdout"},
	}
}

// mcpServersJSON returns MCP manager configuration for command and source-control endpoints.
func mcpServersJSON(t *testing.T, sourcecontrolURL string, commandURL string) string {
	t.Helper()
	servers := []map[string]any{
		{"id": "sourcecontrol", "endpoint": sourcecontrolURL},
		{"id": "command", "endpoint": commandURL},
	}
	data, err := json.Marshal(servers)
	if err != nil {
		t.Fatalf("Marshal() error = %v", err)
	}
	return string(data)
}

// writeWorkflowDefinition writes the Codex pilot workflow used by the integration test.
func writeWorkflowDefinition(t *testing.T, path string, mcpURL string) {
	t.Helper()
	body := fmt.Sprintf(`
kind: state_machine
id: codex_cli_pilot
name: Codex CLI Pilot
states:
  - id: prepare
    type: task
    uses: mcp.call
    with:
      endpoint: %q
      tool: mcp.call
      arguments:
        server_id: sourcecontrol
        tool: sourcecontrol.prepare_worktree
        arguments:
          repository_path: ${repository_path}
          worktree_path: ${worktree_path}
          branch: ${branch}
          base_ref: ${base_ref}
  - id: plan
    type: task
    uses: mcp.call
    depends_on: [prepare]
    with: &command_call
      endpoint: %q
      tool: mcp.call
      arguments:
        server_id: command
        tool: command.execute
        arguments:
          template_id: codex_plan
          cwd: ${prepare.worktree_path}
  - id: assert_plan
    type: task
    uses: data.assert
    depends_on: [plan]
    with:
      checks:
        - path: plan.output.plan.compliant
          mode: equals
          value: true
        - path: plan.output.plan.project_conventions
          mode: equals
          value: true
        - path: plan.output.plan.solid
          mode: equals
          value: true
        - path: plan.output.plan.agents
          mode: equals
          value: true
        - path: plan.output.plan.relevant_skills
          mode: equals
          value: true
        - path: plan.output.plan.no_unnecessary_backwards_compatibility
          mode: equals
          value: true
        - path: plan.output.plan.no_duplicate_implementations
          mode: equals
          value: true
        - path: plan.output.plan.no_hardcoded_values
          mode: equals
          value: true
  - id: backup
    type: task
    uses: mcp.call
    depends_on: [assert_plan, prepare]
    with:
      endpoint: %q
      tool: mcp.call
      arguments:
        server_id: sourcecontrol
        tool: sourcecontrol.backup
        arguments:
          worktree_path: ${prepare.worktree_path}
  - id: implement
    type: task
    uses: mcp.call
    depends_on: [backup, prepare]
    with:
      <<: *command_call
      arguments:
        server_id: command
        tool: command.execute
        arguments:
          template_id: codex_implement
          cwd: ${prepare.worktree_path}
  - id: assert_implement
    type: task
    uses: data.assert
    depends_on: [implement]
    with:
      checks:
        - path: implement.status
          mode: equals
          value: succeeded
        - path: implement.validation.valid
          mode: equals
          value: true
  - id: test
    type: task
    uses: mcp.call
    depends_on: [assert_implement, prepare]
    with:
      <<: *command_call
      arguments:
        server_id: command
        tool: command.execute
        arguments:
          template_id: test
          cwd: ${prepare.worktree_path}
  - id: assert_tests
    type: task
    uses: data.assert
    depends_on: [test]
    with:
      checks:
        - path: test.status
          mode: equals
          value: succeeded
        - path: test.output.passed
          mode: equals
          value: true
  - id: post_review
    type: task
    uses: mcp.call
    depends_on: [assert_tests, prepare]
    with:
      <<: *command_call
      arguments:
        server_id: command
        tool: command.execute
        arguments:
          template_id: codex_review
          cwd: ${prepare.worktree_path}
  - id: cleanup
    type: task
    uses: mcp.call
    depends_on: [post_review, prepare]
    with:
      <<: *command_call
      arguments:
        server_id: command
        tool: command.execute
        arguments:
          template_id: codex_cleanup
          cwd: ${prepare.worktree_path}
  - id: assert_cleanup
    type: task
    uses: data.assert
    depends_on: [cleanup]
    with:
      checks:
        - path: cleanup.status
          mode: equals
          value: succeeded
        - path: cleanup.validation.valid
          mode: equals
          value: true
  - id: retest
    type: task
    uses: mcp.call
    depends_on: [assert_cleanup, prepare]
    with:
      <<: *command_call
      arguments:
        server_id: command
        tool: command.execute
        arguments:
          template_id: test
          cwd: ${prepare.worktree_path}
  - id: assert_retest
    type: task
    uses: data.assert
    depends_on: [retest]
    with:
      checks:
        - path: retest.status
          mode: equals
          value: succeeded
        - path: retest.output.passed
          mode: equals
          value: true
  - id: final_review
    type: task
    uses: mcp.call
    depends_on: [assert_retest, prepare]
    with:
      <<: *command_call
      arguments:
        server_id: command
        tool: command.execute
        arguments:
          template_id: codex_review
          cwd: ${prepare.worktree_path}
  - id: assert_review
    type: task
    uses: data.assert
    depends_on: [final_review]
    with:
      checks:
        - path: final_review.output.deviations
          mode: equals
          value: []
  - id: commit
    type: task
    uses: mcp.call
    depends_on: [assert_review, prepare]
    with:
      endpoint: %q
      tool: mcp.call
      arguments:
        server_id: sourcecontrol
        tool: sourcecontrol.commit
        arguments:
          worktree_path: ${prepare.worktree_path}
          message: ${workflow_input.commit_message}
  - id: push
    type: task
    uses: mcp.call
    depends_on: [commit, prepare]
    with:
      endpoint: %q
      tool: mcp.call
      arguments:
        server_id: sourcecontrol
        tool: sourcecontrol.push
        arguments:
          worktree_path: ${prepare.worktree_path}
          remote: ${workflow_input.remote}
          branch: ${workflow_input.branch}
  - id: open_pr
    type: task
    uses: mcp.call
    depends_on: [push, prepare]
    with:
      <<: *command_call
      arguments:
        server_id: command
        tool: command.execute
        arguments:
          template_id: gh_pr_create
          cwd: ${prepare.worktree_path}
  - id: assert_pr
    type: task
    uses: data.assert
    depends_on: [open_pr]
    with:
      checks:
        - path: open_pr.output.url
          mode: exists
`, mcpURL, mcpURL, mcpURL, mcpURL, mcpURL)
	if err := os.WriteFile(path, []byte(body), 0o600); err != nil {
		t.Fatalf("WriteFile() error = %v", err)
	}
}

// fakeCodexScript returns a shell script that mimics the Codex CLI contract.
func fakeCodexScript() string {
	return `#!/bin/sh
case "$1" in
  plan)
    printf '{"plan":{"compliant":true,"project_conventions":true,"solid":true,"agents":true,"relevant_skills":true,"no_unnecessary_backwards_compatibility":true,"no_duplicate_implementations":true,"no_hardcoded_values":true}}'
    ;;
  implement)
    printf 'implemented by fake codex\n' > codex-output.txt
    printf '{"implemented":true}'
    ;;
  review)
    printf '{"deviations":[]}'
    ;;
  cleanup)
    printf '{"cleaned":true}'
    ;;
  *)
    echo "unknown fake codex mode" >&2
    exit 2
    ;;
esac
`
}

// writeExecutable creates one executable helper script.
func writeExecutable(t *testing.T, dir string, name string, body string) string {
	t.Helper()
	path := filepath.Join(dir, name)
	if err := os.WriteFile(path, []byte(body), 0o700); err != nil {
		t.Fatalf("WriteFile() error = %v", err)
	}
	return path
}

// initRepo creates a local repository with one committed file.
func initRepo(t *testing.T, root string) string {
	t.Helper()
	repo := filepath.Join(root, "repo")
	if err := os.MkdirAll(repo, 0o700); err != nil {
		t.Fatalf("MkdirAll() error = %v", err)
	}
	runCmd(t, repo, "git", "init", "-b", "main")
	runCmd(t, repo, "git", "config", "user.email", "aa@example.test")
	runCmd(t, repo, "git", "config", "user.name", "Agent Awesome Test")
	if err := os.WriteFile(filepath.Join(repo, "README.md"), []byte("root\n"), 0o600); err != nil {
		t.Fatalf("WriteFile() error = %v", err)
	}
	runCmd(t, repo, "git", "add", "README.md")
	runCmd(t, repo, "git", "commit", "-m", "initial")
	return repo
}

// startHarness starts the harness with minimal model, agent, and tool configs.
func startHarness(ctx context.Context, t *testing.T, dir string, tempRoot string, args ...string) *exec.Cmd {
	t.Helper()
	cliArgs := []string{
		"run",
		"--model", writeHarnessModelConfig(t, tempRoot),
		"--agent", writeHarnessAgentConfig(t, tempRoot),
		"--tool", writeHarnessToolConfig(t, tempRoot),
		"--provider", "local-test",
		"--model-id", "noop",
	}
	cliArgs = append(cliArgs, args...)
	goArgs := append([]string{"run", "./cmd/agent-awesome"}, cliArgs...)
	return startDaemon(ctx, t, dir, "go", goArgs...)
}

// writeHarnessModelConfig writes a loopback-only model config for harness startup.
func writeHarnessModelConfig(t *testing.T, root string) string {
	t.Helper()
	path := filepath.Join(root, "harness-model.yaml")
	body := `
default: local-test:noop
providers:
  local-test:
    adapter: openai
    auth: optional
    url: http://127.0.0.1:9/v1/chat/completions
    models:
      - id: noop
        model: noop
`
	writeTextFile(t, path, body)
	return path
}

// writeHarnessAgentConfig writes the minimal agent config required to boot web mode.
func writeHarnessAgentConfig(t *testing.T, root string) string {
	t.Helper()
	path := filepath.Join(root, "harness-agent.yaml")
	body := `
name: codex_pilot_e2e
description: Codex pilot integration harness.
instruction: Keep the harness web runtime alive for embedded service tests.
`
	writeTextFile(t, path, body)
	return path
}

// writeHarnessToolConfig writes an empty tool config for harness startup.
func writeHarnessToolConfig(t *testing.T, root string) string {
	t.Helper()
	path := filepath.Join(root, "harness-tool.yaml")
	body := `
local-exec: {}
mcp: {}
memory: {}
`
	writeTextFile(t, path, body)
	return path
}

// startSourceControlMCP serves the source-control tools needed by the pilot workflow.
func startSourceControlMCP(t *testing.T) *httptest.Server {
	t.Helper()
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		var req sourceControlRPCRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeSourceControlRPCError(w, nil, -32700, "parse error", err.Error())
			return
		}
		switch req.Method {
		case "initialize":
			writeSourceControlRPCResult(w, req.ID, map[string]any{
				"protocolVersion": "2025-06-18",
				"capabilities":    map[string]any{"tools": map[string]any{"listChanged": false}},
				"serverInfo":      map[string]any{"name": "codex-pilot-source-control", "version": "test"},
			})
		case "tools/list":
			writeSourceControlRPCResult(w, req.ID, map[string]any{"tools": sourceControlToolDefinitions()})
		case "tools/call":
			handleSourceControlToolCall(w, req)
		default:
			writeSourceControlRPCError(w, req.ID, -32601, "method not found", req.Method)
		}
	}))
}

// handleSourceControlToolCall decodes and dispatches one fake source-control tool.
func handleSourceControlToolCall(w http.ResponseWriter, req sourceControlRPCRequest) {
	var call sourceControlToolCall
	if err := json.Unmarshal(req.Params, &call); err != nil {
		writeSourceControlRPCError(w, req.ID, -32602, "invalid params", err.Error())
		return
	}
	result, err := callSourceControlTool(call.Name, call.Arguments)
	if err != nil {
		writeSourceControlRPCResult(w, req.ID, sourceControlToolResult(map[string]string{"error": err.Error()}, true))
		return
	}
	writeSourceControlRPCResult(w, req.ID, sourceControlToolResult(result, false))
}

// callSourceControlTool performs the Git side effects used by the workflow.
func callSourceControlTool(name string, args map[string]any) (map[string]any, error) {
	switch name {
	case "sourcecontrol.prepare_worktree":
		return sourceControlPrepareWorktree(args)
	case "sourcecontrol.backup":
		return map[string]any{"backup_id": "codex-pilot-e2e"}, nil
	case "sourcecontrol.commit":
		return sourceControlCommit(args)
	case "sourcecontrol.push":
		return sourceControlPush(args)
	default:
		return nil, fmt.Errorf("unsupported source-control tool %q", name)
	}
}

// sourceControlPrepareWorktree creates a branch worktree for the test repository.
func sourceControlPrepareWorktree(args map[string]any) (map[string]any, error) {
	repo, err := requiredStringArg(args, "repository_path")
	if err != nil {
		return nil, err
	}
	worktree, err := requiredStringArg(args, "worktree_path")
	if err != nil {
		return nil, err
	}
	branch, err := requiredStringArg(args, "branch")
	if err != nil {
		return nil, err
	}
	baseRef, err := requiredStringArg(args, "base_ref")
	if err != nil {
		return nil, err
	}
	if err := os.MkdirAll(filepath.Dir(worktree), 0o700); err != nil {
		return nil, err
	}
	if _, err := runSourceControlCommand(repo, "git", "worktree", "add", "-B", branch, worktree, baseRef); err != nil {
		return nil, err
	}
	return map[string]any{
		"repository_path": repo,
		"worktree_path":   worktree,
		"branch":          branch,
		"base_ref":        baseRef,
	}, nil
}

// sourceControlCommit commits workflow-produced changes in the worktree.
func sourceControlCommit(args map[string]any) (map[string]any, error) {
	worktree, err := requiredStringArg(args, "worktree_path")
	if err != nil {
		return nil, err
	}
	message, err := requiredStringArg(args, "message")
	if err != nil {
		return nil, err
	}
	if _, err := runSourceControlCommand(worktree, "git", "add", "-A"); err != nil {
		return nil, err
	}
	if _, err := runSourceControlCommand(worktree, "git", "commit", "-m", message); err != nil {
		return nil, err
	}
	commit, err := runSourceControlCommand(worktree, "git", "rev-parse", "HEAD")
	if err != nil {
		return nil, err
	}
	return map[string]any{"commit": strings.TrimSpace(commit)}, nil
}

// sourceControlPush pushes the current worktree HEAD to the requested branch.
func sourceControlPush(args map[string]any) (map[string]any, error) {
	worktree, err := requiredStringArg(args, "worktree_path")
	if err != nil {
		return nil, err
	}
	remote, err := requiredStringArg(args, "remote")
	if err != nil {
		return nil, err
	}
	branch, err := requiredStringArg(args, "branch")
	if err != nil {
		return nil, err
	}
	if _, err := runSourceControlCommand(worktree, "git", "push", remote, "HEAD:"+branch); err != nil {
		return nil, err
	}
	return map[string]any{"remote": remote, "branch": branch}, nil
}

// requiredStringArg returns one required string argument from a tool call.
func requiredStringArg(args map[string]any, name string) (string, error) {
	value, _ := args[name].(string)
	if strings.TrimSpace(value) == "" {
		return "", fmt.Errorf("%s is required", name)
	}
	return strings.TrimSpace(value), nil
}

// runSourceControlCommand executes one Git command for the fake source-control server.
func runSourceControlCommand(dir string, name string, args ...string) (string, error) {
	cmd := exec.Command(name, args...)
	cmd.Dir = dir
	out, err := cmd.CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("%s %s: %w: %s", name, strings.Join(args, " "), err, strings.TrimSpace(string(out)))
	}
	return string(out), nil
}

// sourceControlToolDefinitions lists the tools exposed by the fake server.
func sourceControlToolDefinitions() []map[string]any {
	names := []string{
		"sourcecontrol.prepare_worktree",
		"sourcecontrol.backup",
		"sourcecontrol.commit",
		"sourcecontrol.push",
	}
	tools := make([]map[string]any, 0, len(names))
	for _, name := range names {
		tools = append(tools, map[string]any{
			"name":        name,
			"description": name,
			"inputSchema": map[string]any{"type": "object"},
		})
	}
	return tools
}

// sourceControlToolResult wraps structured MCP content.
func sourceControlToolResult(content any, isError bool) map[string]any {
	data, _ := json.Marshal(content)
	return map[string]any{
		"content":           []map[string]string{{"type": "text", "text": string(data)}},
		"structuredContent": content,
		"isError":           isError,
	}
}

// writeSourceControlRPCResult writes a JSON-RPC result response.
func writeSourceControlRPCResult(w http.ResponseWriter, id json.RawMessage, result any) {
	writeJSON(w, http.StatusOK, map[string]any{
		"jsonrpc": "2.0",
		"id":      json.RawMessage(id),
		"result":  result,
	})
}

// writeSourceControlRPCError writes a JSON-RPC error response.
func writeSourceControlRPCError(w http.ResponseWriter, id json.RawMessage, code int, message string, data any) {
	writeJSON(w, http.StatusOK, map[string]any{
		"jsonrpc": "2.0",
		"id":      json.RawMessage(id),
		"error": map[string]any{
			"code":    code,
			"message": message,
			"data":    data,
		},
	})
}

// writeJSON writes one JSON test response.
func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}

// sourceControlRPCRequest stores one JSON-RPC request for the fake server.
type sourceControlRPCRequest struct {
	ID     json.RawMessage `json:"id"`
	Method string          `json:"method"`
	Params json.RawMessage `json:"params"`
}

// sourceControlToolCall stores one MCP tools/call request.
type sourceControlToolCall struct {
	Name      string         `json:"name"`
	Arguments map[string]any `json:"arguments"`
}

// startWorkflow posts one workflow run request and returns the run id.
func startWorkflow(t *testing.T, baseURL string, payload map[string]any) string {
	t.Helper()
	var decoded map[string]any
	postJSON(t, baseURL+"/api/workflows/runs", payload, &decoded)
	run, _ := decoded["run"].(map[string]any)
	runID, _ := run["id"].(string)
	if runID == "" {
		t.Fatalf("start workflow response = %#v, want run id", decoded)
	}
	return runID
}

// waitWorkflow waits for one workflow run to finish.
func waitWorkflow(t *testing.T, baseURL string, runID string) map[string]any {
	t.Helper()
	deadline := time.Now().Add(30 * time.Second)
	for time.Now().Before(deadline) {
		decoded := getJSON(t, baseURL+"/api/workflows/runs/"+runID)
		run, _ := decoded["run"].(map[string]any)
		status, _ := run["status"].(string)
		if status != "running" && status != "waiting" && status != "" {
			return run
		}
		time.Sleep(100 * time.Millisecond)
	}
	t.Fatalf("workflow run %s did not finish", runID)
	return nil
}

// getJSON reads a JSON object from an HTTP endpoint.
func getJSON(t *testing.T, url string) map[string]any {
	t.Helper()
	resp, err := http.Get(url)
	if err != nil {
		t.Fatalf("GET %s: %v", url, err)
	}
	defer resp.Body.Close()
	var decoded map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&decoded); err != nil {
		t.Fatalf("Decode() error = %v", err)
	}
	return decoded
}

// postJSON sends and decodes one JSON HTTP request.
func postJSON(t *testing.T, url string, payload any, target any) {
	t.Helper()
	data, err := json.Marshal(payload)
	if err != nil {
		t.Fatalf("Marshal() error = %v", err)
	}
	resp, err := http.Post(url, "application/json", bytes.NewReader(data))
	if err != nil {
		t.Fatalf("POST %s: %v", url, err)
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		var decoded map[string]any
		_ = json.NewDecoder(resp.Body).Decode(&decoded)
		t.Fatalf("POST %s HTTP %d: %#v", url, resp.StatusCode, decoded)
	}
	if err := json.NewDecoder(resp.Body).Decode(target); err != nil {
		t.Fatalf("Decode() error = %v", err)
	}
}

// callCommandExecute invokes command.execute over the command boundary MCP transport.
func callCommandExecute(t *testing.T, commandURL string, arguments map[string]any) map[string]any {
	t.Helper()
	var decoded map[string]any
	postJSON(t, commandURL, map[string]any{
		"jsonrpc": "2.0",
		"id":      "codex-smoke",
		"method":  "tools/call",
		"params": map[string]any{
			"name":      "command.execute",
			"arguments": arguments,
		},
	}, &decoded)
	if rpcError, ok := decoded["error"].(map[string]any); ok {
		t.Fatalf("command.execute JSON-RPC error = %#v", rpcError)
	}
	result, ok := decoded["result"].(map[string]any)
	if !ok {
		t.Fatalf("command.execute response = %#v, want result object", decoded)
	}
	if isError, _ := result["isError"].(bool); isError {
		t.Fatalf("command.execute returned tool error = %#v", result)
	}
	structured, ok := result["structuredContent"].(map[string]any)
	if !ok {
		t.Fatalf("command.execute result = %#v, want structured content", result)
	}
	return structured
}

// startDaemon starts one Go daemon command in a module directory.
func startDaemon(ctx context.Context, t *testing.T, dir string, name string, args ...string) *exec.Cmd {
	t.Helper()
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.Dir = dir
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Env = append(os.Environ(),
		"GOPATH="+filepath.Join(repoRoot(t), "build", "go"),
		"GOMODCACHE="+filepath.Join(repoRoot(t), "build", "go", "pkg", "mod"),
		"GOCACHE="+filepath.Join(repoRoot(t), "build", "go", "cache"),
	)
	var stderr bytes.Buffer
	cmd.Stdout = &stderr
	cmd.Stderr = &stderr
	if err := cmd.Start(); err != nil {
		t.Fatalf("start %s %s: %v", name, strings.Join(args, " "), err)
	}
	t.Cleanup(func() {
		if cmd.Process != nil {
			_ = syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
		}
		if err := cmd.Wait(); err != nil && ctx.Err() == nil {
			t.Logf("daemon exited: %v: %s", err, stderr.String())
		}
	})
	return cmd
}

// stopDaemon terminates a daemon process.
func stopDaemon(cmd *exec.Cmd) {
	if cmd != nil && cmd.Process != nil {
		_ = syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
	}
}

// waitHealth waits for a daemon health endpoint.
func waitHealth(t *testing.T, url string) {
	t.Helper()
	deadline := time.Now().Add(15 * time.Second)
	for time.Now().Before(deadline) {
		resp, err := http.Get(url)
		if err == nil {
			_ = resp.Body.Close()
			if resp.StatusCode >= 200 && resp.StatusCode < 300 {
				return
			}
		}
		time.Sleep(100 * time.Millisecond)
	}
	t.Fatalf("health endpoint %s did not become ready", url)
}

// freeAddr reserves and releases a local TCP address for a daemon.
func freeAddr(t *testing.T) string {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("Listen() error = %v", err)
	}
	addr := listener.Addr().String()
	if err := listener.Close(); err != nil {
		t.Fatalf("Close() error = %v", err)
	}
	return addr
}

// portFromAddr returns the TCP port component of a host:port address.
func portFromAddr(t *testing.T, address string) string {
	t.Helper()
	_, port, err := net.SplitHostPort(address)
	if err != nil {
		t.Fatalf("SplitHostPort(%q) error = %v", address, err)
	}
	return port
}

// writeTextFile writes a private text file.
func writeTextFile(t *testing.T, path string, body string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(body), 0o600); err != nil {
		t.Fatalf("WriteFile() error = %v", err)
	}
}

// repoRoot resolves the repository root from the e2e module.
func repoRoot(t *testing.T) string {
	t.Helper()
	abs, err := filepath.Abs(filepath.Join("..", ".."))
	if err != nil {
		t.Fatalf("Abs() error = %v", err)
	}
	return abs
}

// runCmd executes one setup or verification command.
func runCmd(t *testing.T, dir string, name string, args ...string) {
	t.Helper()
	cmd := exec.Command(name, args...)
	cmd.Dir = dir
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("%s %s: %v: %s", name, strings.Join(args, " "), err, strings.TrimSpace(string(out)))
	}
}
