// This file tests command daemon configuration parsing.
package app

import "testing"

// TestParseConfigAcceptsParserDirOverride verifies parser catalogs are configurable.
func TestParseConfigAcceptsParserDirOverride(t *testing.T) {
	cfg, err := ParseConfig([]string{
		"-data", t.TempDir(),
		"-parser-dir", t.TempDir(),
		"-templates-json", `[{
			"id":"codex_plan",
			"description":"Run Codex planning",
			"executable":"codex",
			"args":["exec","--json"],
			"output_contract":{"format":"json","source":"stdout"},
			"parameter_schema":{"type":"object"},
			"validation_schema":{"type":"object"},
			"artifact_globs":["plan.json"],
			"require_approval":false
		}]`,
	}, "commandd")
	if err != nil {
		t.Fatalf("ParseConfig() error = %v", err)
	}

	if cfg.Command.ParserDir == "" || len(cfg.Command.Templates) != 1 {
		t.Fatalf("config = %#v, want parser dir and template", cfg)
	}
	template := cfg.Command.Templates[0]
	if template.OutputContract.Format != "json" ||
		template.ParameterSchema["type"] != "object" ||
		template.ValidationSchema["type"] != "object" ||
		len(template.ArtifactGlobs) != 1 {
		t.Fatalf("template = %#v, want structured contract fields", template)
	}
}

// TestParseConfigReadsParserDirEnvironment verifies the documented environment override.
func TestParseConfigReadsParserDirEnvironment(t *testing.T) {
	parserDir := t.TempDir()
	t.Setenv("AGENTAWESOME_COMMAND_PARSER_DIR", parserDir)

	cfg, err := ParseConfig([]string{"-data", t.TempDir()}, "commandd")
	if err != nil {
		t.Fatalf("ParseConfig() error = %v", err)
	}

	if cfg.Command.ParserDir != parserDir {
		t.Fatalf("ParserDir = %q, want %q", cfg.Command.ParserDir, parserDir)
	}
}

// TestParseConfigUsesDefaultParserDir verifies OS config parser defaults are installed.
func TestParseConfigUsesDefaultParserDir(t *testing.T) {
	t.Setenv("AGENTAWESOME_COMMAND_PARSER_DIR", "")

	cfg, err := ParseConfig([]string{"-data", t.TempDir()}, "commandd")
	if err != nil {
		t.Fatalf("ParseConfig() error = %v", err)
	}

	if cfg.Command.ParserDir != defaultParserDir() {
		t.Fatalf("ParserDir = %q, want default %q", cfg.Command.ParserDir, defaultParserDir())
	}
}
