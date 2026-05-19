// This file implements the source-control safety boundary for Git operations.
package sourcecontrol

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

var branchSafePattern = regexp.MustCompile(`^[A-Za-z0-9._/-]+$`)
var refSafePattern = regexp.MustCompile(`^[A-Za-z0-9._/@-]+$`)
var remoteSafePattern = regexp.MustCompile(`^[A-Za-z0-9._/-]+$`)

// Config stores source-control service paths and execution limits.
type Config struct {
	BuildDir string
	Timeout  time.Duration
}

// PrepareWorktreeRequest describes an isolated worktree preparation.
type PrepareWorktreeRequest struct {
	RepositoryPath string `json:"repository_path"`
	WorktreePath   string `json:"worktree_path,omitempty"`
	Branch         string `json:"branch"`
	BaseRef        string `json:"base_ref,omitempty"`
}

// WorktreeResult describes one prepared worktree.
type WorktreeResult struct {
	RepositoryPath string `json:"repository_path"`
	WorktreePath   string `json:"worktree_path"`
	Branch         string `json:"branch"`
	BaseRef        string `json:"base_ref,omitempty"`
	Prepared       bool   `json:"prepared"`
}

// StatusRequest identifies a prepared worktree.
type StatusRequest struct {
	WorktreePath string `json:"worktree_path"`
}

// StatusResult describes Git status for a prepared worktree.
type StatusResult struct {
	WorktreePath string   `json:"worktree_path"`
	Branch       string   `json:"branch"`
	Dirty        bool     `json:"dirty"`
	Entries      []string `json:"entries,omitempty"`
}

// CommitRequest describes a safe commit operation.
type CommitRequest struct {
	WorktreePath string `json:"worktree_path"`
	Message      string `json:"message"`
}

// CommitResult reports the commit produced by a safe commit operation.
type CommitResult struct {
	WorktreePath string `json:"worktree_path"`
	Commit       string `json:"commit"`
}

// PushRequest describes a safe push operation.
type PushRequest struct {
	WorktreePath string `json:"worktree_path"`
	Remote       string `json:"remote,omitempty"`
	Branch       string `json:"branch,omitempty"`
}

// PushResult reports the pushed branch.
type PushResult struct {
	WorktreePath string `json:"worktree_path"`
	Remote       string `json:"remote"`
	Branch       string `json:"branch"`
}

// BackupRequest identifies a prepared worktree to snapshot.
type BackupRequest struct {
	WorktreePath string `json:"worktree_path"`
}

// BackupResult describes a safety backup.
type BackupResult struct {
	BackupID     string `json:"backup_id"`
	BackupPath   string `json:"backup_path"`
	WorktreePath string `json:"worktree_path"`
}

// RestoreRequest identifies a backup to restore into its prepared worktree.
type RestoreRequest struct {
	WorktreePath string `json:"worktree_path"`
	BackupID     string `json:"backup_id"`
}

// CleanupRequest identifies a prepared worktree to remove.
type CleanupRequest struct {
	WorktreePath string `json:"worktree_path"`
}

// Service executes Git operations inside prepared worktrees only.
type Service struct {
	cfg Config
}

// Open validates paths and creates a source-control service.
func Open(cfg Config) (*Service, error) {
	if strings.TrimSpace(cfg.BuildDir) == "" {
		cfg.BuildDir = filepath.Join("build", "sourcecontrol")
	}
	if cfg.Timeout <= 0 {
		cfg.Timeout = 2 * time.Minute
	}
	if err := os.MkdirAll(filepath.Join(cfg.BuildDir, "backups"), 0o700); err != nil {
		return nil, fmt.Errorf("create sourcecontrol backups: %w", err)
	}
	if err := os.MkdirAll(filepath.Join(cfg.BuildDir, "worktrees"), 0o700); err != nil {
		return nil, fmt.Errorf("create sourcecontrol worktrees: %w", err)
	}
	return &Service{cfg: cfg}, nil
}

