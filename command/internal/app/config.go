// This file parses command daemon command-line configuration.
package app

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"command/internal/command"
)

// Config stores command daemon process settings.
type Config struct {
	ListenAddress  string
	DataDir        string
	AllowedWorkdir repeatedStrings
	AllowedEnv     repeatedStrings
	TemplatesJSON  string
	ParserDir      string
	CheckConfig    bool
	Command        command.Config
}

// ParseConfig parses command daemon flags and environment defaults.
func ParseConfig(args []string, processName string) (Config, error) {
	if strings.TrimSpace(processName) == "" {
		processName = "commandd"
	}
	defaultData := filepath.Join(defaultDataDir(), "command")
	cfg := Config{
		ListenAddress:  envString("AGENTAWESOME_COMMAND_ADDR", "127.0.0.1:8093"),
		DataDir:        envString("AGENTAWESOME_COMMAND_DATA_DIR", defaultData),
		TemplatesJSON:  envString("AGENTAWESOME_COMMAND_TEMPLATES_JSON", ""),
		ParserDir:      envString("AGENTAWESOME_COMMAND_PARSER_DIR", defaultParserDir()),
		AllowedWorkdir: repeatedStrings(envList("AGENTAWESOME_COMMAND_ALLOWED_WORKDIRS", []string{"."})),
		AllowedEnv:     repeatedStrings(envList("AGENTAWESOME_COMMAND_ALLOWED_ENV", []string{"PATH", "HOME", "USER", "TMPDIR"})),
	}
	commandCfg := command.Config{
		DefaultTimeout:   envDuration("AGENTAWESOME_COMMAND_TIMEOUT", 10*time.Minute),
		DefaultMaxOutput: envInt64("AGENTAWESOME_COMMAND_MAX_OUTPUT_BYTES", 64<<10),
		ApprovalTTL:      envDuration("AGENTAWESOME_COMMAND_APPROVAL_TTL", 10*time.Minute),
		RequireApproval:  envBool("AGENTAWESOME_COMMAND_REQUIRE_APPROVAL", true),
		AllowArbitrary:   envBool("AGENTAWESOME_COMMAND_ALLOW_ARBITRARY", true),
	}
	fs := flag.NewFlagSet(processName, flag.ContinueOnError)
	fs.StringVar(&cfg.ListenAddress, "addr", cfg.ListenAddress, processName+" listen address")
	fs.StringVar(&cfg.DataDir, "data", cfg.DataDir, "command service data directory")
	fs.Var(&cfg.AllowedWorkdir, "allow-workdir", "allowed command working directory root")
	fs.Var(&cfg.AllowedEnv, "allow-env", "allowed process environment variable")
	fs.StringVar(&cfg.TemplatesJSON, "templates-json", cfg.TemplatesJSON, "JSON command template list")
	fs.StringVar(&cfg.ParserDir, "parser-dir", cfg.ParserDir, "Starlark command parser directory")
	fs.DurationVar(&commandCfg.DefaultTimeout, "timeout", commandCfg.DefaultTimeout, "default command timeout")
	fs.Int64Var(&commandCfg.DefaultMaxOutput, "max-output-bytes", commandCfg.DefaultMaxOutput, "default output tail byte limit")
	fs.DurationVar(&commandCfg.ApprovalTTL, "approval-ttl", commandCfg.ApprovalTTL, "command approval expiry")
	fs.BoolVar(&commandCfg.RequireApproval, "require-approval", commandCfg.RequireApproval, "require approval for configured templates by default")
	fs.BoolVar(&commandCfg.AllowArbitrary, "allow-arbitrary", commandCfg.AllowArbitrary, "allow arbitrary reviewed command proposals")
	fs.BoolVar(&cfg.CheckConfig, "check-config", cfg.CheckConfig, "validate configuration and exit")
	if err := fs.Parse(args); err != nil {
		return Config{}, err
	}
	templates, err := parseTemplates(cfg.TemplatesJSON)
	if err != nil {
		return Config{}, err
	}
	commandCfg.DataDir = cfg.DataDir
	commandCfg.AllowedWorkdirs = []string(cfg.AllowedWorkdir)
	commandCfg.AllowedEnv = []string(cfg.AllowedEnv)
	commandCfg.Templates = templates
	commandCfg.ParserDir = cfg.ParserDir
	cfg.Command = commandCfg
	return cfg, cfg.Validate()
}

// Validate reports unsafe or incomplete command daemon settings.
func (c Config) Validate() error {
	if strings.TrimSpace(c.ListenAddress) == "" {
		return fmt.Errorf("listen address is required")
	}
	if strings.TrimSpace(c.DataDir) == "" {
		return fmt.Errorf("data directory is required")
	}
	if strings.TrimSpace(c.ParserDir) == "" {
		return fmt.Errorf("parser directory is required")
	}
	return nil
}

