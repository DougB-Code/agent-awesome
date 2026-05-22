// This file tests application runtime option handling.
package app

import (
	"reflect"
	"testing"
	"time"

	"agentawesome/internal/config/schema"
)

func TestLocalExecCommandTemplatesConvertsLegacyAliases(t *testing.T) {
	templates, err := localExecCommandTemplates(&schema.Tools{
		LocalExec: schema.LocalExec{
			Enabled:                  true,
			DefaultTimeout:           "11s",
			DefaultMaxOutputBytes:    2048,
			AllowPersistentApprovals: true,
			Commands: []schema.LocalExecCommand{
				{
					Name:           "git_status",
					Description:    "Show status.",
					Executable:     "git",
					Args:           []string{"status", "--short"},
					Timeout:        "3s",
					MaxOutputBytes: 4096,
				},
			},
		},
	})
	if err != nil {
		t.Fatalf("localExecCommandTemplates() error = %v", err)
	}
	if got, want := len(templates), 1; got != want {
		t.Fatalf("len(templates) = %d, want %d", got, want)
	}
	template := templates[0]
	if template.ID != "git_status" || template.Description != "Show status." || template.Executable != "git" {
		t.Fatalf("template identity = %#v, want git_status git", template)
	}
	if want := []string{"status", "--short"}; !reflect.DeepEqual(template.Args, want) {
		t.Fatalf("template.Args = %#v, want %#v", template.Args, want)
	}
	if template.Timeout != 3*time.Second {
		t.Fatalf("template.Timeout = %s, want 3s", template.Timeout)
	}
	if template.MaxOutputBytes != 4096 {
		t.Fatalf("template.MaxOutputBytes = %d, want 4096", template.MaxOutputBytes)
	}
}

func TestToolsWithEmbeddedCommandEndpointAddsConfirmedCommandMCPServer(t *testing.T) {
	cfg := toolsWithEmbeddedCommandEndpoint(&schema.Tools{}, "http://127.0.0.1:8093/mcp")
	if !cfg.MCP.Enabled {
		t.Fatalf("MCP.Enabled = false, want true")
	}
	if got, want := len(cfg.MCP.Servers), 1; got != want {
		t.Fatalf("len(MCP.Servers) = %d, want %d", got, want)
	}
	server := cfg.MCP.Servers[0]
	if server.Name != "command" || server.Endpoint != "http://127.0.0.1:8093/mcp" {
		t.Fatalf("command server = %#v, want named command endpoint", server)
	}
	if want := []string{"command_execute", "command_cancel"}; !reflect.DeepEqual(server.RequireConfirmationTools, want) {
		t.Fatalf("RequireConfirmationTools = %#v, want %#v", server.RequireConfirmationTools, want)
	}
	if want := []string{"command_execute", "command_template_list", "command_status", "command_cancel"}; !reflect.DeepEqual(server.Tools.Allow, want) {
		t.Fatalf("Tools.Allow = %#v, want %#v", server.Tools.Allow, want)
	}
}

func TestToolsWithEmbeddedCommandEndpointDoesNotDuplicateConfiguredServer(t *testing.T) {
	cfg := toolsWithEmbeddedCommandEndpoint(&schema.Tools{
		MCP: schema.MCP{
			Enabled: true,
			Servers: []schema.MCPServer{
				{Name: "command", Transport: "streamable-http", Endpoint: "http://127.0.0.1:8093/mcp"},
			},
		},
	}, "http://127.0.0.1:8093/mcp")
	if got, want := len(cfg.MCP.Servers), 1; got != want {
		t.Fatalf("len(MCP.Servers) = %d, want %d", got, want)
	}
}

func TestCommandRequireApprovalUsesADKConfirmationForLegacyLocalExec(t *testing.T) {
	if commandRequireApproval(Options{}, &schema.Tools{LocalExec: schema.LocalExec{Enabled: true}}) {
		t.Fatalf("commandRequireApproval() = true, want false for ADK-confirmed legacy aliases")
	}
	if !commandRequireApproval(Options{}, &schema.Tools{}) {
		t.Fatalf("commandRequireApproval() = false, want secure default when no legacy alias is active")
	}
	if !commandRequireApproval(Options{CommandApprovalSet: true, CommandRequireApproval: true}, &schema.Tools{LocalExec: schema.LocalExec{Enabled: true}}) {
		t.Fatalf("commandRequireApproval() ignored explicit approval requirement")
	}
}
