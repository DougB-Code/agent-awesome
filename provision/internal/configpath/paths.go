package configpath

import (
	"fmt"
	"os"
	"path/filepath"
)

// AppConfigDirName is the shared Agent Awesome config directory and keyring service name.
const AppConfigDirName = "agent-awesome"

// ProvisioningRoot returns the local root for provisioning metadata.
func ProvisioningRoot() (string, error) {
	configDir, err := os.UserConfigDir()
	if err != nil {
		return "", fmt.Errorf("resolve user config dir: %w", err)
	}
	return filepath.Join(configDir, AppConfigDirName, "provisioning"), nil
}

// PlatformConfigPath returns the default platform configuration file path.
func PlatformConfigPath() (string, error) {
	root, err := ProvisioningRoot()
	if err != nil {
		return "", err
	}
	return filepath.Join(root, "platform.json"), nil
}