// parseTemplates decodes JSON command templates from config.
func parseTemplates(value string) ([]command.Template, error) {
	if strings.TrimSpace(value) == "" {
		return nil, nil
	}
	var raw []rawTemplate
	if err := json.Unmarshal([]byte(value), &raw); err != nil {
		return nil, fmt.Errorf("decode command templates: %w", err)
	}
	templates := make([]command.Template, 0, len(raw))
	for _, item := range raw {
		timeout, err := parseOptionalDuration(item.Timeout)
		if err != nil {
			return nil, fmt.Errorf("template %q timeout: %w", item.ID, err)
		}
		templates = append(templates, command.Template{
			ID:                     item.ID,
			Description:            item.Description,
			Executable:             item.Executable,
			Args:                   item.Args,
			Stdin:                  item.Stdin,
			WorkingDir:             item.WorkingDir,
			Env:                    item.Env,
			Timeout:                timeout,
			MaxOutputBytes:         item.MaxOutputBytes,
			RequireApproval:        item.RequireApproval,
			ParameterSchema:        item.ParameterSchema,
			OutputContract:         item.OutputContract,
			ParserID:               item.ParserID,
			OutputSource:           item.OutputSource,
			ArtifactGlobs:          item.ArtifactGlobs,
			EnvironmentPolicy:      item.EnvironmentPolicy,
			WorkingDirectoryPolicy: item.WorkingDirectoryPolicy,
			ValidationSchema:       item.ValidationSchema,
		})
	}
	return templates, nil
}

// parseOptionalDuration parses an optional duration string.
func parseOptionalDuration(value string) (time.Duration, error) {
	if strings.TrimSpace(value) == "" {
		return 0, nil
	}
	return time.ParseDuration(value)
}

// rawTemplate stores JSON-friendly command template fields.
type rawTemplate struct {
	ID                     string                 `json:"id"`
	Description            string                 `json:"description"`
	Executable             string                 `json:"executable"`
	Args                   []string               `json:"args"`
	Stdin                  string                 `json:"stdin"`
	WorkingDir             string                 `json:"working_dir"`
	Env                    map[string]string      `json:"env"`
	Timeout                string                 `json:"timeout"`
	MaxOutputBytes         int64                  `json:"max_output_bytes"`
	RequireApproval        bool                   `json:"require_approval"`
	ParameterSchema        map[string]any         `json:"parameter_schema"`
	OutputContract         command.OutputContract `json:"output_contract"`
	ParserID               string                 `json:"parser_id"`
	OutputSource           string                 `json:"output_source"`
	ArtifactGlobs          []string               `json:"artifact_globs"`
	EnvironmentPolicy      map[string]any         `json:"environment_policy"`
	WorkingDirectoryPolicy string                 `json:"working_directory_policy"`
	ValidationSchema       map[string]any         `json:"validation_schema"`
}

// repeatedStrings stores repeatable CLI string flags.
type repeatedStrings []string

// String returns the comma-joined flag value.
func (r repeatedStrings) String() string {
	return strings.Join(r, ",")
}

// Set appends one flag value.
func (r *repeatedStrings) Set(value string) error {
	*r = append(*r, value)
	return nil
}

// envString returns a string environment value or fallback.
func envString(name string, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(name)); value != "" {
		return value
	}
	return fallback
}

// envBool returns a bool environment value or fallback.
func envBool(name string, fallback bool) bool {
	value := strings.TrimSpace(os.Getenv(name))
	if value == "" {
		return fallback
	}
	return value == "1" || strings.EqualFold(value, "true") || strings.EqualFold(value, "yes")
}

// envDuration returns a duration environment value or fallback.
func envDuration(name string, fallback time.Duration) time.Duration {
	value := strings.TrimSpace(os.Getenv(name))
	if value == "" {
		return fallback
	}
	parsed, err := time.ParseDuration(value)
	if err != nil {
		return fallback
	}
	return parsed
}

// envInt64 returns an int64 environment value or fallback.
func envInt64(name string, fallback int64) int64 {
	value := strings.TrimSpace(os.Getenv(name))
	if value == "" {
		return fallback
	}
	var parsed int64
	if _, err := fmt.Sscan(value, &parsed); err != nil {
		return fallback
	}
	return parsed
}

// envList returns a comma-separated string list environment value.
func envList(name string, fallback []string) []string {
	value := strings.TrimSpace(os.Getenv(name))
	if value == "" {
		return fallback
	}
	items := strings.Split(value, ",")
	out := make([]string, 0, len(items))
	for _, item := range items {
		if trimmed := strings.TrimSpace(item); trimmed != "" {
			out = append(out, trimmed)
		}
	}
	return out
}

// defaultDataDir returns the command service data root.
func defaultDataDir() string {
	if dir := strings.TrimSpace(os.Getenv("AGENTAWESOME_DATA_DIR")); dir != "" {
		return dir
	}
	configDir, err := os.UserConfigDir()
	if err != nil {
		return filepath.Join(".", "agent-awesome", "data")
	}
	return filepath.Join(configDir, "agent-awesome", "data")
}

// defaultParserDir returns the default file-backed parser catalog path.
func defaultParserDir() string {
	if dir := strings.TrimSpace(os.Getenv("AGENTAWESOME_COMMAND_PARSER_DIR")); dir != "" {
		return dir
	}
	configDir, err := os.UserConfigDir()
	if err != nil {
		return filepath.Join(".", "agent-awesome", "command", "parsers")
	}
	return filepath.Join(configDir, "agent-awesome", "command", "parsers")
}