// PrepareWorktree creates an isolated branch worktree after source safety checks.
func (s *Service) PrepareWorktree(ctx context.Context, req PrepareWorktreeRequest) (WorktreeResult, error) {
	repo, err := cleanAbs(req.RepositoryPath)
	if err != nil {
		return WorktreeResult{}, err
	}
	branch := strings.TrimSpace(req.Branch)
	if err := validateBranchName(branch); err != nil {
		return WorktreeResult{}, err
	}
	if dirty, entries, err := gitDirty(ctx, s.cfg.Timeout, repo); err != nil {
		return WorktreeResult{}, err
	} else if dirty {
		return WorktreeResult{}, fmt.Errorf("repository has uncommitted changes: %s", strings.Join(entries, ", "))
	}
	baseRef := strings.TrimSpace(req.BaseRef)
	if baseRef == "" {
		baseRef = "HEAD"
	}
	if err := validateBaseRef(baseRef); err != nil {
		return WorktreeResult{}, err
	}
	worktree := strings.TrimSpace(req.WorktreePath)
	if worktree == "" {
		worktree = filepath.Join(s.cfg.BuildDir, "worktrees", safePathName(branch))
	}
	worktree, err = cleanAbs(worktree)
	if err != nil {
		return WorktreeResult{}, err
	}
	if _, err := os.Stat(worktree); err == nil {
		return WorktreeResult{}, fmt.Errorf("worktree path %q already exists", worktree)
	} else if !os.IsNotExist(err) {
		return WorktreeResult{}, err
	}
	if _, err := runGit(ctx, s.cfg.Timeout, repo, "worktree", "add", "-b", branch, worktree, baseRef); err != nil {
		return WorktreeResult{}, err
	}
	meta := preparedMetadata{
		RepositoryPath: repo,
		WorktreePath:   worktree,
		Branch:         branch,
		BaseRef:        baseRef,
		CreatedAt:      time.Now().UTC().Format(time.RFC3339Nano),
	}
	if err := writePreparedMetadata(worktree, meta); err != nil {
		return WorktreeResult{}, err
	}
	return WorktreeResult{RepositoryPath: repo, WorktreePath: worktree, Branch: branch, BaseRef: baseRef, Prepared: true}, nil
}

// Status reports Git status for a prepared worktree.
func (s *Service) Status(ctx context.Context, req StatusRequest) (StatusResult, error) {
	meta, err := requirePrepared(req.WorktreePath)
	if err != nil {
		return StatusResult{}, err
	}
	dirty, entries, err := gitDirty(ctx, s.cfg.Timeout, meta.WorktreePath)
	if err != nil {
		return StatusResult{}, err
	}
	branch, err := currentBranch(ctx, s.cfg.Timeout, meta.WorktreePath)
	if err != nil {
		return StatusResult{}, err
	}
	return StatusResult{WorktreePath: meta.WorktreePath, Branch: branch, Dirty: dirty, Entries: entries}, nil
}

// Commit stages all changes and creates a commit in a prepared worktree.
func (s *Service) Commit(ctx context.Context, req CommitRequest) (CommitResult, error) {
	meta, err := requirePrepared(req.WorktreePath)
	if err != nil {
		return CommitResult{}, err
	}
	if strings.TrimSpace(req.Message) == "" {
		return CommitResult{}, fmt.Errorf("commit message is required")
	}
	dirty, _, err := gitDirty(ctx, s.cfg.Timeout, meta.WorktreePath)
	if err != nil {
		return CommitResult{}, err
	}
	if !dirty {
		return CommitResult{}, fmt.Errorf("prepared worktree has no changes to commit")
	}
	if _, err := runGit(ctx, s.cfg.Timeout, meta.WorktreePath, "add", "-A"); err != nil {
		return CommitResult{}, err
	}
	if _, err := runGit(ctx, s.cfg.Timeout, meta.WorktreePath, "commit", "-m", req.Message); err != nil {
		return CommitResult{}, err
	}
	commit, err := runGit(ctx, s.cfg.Timeout, meta.WorktreePath, "rev-parse", "HEAD")
	if err != nil {
		return CommitResult{}, err
	}
	return CommitResult{WorktreePath: meta.WorktreePath, Commit: strings.TrimSpace(commit)}, nil
}

