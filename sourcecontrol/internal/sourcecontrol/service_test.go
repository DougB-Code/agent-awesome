// This file tests source-control safety operations with temporary Git repositories.
package sourcecontrol

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// TestPreparedWorktreeCommitBackupRestoreAndCleanup verifies the core safe workflow.
func TestPreparedWorktreeCommitBackupRestoreAndCleanup(t *testing.T) {
	ctx := context.Background()
	repo := initRepo(t)
	buildDir := filepath.Join(t.TempDir(), "sourcecontrol")
	service, err := Open(Config{BuildDir: buildDir, Timeout: 5 * time.Second})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}

	prepared, err := service.PrepareWorktree(ctx, PrepareWorktreeRequest{
		RepositoryPath: repo,
		WorktreePath:   testWorktreePath(buildDir, "worktree"),
		Branch:         "feature/test",
	})
	if err != nil {
		t.Fatalf("PrepareWorktree() error = %v", err)
	}
	if !prepared.Prepared {
		t.Fatalf("prepared = %#v, want prepared", prepared)
	}
	if err := os.WriteFile(filepath.Join(prepared.WorktreePath, "feature.txt"), []byte("first"), 0o600); err != nil {
		t.Fatalf("WriteFile() error = %v", err)
	}
	status, err := service.Status(ctx, StatusRequest{WorktreePath: prepared.WorktreePath})
	if err != nil {
		t.Fatalf("Status() error = %v", err)
	}
	if !status.Dirty {
		t.Fatalf("Status() = %#v, want dirty", status)
	}
	backup, err := service.Backup(ctx, BackupRequest{WorktreePath: prepared.WorktreePath})
	if err != nil {
		t.Fatalf("Backup() error = %v", err)
	}
	if err := os.WriteFile(filepath.Join(prepared.WorktreePath, "feature.txt"), []byte("mutated"), 0o600); err != nil {
		t.Fatalf("WriteFile() error = %v", err)
	}
	if _, err := service.Restore(ctx, RestoreRequest{WorktreePath: prepared.WorktreePath, BackupID: backup.BackupID}); err != nil {
		t.Fatalf("Restore() error = %v", err)
	}
	restored, err := os.ReadFile(filepath.Join(prepared.WorktreePath, "feature.txt"))
	if err != nil {
		t.Fatalf("ReadFile() error = %v", err)
	}
	if string(restored) != "first" {
		t.Fatalf("restored = %q, want first", restored)
	}
	commit, err := service.Commit(ctx, CommitRequest{WorktreePath: prepared.WorktreePath, Message: "add feature"})
	if err != nil {
		t.Fatalf("Commit() error = %v", err)
	}
	if strings.TrimSpace(commit.Commit) == "" {
		t.Fatalf("Commit() = %#v, want commit hash", commit)
	}
	cleanup, err := service.CleanupWorktree(ctx, CleanupRequest{WorktreePath: prepared.WorktreePath})
	if err != nil {
		t.Fatalf("CleanupWorktree() error = %v", err)
	}
	if cleanup.Prepared {
		t.Fatalf("cleanup = %#v, want unprepared", cleanup)
	}
	if _, err := os.Stat(prepared.WorktreePath); !os.IsNotExist(err) {
		t.Fatalf("worktree still exists or stat failed unexpectedly: %v", err)
	}
}

// TestPrepareWorktreeRejectsDirtyRepository verifies dirty source repos are protected.
func TestPrepareWorktreeRejectsDirtyRepository(t *testing.T) {
	ctx := context.Background()
	repo := initRepo(t)
	if err := os.WriteFile(filepath.Join(repo, "dirty.txt"), []byte("dirty"), 0o600); err != nil {
		t.Fatalf("WriteFile() error = %v", err)
	}
	buildDir := filepath.Join(t.TempDir(), "sourcecontrol")
	service, err := Open(Config{BuildDir: buildDir, Timeout: 5 * time.Second})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}

	_, err = service.PrepareWorktree(ctx, PrepareWorktreeRequest{
		RepositoryPath: repo,
		WorktreePath:   testWorktreePath(buildDir, "worktree"),
		Branch:         "feature/dirty",
	})
	if err == nil || !strings.Contains(err.Error(), "uncommitted") {
		t.Fatalf("PrepareWorktree() error = %v, want dirty rejection", err)
	}
}

// TestPrepareWorktreeRejectsUnsafeBranch verifies branch names cannot act as Git options.
func TestPrepareWorktreeRejectsUnsafeBranch(t *testing.T) {
	ctx := context.Background()
	repo := initRepo(t)
	buildDir := filepath.Join(t.TempDir(), "sourcecontrol")
	service, err := Open(Config{BuildDir: buildDir, Timeout: 5 * time.Second})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}

	_, err = service.PrepareWorktree(ctx, PrepareWorktreeRequest{
		RepositoryPath: repo,
		WorktreePath:   testWorktreePath(buildDir, "worktree"),
		Branch:         "-unsafe",
	})
	if err == nil || !strings.Contains(err.Error(), "branch") {
		t.Fatalf("PrepareWorktree() error = %v, want unsafe branch rejection", err)
	}
}

