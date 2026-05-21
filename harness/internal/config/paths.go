// This file defines default Agent Awesome configuration paths.
package config

import (
	"agentawesome/internal/config/schema"
	"os"
	"path/filepath"
)

// DefaultConfigDir returns the user config directory for Agent Awesome.
func DefaultConfigDir() string {
	dir, err := os.UserConfigDir()
	if err != nil {
		return "."
	}
	return filepath.Join(dir, schema.AppConfigDirName)
}

// DefaultModelPath returns the default model configuration path.
func DefaultModelPath() string {
	return filepath.Join(DefaultConfigDir(), schema.DefaultModelFilename)
}

// DefaultAgentPath returns the default agent configuration path.
func DefaultAgentPath() string {
	return filepath.Join(DefaultConfigDir(), schema.DefaultAgentFilename)
}

// DefaultToolPath returns the default tool configuration path.
func DefaultToolPath() string {
	return filepath.Join(DefaultToolConfigDir(), "default", schema.DefaultToolFilename)
}

// DefaultToolConfigDir returns the package directory for installed tool configs.
func DefaultToolConfigDir() string {
	return filepath.Join(DefaultConfigDir(), schema.DefaultToolConfigDirName)
}

// DefaultMCPConfigDir returns the package directory for installed MCP configs.
func DefaultMCPConfigDir() string {
	return filepath.Join(DefaultConfigDir(), schema.DefaultMCPConfigDirName)
}

// DefaultDataDir returns the user data directory for Agent Awesome.
func DefaultDataDir() string {
	return filepath.Join(DefaultConfigDir(), "data")
}

// DefaultWorkflowDefinitionsDir returns the editable workflow definition path.
func DefaultWorkflowDefinitionsDir() string {
	return filepath.Join(DefaultConfigDir(), "workflows")
}

// DefaultWorkflowDatabasePath returns the embedded workflow SQLite path.
func DefaultWorkflowDatabasePath() string {
	return filepath.Join(DefaultDataDir(), "workflow", "workflow.db")
}

// DefaultCommandDataDir returns the embedded command service data path.
func DefaultCommandDataDir() string {
	return filepath.Join(DefaultDataDir(), "command")
}

// DefaultCommandParserDir returns the editable command parser catalog path.
func DefaultCommandParserDir() string {
	return filepath.Join(DefaultConfigDir(), "command", "parsers")
}
