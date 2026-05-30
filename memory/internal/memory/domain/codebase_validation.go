// This file validates codebase catalog data models.
package domain

import (
	"errors"
	"fmt"
	"net/url"
	"path"
	"regexp"
	"strings"

	"memory/internal/memory/normalize"
	"memory/internal/memory/vocabulary"
)

var codebaseIDPattern = regexp.MustCompile(`^[a-z0-9][a-z0-9_-]*$`)
var codebaseRefPattern = regexp.MustCompile(`^[A-Za-z0-9._/@-]+$`)
var codebaseRemotePattern = regexp.MustCompile(`^[A-Za-z0-9._-]+$`)

// NormalizeUpsertCodebaseRequest validates and defaults one codebase write.
func NormalizeUpsertCodebaseRequest(req UpsertCodebaseRequest) (UpsertCodebaseRequest, error) {
	req.Actor = normalize.Default(req.Actor, vocabulary.DefaultAgentActor)
	codebase, err := NormalizeCodebase(req.Codebase)
	if err != nil {
		return req, err
	}
	req.Codebase = codebase
	return req, nil
}

// NormalizeCodebase validates and canonicalizes durable codebase metadata.
func NormalizeCodebase(value Codebase) (Codebase, error) {
	value.ID = normalizeCodebaseID(value.ID)
	value.Name = strings.TrimSpace(value.Name)
	if value.ID == "" {
		value.ID = slugID(value.Name)
	}
	if value.ID == "" {
		return value, errors.New("codebase id or name is required")
	}
	if !codebaseIDPattern.MatchString(value.ID) {
		return value, fmt.Errorf("codebase id %q is invalid", value.ID)
	}
	if value.Name == "" {
		return value, errors.New("codebase name is required")
	}
	value.Aliases = normalizeCodebaseAliases(append(value.Aliases, value.Name))
	value.RepositoryPath = strings.TrimSpace(value.RepositoryPath)
	value.DefaultRemote = strings.TrimSpace(value.DefaultRemote)
	value.DefaultBranch = strings.TrimSpace(value.DefaultBranch)
	value.Provider = normalizeProvider(value.Provider)
	value.ProviderRepository = strings.TrimSpace(value.ProviderRepository)
	value.RuntimeTargetID = strings.TrimSpace(value.RuntimeTargetID)
	value.AgentProfileID = strings.TrimSpace(value.AgentProfileID)
	if localProvider(value.Provider) && value.RepositoryPath == "" {
		return value, errors.New("repository_path is required for local codebases")
	}
	if value.DefaultRemote != "" && !validRemoteName(value.DefaultRemote) {
		return value, fmt.Errorf("default_remote %q is invalid", value.DefaultRemote)
	}
	if value.DefaultBranch != "" && !validRefName(value.DefaultBranch) {
		return value, fmt.Errorf("default_branch %q is invalid", value.DefaultBranch)
	}
	if value.Provider == "github" {
		repo, err := normalizeGitHubRepository(value.ProviderRepository)
		if err != nil {
			return value, err
		}
		value.ProviderRepository = repo
	}
	return value, nil
}

// NormalizeCodebaseIDRequest validates one codebase id lookup.
func NormalizeCodebaseIDRequest(req CodebaseIDRequest) (CodebaseIDRequest, error) {
	req.ID = normalizeCodebaseID(req.ID)
	req.Actor = normalize.Default(req.Actor, vocabulary.DefaultAgentActor)
	if req.ID == "" {
		return req, errors.New("codebase id is required")
	}
	if !codebaseIDPattern.MatchString(req.ID) {
		return req, fmt.Errorf("codebase id %q is invalid", req.ID)
	}
	return req, nil
}

// NormalizeCodebaseQuery validates one codebase list query.
func NormalizeCodebaseQuery(req CodebaseQuery) (CodebaseQuery, error) {
	req.Text = strings.TrimSpace(req.Text)
	req.Actor = normalize.Default(req.Actor, vocabulary.DefaultAgentActor)
	if req.Limit <= 0 || req.Limit > 100 {
		req.Limit = 50
	}
	return req, nil
}