// TestPrepareWorktreeRejectsUnsafeBaseRef verifies base refs cannot act as Git options.
func TestPrepareWorktreeRejectsUnsafeBaseRef(t *testing.T) {
	ctx := context.Background()
	repo := initRepo(t)
	buildDir := filepath.Join(t.TempDir(), "sourcecontrol")
	service, err := Open(Config{BuildDir: buildDir, Timeout: 5 * time.Second})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}

	_, err = service.PrepareWorktree(ctx, PrepareWorktreeRequest{
		RepositoryPath: repo,
		WorktreePath:   testWorktreePath(buildDir, "worktree"),
		Branch:         "feature/base",
		BaseRef:        "-unsafe",
	})
	if err == nil || !strings.Contains(err.Error(), "base ref") {
		t.Fatalf("PrepareWorktree() error = %v, want unsafe base ref rejection", err)
	}
}

// TestUnsafeOperationsRequirePreparedWorktree verifies marker enforcement.
func TestUnsafeOperationsRequirePreparedWorktree(t *testing.T) {
	buildDir := filepath.Join(t.TempDir(), "sourcecontrol")
	service, err := Open(Config{BuildDir: buildDir, Timeout: 5 * time.Second})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}
	unprepared := testWorktreePath(buildDir, "unprepared")
	if err := os.MkdirAll(unprepared, 0o700); err != nil {
		t.Fatalf("MkdirAll() error = %v", err)
	}

	_, err = service.Status(context.Background(), StatusRequest{WorktreePath: unprepared})
	if err == nil || !strings.Contains(err.Error(), "not prepared") {
		t.Fatalf("Status() error = %v, want prepared marker rejection", err)
	}
}

// TestPushRequiresPreparedBranch verifies push uses the prepared branch only.
func TestPushRequiresPreparedBranch(t *testing.T) {
	ctx := context.Background()
	repo := initRepo(t)
	remote := filepath.Join(t.TempDir(), "remote.git")
	runCmd(t, "", "git", "init", "--bare", remote)
	runCmd(t, repo, "git", "remote", "add", "origin", remote)
	buildDir := filepath.Join(t.TempDir(), "sourcecontrol")
	service, err := Open(Config{BuildDir: buildDir, Timeout: 5 * time.Second})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}
	prepared, err := service.PrepareWorktree(ctx, PrepareWorktreeRequest{
		RepositoryPath: repo,
		WorktreePath:   testWorktreePath(buildDir, "worktree"),
		Branch:         "feature/push",
	})
	if err != nil {
		t.Fatalf("PrepareWorktree() error = %v", err)
	}
	if err := os.WriteFile(filepath.Join(prepared.WorktreePath, "push.txt"), []byte("push"), 0o600); err != nil {
		t.Fatalf("WriteFile() error = %v", err)
	}
	if _, err := service.Commit(ctx, CommitRequest{WorktreePath: prepared.WorktreePath, Message: "push feature"}); err != nil {
		t.Fatalf("Commit() error = %v", err)
	}
	if _, err := service.Push(ctx, PushRequest{WorktreePath: prepared.WorktreePath, Branch: "main"}); err == nil || !strings.Contains(err.Error(), "does not match") {
		t.Fatalf("Push() mismatched branch error = %v, want rejection", err)
	}
	if _, err := service.Push(ctx, PushRequest{WorktreePath: prepared.WorktreePath, Remote: "-unsafe"}); err == nil || !strings.Contains(err.Error(), "remote") {
		t.Fatalf("Push() unsafe remote error = %v, want rejection", err)
	}
	if _, err := service.Push(ctx, PushRequest{WorktreePath: prepared.WorktreePath, Remote: "missing"}); err == nil || !strings.Contains(err.Error(), "not configured") {
		t.Fatalf("Push() unconfigured remote error = %v, want rejection", err)
	}
	if _, err := service.Push(ctx, PushRequest{WorktreePath: prepared.WorktreePath}); err != nil {
		t.Fatalf("Push() error = %v", err)
	}
}

// TestPrepareWorktreeRejectsOutsideBuildWorktree verifies cleanup cannot target arbitrary paths.
func TestPrepareWorktreeRejectsOutsideBuildWorktree(t *testing.T) {
	ctx := context.Background()
	repo := initRepo(t)
	buildDir := filepath.Join(t.TempDir(), "sourcecontrol")
	service, err := Open(Config{BuildDir: buildDir, Timeout: 5 * time.Second})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}

	_, err = service.PrepareWorktree(ctx, PrepareWorktreeRequest{
		RepositoryPath: repo,
		WorktreePath:   filepath.Join(t.TempDir(), "outside"),
		Branch:         "feature/outside",
	})
	if err == nil || !strings.Contains(err.Error(), "outside sourcecontrol worktree root") {
		t.Fatalf("PrepareWorktree() error = %v, want worktree root rejection", err)
	}
}

