// This file tests codebase catalog validation.
package domain

import "testing"

// TestNormalizeCodebaseDefaultsAndNormalizes verifies catalog writes are stable.
func TestNormalizeCodebaseDefaultsAndNormalizes(t *testing.T) {
	codebase, err := NormalizeCodebase(Codebase{
		Name:               " Agent Awesome ",
		Aliases:            []string{"AA", "aa", " Agent Awesome "},
		RepositoryPath:     "/repo/agent",
		DefaultRemote:      "origin",
		DefaultBranch:      "main",
		Provider:           " GitHub ",
		ProviderRepository: "https://github.com/Doug/AgentAwesome.git",
	})
	if err != nil {
		t.Fatalf("NormalizeCodebase() error = %v", err)
	}
	if codebase.ID != "agent_awesome" {
		t.Fatalf("id = %q, want agent_awesome", codebase.ID)
	}
	if codebase.Provider != "github" || codebase.ProviderRepository != "doug/agentawesome" {
		t.Fatalf("provider = %q repo = %q, want github doug/agentawesome", codebase.Provider, codebase.ProviderRepository)
	}
	if len(codebase.Aliases) != 2 || codebase.Aliases[0] != "aa" || codebase.Aliases[1] != "agent awesome" {
		t.Fatalf("aliases = %#v, want normalized aliases", codebase.Aliases)
	}
}

// TestNormalizeCodebaseRequiresLocalRepositoryPath verifies local records need a path.
func TestNormalizeCodebaseRequiresLocalRepositoryPath(t *testing.T) {
	_, err := NormalizeCodebase(Codebase{Name: "Agent Awesome"})
	if err == nil {
		t.Fatalf("NormalizeCodebase() error = nil, want repository path error")
	}
}

// TestNormalizeCodebaseValidatesGitDefaults verifies unsafe Git strings are rejected.
func TestNormalizeCodebaseValidatesGitDefaults(t *testing.T) {
	_, err := NormalizeCodebase(Codebase{Name: "Agent Awesome", RepositoryPath: "/repo", DefaultRemote: "../origin"})
	if err == nil {
		t.Fatalf("NormalizeCodebase() remote error = nil, want invalid remote")
	}
	_, err = NormalizeCodebase(Codebase{Name: "Agent Awesome", RepositoryPath: "/repo", DefaultBranch: "-main"})
	if err == nil {
		t.Fatalf("NormalizeCodebase() branch error = nil, want invalid branch")
	}
}
