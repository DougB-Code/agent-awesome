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
			Enabled:               true,
			DefaultTimeout:        "11s",
			DefaultMaxOutputBytes: 2048,
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

func TestCommandServiceTemplatesMergesJSONAndLocalExecAliases(t *testing.T) {
	templates, err := commandServiceTemplates(Options{
		CommandTemplatesJSON: `[{"id":"json_status","description":"JSON status.","executable":"git","args":["status"]}]`,
	}, &schema.Tools{
		LocalExec: schema.LocalExec{
			Enabled:               true,
			DefaultTimeout:        "11s",
			DefaultMaxOutputBytes: 2048,
			Commands: []schema.LocalExecCommand{
				{
					Name:        "local_status",
					Description: "Local status.",
					Executable:  "git",
					Args:        []string{"status", "--short"},
				},
			},
		},
	})
	if err != nil {
		t.Fatalf("commandServiceTemplates() error = %v", err)
	}
	if got, want := len(templates), 2; got != want {
		t.Fatalf("len(templates) = %d, want %d", got, want)
	}
	if templates[0].ID != "json_status" || templates[1].ID != "local_status" {
		t.Fatalf("template ids = %#v, want json then local", templates)
	}
}

func TestCommandRuntimeEnabledIncludesJSONTemplates(t *testing.T) {
	if !commandRuntimeEnabled(Options{CommandTemplatesJSON: `[{"id":"status"}]`}, nil) {
		t.Fatalf("commandRuntimeEnabled() = false, want true for JSON templates")
	}
	if commandRuntimeEnabled(Options{}, &schema.Tools{}) {
		t.Fatalf("commandRuntimeEnabled() = true, want false without command config")
	}
}

func TestCommandServiceToolsCreatesDirectADKTools(t *testing.T) {
	service, err := openCommandService(Options{
		CommandDataDir:       t.TempDir(),
		CommandParserDir:     t.TempDir(),
		CommandTemplatesJSON: `[{"id":"status","description":"Show status.","executable":"git","args":["status"]}]`,
	}, nil)
	if err != nil {
		t.Fatalf("openCommandService() error = %v", err)
	}
	defer service.Close()
	tools, err := commandServiceTools(service)
	if err != nil {
		t.Fatalf("commandServiceTools() error = %v", err)
	}
	names := make([]string, 0, len(tools))
	for _, item := range tools {
		names = append(names, item.Name())
	}
	if want := []string{"command_execute", "command_template_list", "command_status"}; !reflect.DeepEqual(names, want) {
		t.Fatalf("tool names = %#v, want %#v", names, want)
	}
}