// TestPrepareWorktreeRejectsSymlinkParentEscape verifies parent symlinks cannot redirect worktrees.
func TestPrepareWorktreeRejectsSymlinkParentEscape(t *testing.T) {
	ctx := context.Background()
	repo := initRepo(t)
	buildDir := filepath.Join(t.TempDir(), "sourcecontrol")
	service, err := Open(Config{BuildDir: buildDir, Timeout: 5 * time.Second})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}
	outside := t.TempDir()
	link := testWorktreePath(buildDir, "escape")
	if err := os.Symlink(outside, link); err != nil {
		t.Skipf("symlink unavailable: %v", err)
	}

	_, err = service.PrepareWorktree(ctx, PrepareWorktreeRequest{
		RepositoryPath: repo,
		WorktreePath:   filepath.Join(link, "worktree"),
		Branch:         "feature/symlink-parent",
	})
	if err == nil || !strings.Contains(err.Error(), "escapes sourcecontrol worktree root") {
		t.Fatalf("PrepareWorktree() error = %v, want symlink parent rejection", err)
	}
}

// TestPreparedOperationRejectsSymlinkWorktree verifies prepared markers cannot be reached through symlinks.
func TestPreparedOperationRejectsSymlinkWorktree(t *testing.T) {
	buildDir := filepath.Join(t.TempDir(), "sourcecontrol")
	service, err := Open(Config{BuildDir: buildDir, Timeout: 5 * time.Second})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}
	outside := t.TempDir()
	link := testWorktreePath(buildDir, "prepared-link")
	if err := os.Symlink(outside, link); err != nil {
		t.Skipf("symlink unavailable: %v", err)
	}
	if err := writePreparedMetadata(outside, preparedMetadata{
		RepositoryPath: t.TempDir(),
		WorktreePath:   link,
		Branch:         "feature/fake",
	}); err != nil {
		t.Fatalf("writePreparedMetadata() error = %v", err)
	}

	_, err = service.Status(context.Background(), StatusRequest{WorktreePath: link})
	if err == nil || !strings.Contains(err.Error(), "resolves outside") {
		t.Fatalf("Status() error = %v, want symlink prepared worktree rejection", err)
	}
}

// TestBackupSkipsSymlinkWithoutCopyingTarget verifies backups do not dereference symlinks.
func TestBackupSkipsSymlinkWithoutCopyingTarget(t *testing.T) {
	ctx := context.Background()
	repo := initRepo(t)
	buildDir := filepath.Join(t.TempDir(), "sourcecontrol")
	service, err := Open(Config{BuildDir: buildDir, Timeout: 5 * time.Second})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}
	prepared, err := service.PrepareWorktree(ctx, PrepareWorktreeRequest{
		RepositoryPath: repo,
		WorktreePath:   testWorktreePath(buildDir, "symlink"),
		Branch:         "feature/symlink",
	})
	if err != nil {
		t.Fatalf("PrepareWorktree() error = %v", err)
	}
	secret := filepath.Join(t.TempDir(), "secret.txt")
	if err := os.WriteFile(secret, []byte("outside secret"), 0o600); err != nil {
		t.Fatalf("WriteFile() error = %v", err)
	}
	link := filepath.Join(prepared.WorktreePath, "linked-secret")
	if err := os.Symlink(secret, link); err != nil {
		t.Skipf("symlink unavailable: %v", err)
	}

	backup, err := service.Backup(ctx, BackupRequest{WorktreePath: prepared.WorktreePath})
	if err != nil {
		t.Fatalf("Backup() error = %v", err)
	}
	backupLink := filepath.Join(backup.BackupPath, "linked-secret")
	if _, err := os.Lstat(backupLink); !os.IsNotExist(err) {
		t.Fatalf("backup symlink stat error = %v, want missing symlink", err)
	}
	if entries, err := os.ReadDir(backup.BackupPath); err != nil {
		t.Fatalf("ReadDir() error = %v", err)
	} else if len(entries) != 1 || entries[0].Name() != "README.md" {
		t.Fatalf("backup entries = %#v, want only tracked regular files", entries)
	}
}

// initRepo creates a committed temporary Git repository.
func initRepo(t *testing.T) string {
	t.Helper()
	repo := t.TempDir()
	runCmd(t, repo, "git", "init", "-b", "main")
	runCmd(t, repo, "git", "config", "user.email", "aa@example.test")
	runCmd(t, repo, "git", "config", "user.name", "Agent Awesome Test")
	if err := os.WriteFile(filepath.Join(repo, "README.md"), []byte("root\n"), 0o600); err != nil {
		t.Fatalf("WriteFile() error = %v", err)
	}
	runCmd(t, repo, "git", "add", "README.md")
	runCmd(t, repo, "git", "commit", "-m", "initial")
	return repo
}

// testWorktreePath returns a sourcecontrol-managed worktree test path.
func testWorktreePath(buildDir string, name string) string {
	return filepath.Join(buildDir, "worktrees", name)
}

// runCmd executes one test setup command.
func runCmd(t *testing.T, dir string, name string, args ...string) {
	t.Helper()
	cmd := exec.Command(name, args...)
	cmd.Dir = dir
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("%s %s: %v: %s", name, strings.Join(args, " "), err, strings.TrimSpace(string(out)))
	}
}
