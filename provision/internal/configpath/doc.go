// Package configpath centralizes local Agent Awesome provisioning paths.
//
// Intended use cases:
//   - Resolve the user config directory for provisioning metadata.
//   - Keep OS keyring service names consistent across provisioning packages.
//   - Avoid hard-coded path fragments in command and storage packages.
//
// High-level examples:
//   - configpath.ProvisioningRoot() returns the local provisioning state root.
//   - configpath.PlatformConfigPath() returns the platform config file path.
//
// This package should not read or write files, store secrets, or know provider
// specific resource names.
package configpath
