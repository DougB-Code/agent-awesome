// This file tests persistent runtime session storage setup.
package sessionstore

import (
	"context"
	"path/filepath"
	"testing"

	"google.golang.org/adk/model"
	"google.golang.org/adk/session"
	"google.golang.org/genai"
)

// TestResolveDatabasePathUsesDataDirEnv verifies UI-owned data directories are honored.
func TestResolveDatabasePathUsesDataDirEnv(t *testing.T) {
	t.Setenv(dataDirEnv, "/tmp/agentawesome-data")
	t.Setenv(sessionDatabaseEnv, "")
	t.Setenv(memoryDatabaseEnv, "")

	got := ResolveDatabasePath("")
	want := filepath.Join("/tmp/agentawesome-data", "memory", "memory.db")
	if got != want {
		t.Fatalf("ResolveDatabasePath() = %q, want %q", got, want)
	}
}

// TestResolveDatabasePathUsesMemoryDBEnv verifies memory DB profiles are honored.
func TestResolveDatabasePathUsesMemoryDBEnv(t *testing.T) {
	t.Setenv(sessionDatabaseEnv, "")
	t.Setenv(memoryDatabaseEnv, "/tmp/memory.db")

	if got := ResolveDatabasePath(""); got != "/tmp/memory.db" {
		t.Fatalf("ResolveDatabasePath() = %q, want memory env path", got)
	}
}

// TestOpenPersistsEventsAcrossServices verifies runtime history survives reopen.
func TestOpenPersistsEventsAcrossServices(t *testing.T) {
	ctx := context.Background()
	path := filepath.Join(t.TempDir(), "sessions.db")
	first, err := Open(path)
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}
	created, err := first.Create(ctx, &session.CreateRequest{
		AppName:   "pilot",
		UserID:    "doug",
		SessionID: "chat-1",
	})
	if err != nil {
		t.Fatalf("Create() error = %v", err)
	}
	event := session.NewEvent("turn-1")
	event.Author = "user"
	event.Content = genai.NewContentFromText("remember milk", genai.RoleUser)
	event.TurnComplete = true
	event.LLMResponse = model.LLMResponse{Content: event.Content, TurnComplete: true}
	if err := first.AppendEvent(ctx, created.Session, event); err != nil {
		t.Fatalf("AppendEvent() error = %v", err)
	}

	second, err := Open(path)
	if err != nil {
		t.Fatalf("Open() second error = %v", err)
	}
	loaded, err := second.Get(ctx, &session.GetRequest{
		AppName:   "pilot",
		UserID:    "doug",
		SessionID: "chat-1",
	})
	if err != nil {
		t.Fatalf("Get() error = %v", err)
	}
	if got := loaded.Session.Events().Len(); got != 1 {
		t.Fatalf("Events().Len() = %d, want 1", got)
	}
}
