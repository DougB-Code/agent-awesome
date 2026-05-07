package platform

import (
	"path/filepath"
	"testing"
)

// TestStoreSaveAndLoad verifies platform defaults persist without secrets.
func TestStoreSaveAndLoad(t *testing.T) {
	store := NewStore(filepath.Join(t.TempDir(), "platform.json"))
	saved, err := store.Save(Config{
		ZoneName:        "agent-awesome.com",
		WorkerSourceDir: t.TempDir(),
	})
	if err != nil {
		t.Fatalf("Save() error = %v", err)
	}

	loaded, err := store.Load()
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}
	if loaded.AgentHostnameSuffix != saved.ZoneName {
		t.Fatalf("AgentHostnameSuffix = %q, want zone default %q", loaded.AgentHostnameSuffix, saved.ZoneName)
	}
	if loaded.DefaultModelProvider != "openai" {
		t.Fatalf("DefaultModelProvider = %q, want openai", loaded.DefaultModelProvider)
	}
}

// TestNewConfigNormalizesHTTPSHostnames verifies copied URLs become DNS names.
func TestNewConfigNormalizesHTTPSHostnames(t *testing.T) {
	config, err := NewConfig(Config{
		ZoneName:            "https://agent-awesome.com",
		AgentHostnameSuffix: "https://agents.agent-awesome.com/path",
		WorkerSourceDir:     t.TempDir(),
	})
	if err != nil {
		t.Fatalf("NewConfig() error = %v", err)
	}
	if config.ZoneName != "agent-awesome.com" {
		t.Fatalf("ZoneName = %q, want agent-awesome.com", config.ZoneName)
	}
	if config.AgentHostnameSuffix != "agents.agent-awesome.com" {
		t.Fatalf("AgentHostnameSuffix = %q, want agents.agent-awesome.com", config.AgentHostnameSuffix)
	}
}
