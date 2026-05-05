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
	return filepath.Join(DefaultConfigDir(), schema.DefaultToolFilename)
}