// Push pushes a prepared worktree branch to a remote.
func (s *Service) Push(ctx context.Context, req PushRequest) (PushResult, error) {
	meta, err := requirePrepared(req.WorktreePath)
	if err != nil {
		return PushResult{}, err
	}
	remote := strings.TrimSpace(req.Remote)
	if remote == "" {
		remote = "origin"
	}
	if err := validateRemoteName(remote); err != nil {
		return PushResult{}, err
	}
	branch := strings.TrimSpace(req.Branch)
	if branch == "" {
		branch = meta.Branch
	}
	if err := validateBranchName(branch); err != nil {
		return PushResult{}, err
	}
	if branch != meta.Branch {
		return PushResult{}, fmt.Errorf("push branch %q does not match prepared branch %q", branch, meta.Branch)
	}
	if _, err := runGit(ctx, s.cfg.Timeout, meta.WorktreePath, "push", "-u", remote, branch); err != nil {
		return PushResult{}, err
	}
	return PushResult{WorktreePath: meta.WorktreePath, Remote: remote, Branch: branch}, nil
}

// Backup snapshots non-Git worktree files under build/sourcecontrol.
func (s *Service) Backup(ctx context.Context, req BackupRequest) (BackupResult, error) {
	meta, err := requirePrepared(req.WorktreePath)
	if err != nil {
		return BackupResult{}, err
	}
	if err := ctx.Err(); err != nil {
		return BackupResult{}, err
	}
	id, err := randomID("backup")
	if err != nil {
		return BackupResult{}, err
	}
	backupPath := filepath.Join(s.cfg.BuildDir, "backups", id)
	if err := copyWorktreeFiles(meta.WorktreePath, backupPath); err != nil {
		return BackupResult{}, err
	}
	return BackupResult{BackupID: id, BackupPath: backupPath, WorktreePath: meta.WorktreePath}, nil
}

// Restore replaces worktree files with a previously captured backup.
func (s *Service) Restore(ctx context.Context, req RestoreRequest) (BackupResult, error) {
	meta, err := requirePrepared(req.WorktreePath)
	if err != nil {
		return BackupResult{}, err
	}
	if err := ctx.Err(); err != nil {
		return BackupResult{}, err
	}
	id, err := validateBackupID(req.BackupID)
	if err != nil {
		return BackupResult{}, err
	}
	backupPath := filepath.Join(s.cfg.BuildDir, "backups", id)
	if _, err := os.Stat(backupPath); err != nil {
		return BackupResult{}, fmt.Errorf("backup %q: %w", id, err)
	}
	if err := clearWorktreeFiles(meta.WorktreePath); err != nil {
		return BackupResult{}, err
	}
	if err := copyWorktreeFiles(backupPath, meta.WorktreePath); err != nil {
		return BackupResult{}, err
	}
	return BackupResult{BackupID: id, BackupPath: backupPath, WorktreePath: meta.WorktreePath}, nil
}

// CleanupWorktree removes a prepared worktree through Git and then deletes leftovers.
func (s *Service) CleanupWorktree(ctx context.Context, req CleanupRequest) (WorktreeResult, error) {
	meta, err := requirePrepared(req.WorktreePath)
	if err != nil {
		return WorktreeResult{}, err
	}
	_, _ = runGit(ctx, s.cfg.Timeout, meta.RepositoryPath, "worktree", "remove", "--force", meta.WorktreePath)
	if err := os.RemoveAll(meta.WorktreePath); err != nil {
		return WorktreeResult{}, fmt.Errorf("remove worktree: %w", err)
	}
	return WorktreeResult{RepositoryPath: meta.RepositoryPath, WorktreePath: meta.WorktreePath, Branch: meta.Branch, BaseRef: meta.BaseRef, Prepared: false}, nil
}

