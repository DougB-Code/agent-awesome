// This file tests runtime tool bundle construction.
package toolsets

import (
	"path/filepath"
	"runtime"
	"testing"

	"agentawesome/internal/config"
	"agentawesome/internal/config/schema"
)

func TestBuildReturnsLocalToolsAndMCPToolsets(t *testing.T) {
	cfg := &schema.Tools{
		LocalExec: schema.LocalExec{
			Enabled: true,
			Commands: []schema.LocalExecCommand{
				{
					Name:        "git_status",
					Executable:  "git",
					Description: "Show repository status.",
					Args:        []string{"status", "--short"},
				},
			},
		},
		MCP: schema.MCP{
			Enabled: true,
			Servers: []schema.MCPServer{
				{
					Name:                "filesystem",
					Transport:           "stdio",
					Command:             "npx",
					Args:                []string{"-y", "@modelcontextprotocol/server-filesystem", "/tmp"},
					RequireConfirmation: true,
					Tools: schema.MCPToolFilter{
						Allow: []string{"read_file"},
					},
				},
				{
					Name:                     "remote",
					Transport:                "http",
					Endpoint:                 "https://example.test/mcp",
					RequireConfirmationTools: []string{"delete_item"},
				},
			},
		},
	}

	bundle, err := Build(cfg)
	if err != nil {
		t.Fatalf("Build() error = %v", err)
	}
	if got, want := len(bundle.Tools), 2; got != want {
		t.Fatalf("len(Tools) = %d, want %d", got, want)
	}
	if got, want := len(bundle.Toolsets), 2; got != want {
		t.Fatalf("len(Toolsets) = %d, want %d", got, want)
	}
}

func TestBuildEmptyConfigReturnsEmptyBundle(t *testing.T) {
	bundle, err := Build(&schema.Tools{})
	if err != nil {
		t.Fatalf("Build() error = %v", err)
	}
	if len(bundle.Tools) != 0 {
		t.Fatalf("len(Tools) = %d, want 0", len(bundle.Tools))
	}
	if len(bundle.Toolsets) != 0 {
		t.Fatalf("len(Toolsets) = %d, want 0", len(bundle.Toolsets))
	}
}

func TestConfirmationProviderMatchesToolNames(t *testing.T) {
	provider := confirmationProvider([]string{"delete_item"})
	if provider == nil {
		t.Fatalf("confirmationProvider() = nil")
	}
	if !provider("delete_item", nil) {
		t.Fatalf("provider(delete_item) = false, want true")
	}
	if provider("read_file", nil) {
		t.Fatalf("provider(read_file) = true, want false")
	}
}

func TestShippedGraphMutationToolRequiresRuntimeConfirmation(t *testing.T) {
	root := repoRoot(t)
	for _, path := range []string{
		filepath.Join(root, "harness", "tool.local.yaml"),
		filepath.Join(root, "harness", "tool.cloudflare.yaml"),
		filepath.Join(root, "pilots", "personal-assistant", "tool.yaml"),
		filepath.Join(root, "deploy", "cloudflare", "config", "tool.yaml"),
	} {
		t.Run(filepath.ToSlash(path), func(t *testing.T) {
			cfg, err := config.LoadTools(path, true)
			if err != nil {
				t.Fatalf("LoadTools() error = %v", err)
			}
			server, ok := memoryServer(cfg.MCP.Servers)
			if !ok {
				t.Fatalf("memory MCP server not found")
			}
			provider := confirmationProvider(server.RequireConfirmationTools)
			if provider == nil {
				t.Fatalf("confirmationProvider() = nil")
			}
			mutation := map[string]any{
				"query":          `INSERT NODE task SET title = "needs review"`,
				"actor":          "beta-test",
				"source_node_id": "source:test",
			}
			if !provider("query_context_graph", mutation) {
				t.Fatalf("query_context_graph mutation did not require confirmation")
			}
			if !provider("mutate_context_graph", mutation) {
				t.Fatalf("mutate_context_graph mutation did not require confirmation")
			}
			if provider("list_tasks", map[string]any{}) {
				t.Fatalf("list_tasks required confirmation, want read-only task listing without confirmation")
			}
		})
	}
}

// memoryServer returns the memory MCP server from a loaded tool config.
func memoryServer(servers []schema.MCPServer) (schema.MCPServer, bool) {
	for _, server := range servers {
		if server.Name == "memory" {
			return server, true
		}
	}
	return schema.MCPServer{}, false
}

// repoRoot returns the repository root for shipped-config tests.
func repoRoot(t *testing.T) string {
	t.Helper()
	_, file, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("runtime.Caller() failed")
	}
	return filepath.Clean(filepath.Join(filepath.Dir(file), "..", "..", "..", ".."))
}
