// This file tests application runtime option handling.
package app

import (
	"reflect"
	"testing"

	"agentawesome/internal/config/schema"
)

func TestLocalExecCommandTemplatesConvertsCLISurfaces(t *testing.T) {
	templates, err := localExecCommandTemplates(&schema.Tools{
		LocalExec: schema.LocalExec{
			Enabled:               true,
			DefaultTimeout:        "11s",
			DefaultMaxOutputBytes: 2048,
			Commands: []schema.LocalExecCommand{
				{
					Name:        "git",
					Description: "Run documented Git CLI subcommands.",
					Executable:  "git",
					Surface: schema.CommandSurface{
						GlobalFlags: []schema.CommandFlag{{
							Name:        "-C",
							Description: "Run as if Git started in the given path.",
						}},
						Subcommands: []schema.CommandSubcommand{{
							Name:        "status",
							Description: "Show working tree status.",
							Flags: []schema.CommandFlag{{
								Name:        "--short",
								Description: "Use short status output.",
							}},
						}},
					},
					Operations: []schema.CommandOperation{{
						Name:        "status",
						Description: "Read repository status.",
						Args:        []string{"status", "--short"},
						Output:      schema.CommandOutput{Format: "text", Source: "stdout"},
					}},
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
	if template.ID != "git.status" || template.Description != "Read repository status." || template.Executable != "git" {
		t.Fatalf("template identity = %#v, want git status operation", template)
	}
	if want := []string{"status", "--short"}; !reflect.DeepEqual(template.Args, want) {
		t.Fatalf("template.Args = %#v, want %#v", template.Args, want)
	}
	if template.ParameterSchema != nil {
		t.Fatalf("template.ParameterSchema = %#v, want nil", template.ParameterSchema)
	}
	if got, want := template.Surface.Subcommands[0].Name, "status"; got != want {
		t.Fatalf("template.Surface.Subcommands[0].Name = %q, want %q", got, want)
	}
}

func TestCommandServiceTemplatesMergesJSONAndLocalExecCommands(t *testing.T) {
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