// gitDirty reports whether a repository has uncommitted status entries.
func gitDirty(ctx context.Context, timeout time.Duration, dir string) (bool, []string, error) {
	out, err := runGit(ctx, timeout, dir, "status", "--porcelain")
	if err != nil {
		return false, nil, err
	}
	lines := splitLines(out)
	return len(lines) > 0, lines, nil
}

// currentBranch returns the current branch name.
func currentBranch(ctx context.Context, timeout time.Duration, dir string) (string, error) {
	out, err := runGit(ctx, timeout, dir, "branch", "--show-current")
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(out), nil
}

// runGit executes one Git command and returns combined output on success.
func runGit(ctx context.Context, timeout time.Duration, dir string, args ...string) (string, error) {
	runCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	cmd := exec.CommandContext(runCtx, "git", args...)
	cmd.Dir = dir
	out, err := cmd.CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("git %s: %w: %s", strings.Join(args, " "), err, strings.TrimSpace(string(out)))
	}
	return string(out), nil
}

// writePreparedMetadata writes the AA prepared-worktree marker.
func writePreparedMetadata(worktree string, meta preparedMetadata) error {
	dir := filepath.Join(worktree, ".agent-awesome")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	data, err := json.MarshalIndent(meta, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(dir, "sourcecontrol.json"), data, 0o600)
}

// requirePrepared reads and verifies the AA prepared-worktree marker.
func requirePrepared(worktree string) (preparedMetadata, error) {
	clean, err := cleanAbs(worktree)
	if err != nil {
		return preparedMetadata{}, err
	}
	data, err := os.ReadFile(filepath.Join(clean, ".agent-awesome", "sourcecontrol.json"))
	if err != nil {
		return preparedMetadata{}, fmt.Errorf("worktree %q is not prepared by sourcecontrol: %w", clean, err)
	}
	var meta preparedMetadata
	if err := json.Unmarshal(data, &meta); err != nil {
		return preparedMetadata{}, fmt.Errorf("decode prepared worktree metadata: %w", err)
	}
	if filepath.Clean(meta.WorktreePath) != clean {
		return preparedMetadata{}, fmt.Errorf("prepared worktree metadata does not match %q", clean)
	}
	return meta, nil
}

// cleanAbs resolves one required path to an absolute clean path.
func cleanAbs(value string) (string, error) {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return "", fmt.Errorf("path is required")
	}
	abs, err := filepath.Abs(trimmed)
	if err != nil {
		return "", err
	}
	return filepath.Clean(abs), nil
}

// validateBranchName rejects Git branch names that can be parsed as options or unsafe refs.
func validateBranchName(branch string) error {
	if branch == "" ||
		strings.HasPrefix(branch, "-") ||
		strings.Contains(branch, "..") ||
		strings.Contains(branch, "//") ||
		strings.Contains(branch, "@{") ||
		strings.HasSuffix(branch, "/") ||
		strings.HasSuffix(branch, ".") ||
		strings.HasSuffix(branch, ".lock") ||
		!branchSafePattern.MatchString(branch) {
		return fmt.Errorf("branch %q is invalid", branch)
	}
	return nil
}

// validateBaseRef rejects Git revision inputs that can be parsed as options or unsafe refs.
func validateBaseRef(ref string) error {
	if ref == "" ||
		ref == "@" ||
		strings.HasPrefix(ref, "-") ||
		strings.HasPrefix(ref, "/") ||
		strings.Contains(ref, "..") ||
		strings.Contains(ref, "//") ||
		strings.Contains(ref, "@{") ||
		strings.HasSuffix(ref, "/") ||
		strings.HasSuffix(ref, ".") ||
		strings.HasSuffix(ref, ".lock") ||
		!refSafePattern.MatchString(ref) {
		return fmt.Errorf("base ref %q is invalid", ref)
	}
	return nil
}