// NormalizeResolveCodebaseRequest validates one human codebase lookup.
func NormalizeResolveCodebaseRequest(req ResolveCodebaseRequest) (ResolveCodebaseRequest, error) {
	req.Query = strings.TrimSpace(req.Query)
	req.Actor = normalize.Default(req.Actor, vocabulary.DefaultAgentActor)
	if req.Query == "" {
		return req, errors.New("query is required")
	}
	return req, nil
}

// normalizeCodebaseID canonicalizes an external codebase id.
func normalizeCodebaseID(value string) string {
	return strings.Trim(strings.ToLower(strings.TrimSpace(value)), "_-")
}

// normalizeCodebaseAliases lowercases, trims, and deduplicates aliases.
func normalizeCodebaseAliases(values []string) []string {
	aliases := normalize.LowerUnique(values)
	out := make([]string, 0, len(aliases))
	for _, alias := range aliases {
		if alias != "" {
			out = append(out, alias)
		}
	}
	return out
}

// normalizeProvider canonicalizes a repository provider id.
func normalizeProvider(value string) string {
	return strings.ToLower(strings.TrimSpace(value))
}

// localProvider reports whether a codebase must have a local path.
func localProvider(provider string) bool {
	return provider == "" || provider == "local"
}

// validRemoteName rejects Git remote names that can act as options or paths.
func validRemoteName(value string) bool {
	return value != "" &&
		!strings.HasPrefix(value, "-") &&
		!strings.Contains(value, "..") &&
		!strings.ContainsAny(value, `/\`) &&
		codebaseRemotePattern.MatchString(value)
}

// validRefName rejects unsafe Git ref inputs.
func validRefName(value string) bool {
	return value != "" &&
		value != "@" &&
		!strings.HasPrefix(value, "-") &&
		!strings.HasPrefix(value, "/") &&
		!strings.Contains(value, "..") &&
		!strings.Contains(value, "//") &&
		!strings.Contains(value, "@{") &&
		!strings.HasSuffix(value, "/") &&
		!strings.HasSuffix(value, ".") &&
		!strings.HasSuffix(value, ".lock") &&
		codebaseRefPattern.MatchString(value)
}

// normalizeGitHubRepository canonicalizes GitHub repository ids as owner/name.
func normalizeGitHubRepository(value string) (string, error) {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return "", errors.New("provider_repository is required for GitHub codebases")
	}
	if parsed, err := url.Parse(trimmed); err == nil && parsed.Scheme != "" {
		trimmed = parsed.Path
	}
	if colon := strings.Index(trimmed, ":"); colon > 0 && strings.Contains(trimmed[:colon], "@") {
		trimmed = trimmed[colon+1:]
	}
	trimmed = strings.Trim(strings.TrimSuffix(path.Clean(strings.Trim(trimmed, "/")), ".git"), "/")
	parts := strings.Split(trimmed, "/")
	if len(parts) == 3 && strings.EqualFold(parts[0], "github.com") {
		parts = parts[1:]
	}
	if len(parts) != 2 || parts[0] == "" || parts[1] == "" {
		return "", fmt.Errorf("provider_repository must be owner/name for GitHub")
	}
	return strings.ToLower(parts[0]) + "/" + strings.TrimSuffix(strings.ToLower(parts[1]), ".git"), nil
}

// slugID derives a stable id from a display name.
func slugID(value string) string {
	var builder strings.Builder
	lastDash := false
	for _, item := range strings.ToLower(strings.TrimSpace(value)) {
		switch {
		case item >= 'a' && item <= 'z':
			builder.WriteRune(item)
			lastDash = false
		case item >= '0' && item <= '9':
			builder.WriteRune(item)
			lastDash = false
		default:
			if !lastDash && builder.Len() > 0 {
				builder.WriteByte('-')
				lastDash = true
			}
		}
	}
	return strings.ReplaceAll(strings.Trim(builder.String(), "-"), "-", "_")
}
