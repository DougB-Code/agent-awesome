// Package main resolves platform and provisioning state stores.
package main

import (
	"errors"
	"path/filepath"

	"agentprovision/internal/platform"
	"agentprovision/internal/state"
)

// platformStore returns the configured platform config store.
func platformStore(path string) (platform.Store, error) {
	if path != "" {
		absolute, err := filepath.Abs(path)
		if err != nil {
			return platform.Store{}, err
		}
		return platform.NewStore(absolute), nil
	}
	return platform.DefaultStore()
}

// loadOptionalPlatformConfig loads platform config when present.
func loadOptionalPlatformConfig(path string) (platform.Config, bool, error) {
	store, err := platformStore(path)
	if err != nil {
		return platform.Config{}, false, err
	}
	config, err := store.Load()
	if errors.Is(err, platform.ErrNotFound) {
		return platform.Config{}, false, nil
	}
	if err != nil {
		return platform.Config{}, false, err
	}
	return config, true, nil
}

// provisionStore returns the configured local provisioning state store.
func provisionStore(stateDir string) (state.Store, error) {
	if stateDir != "" {
		absolute, err := filepath.Abs(stateDir)
		if err != nil {
			return state.Store{}, err
		}
		return state.NewStore(absolute), nil
	}
	return state.DefaultStore()
}