// validateRemoteName rejects Git remote names that can be parsed as options.
func validateRemoteName(remote string) error {
	if remote == "" || strings.HasPrefix(remote, "-") || !remoteSafePattern.MatchString(remote) {
		return fmt.Errorf("remote %q is invalid", remote)
	}
	return nil
}

// copyWorktreeFiles copies regular files and directories except Git metadata.
func copyWorktreeFiles(src string, dst string) error {
	if err := os.MkdirAll(dst, 0o700); err != nil {
		return err
	}
	return filepath.WalkDir(src, func(path string, entry fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(src, path)
		if err != nil {
			return err
		}
		if rel == "." {
			return nil
		}
		if shouldSkipWorktreeRel(rel) {
			if entry.IsDir() {
				return filepath.SkipDir
			}
			return nil
		}
		target := filepath.Join(dst, rel)
		if entry.IsDir() {
			return os.MkdirAll(target, 0o700)
		}
		info, err := entry.Info()
		if err != nil {
			return err
		}
		return copyFile(path, target, info.Mode())
	})
}

// clearWorktreeFiles removes all non-Git worktree files before restore.
func clearWorktreeFiles(worktree string) error {
	entries, err := os.ReadDir(worktree)
	if err != nil {
		return err
	}
	for _, entry := range entries {
		name := entry.Name()
		if name == ".git" || name == ".agent-awesome" {
			continue
		}
		if err := os.RemoveAll(filepath.Join(worktree, name)); err != nil {
			return err
		}
	}
	return nil
}

// copyFile copies one file with the provided mode.
func copyFile(src string, dst string, mode fs.FileMode) error {
	if err := os.MkdirAll(filepath.Dir(dst), 0o700); err != nil {
		return err
	}
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.OpenFile(dst, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, mode)
	if err != nil {
		return err
	}
	defer out.Close()
	_, err = io.Copy(out, in)
	return err
}

// shouldSkipWorktreeRel reports whether a relative path is service metadata.
func shouldSkipWorktreeRel(rel string) bool {
	first := strings.Split(filepath.ToSlash(rel), "/")[0]
	return first == ".git" || first == ".agent-awesome"
}

// splitLines returns non-empty trimmed lines.
func splitLines(value string) []string {
	raw := strings.Split(strings.TrimSpace(value), "\n")
	out := make([]string, 0, len(raw))
	for _, line := range raw {
		if strings.TrimSpace(line) != "" {
			out = append(out, strings.TrimSpace(line))
		}
	}
	return out
}

// safePathName returns a filesystem-safe branch-derived name.
func safePathName(value string) string {
	replacer := strings.NewReplacer("/", "_", "\\", "_", ":", "_")
	return replacer.Replace(value)
}

// randomID creates a prefixed random hex id.
func randomID(prefix string) (string, error) {
	var bytes [8]byte
	if _, err := rand.Read(bytes[:]); err != nil {
		return "", fmt.Errorf("create %s id: %w", prefix, err)
	}
	return prefix + "_" + hex.EncodeToString(bytes[:]), nil
}

// validateBackupID rejects path traversal in backup identifiers.
func validateBackupID(value string) (string, error) {
	trimmed := strings.TrimSpace(value)
	if !regexp.MustCompile(`^backup_[a-f0-9]+$`).MatchString(trimmed) {
		return "", fmt.Errorf("backup id %q is invalid", value)
	}
	return trimmed, nil
}

// preparedMetadata stores the marker required for safe source-control operations.
type preparedMetadata struct {
	RepositoryPath string `json:"repository_path"`
	WorktreePath   string `json:"worktree_path"`
	Branch         string `json:"branch"`
	BaseRef        string `json:"base_ref,omitempty"`
	CreatedAt      string `json:"created_at"`
}
