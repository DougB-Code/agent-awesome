// This file tests runtime tool bundle construction.
package toolsets

import (
	"testing"

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
