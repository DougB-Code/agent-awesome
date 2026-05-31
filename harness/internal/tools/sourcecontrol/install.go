// This file implements source-control-backed AA package installation.
package sourcecontrol

import (
	"archive/zip"
	"context"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"agentawesome/internal/config"
	"agentawesome/internal/config/schema"
)

const defaultArchiveRef = "main"

var packageIDPattern = regexp.MustCompile(`[^A-Za-z0-9_.-]+`)

// Options describes one source-control package installation request.
type Options struct {
	Source     string
	PackageID  string
	ToolRoot   string
	MCPRoot    string
	AppRoot    string
	HTTPClient *http.Client
}

// Result describes one installed AA package.
type Result struct {
	Source     string `json:"source"`
	PackageID  string `json:"package_id"`
	Kind       string `json:"kind"`
	ConfigPath string `json:"config_path"`
}

// Install downloads or copies one AA package from a source-control location.
func Install(ctx context.Context, opts Options) (Result, error) {
	source, err := parseSource(strings.TrimSpace(opts.Source))
	if err != nil {
		return Result{}, err
	}
	workDir, err := os.MkdirTemp("", "aa-tool-install-*")
	if err != nil {
		return Result{}, fmt.Errorf("create install workspace: %w", err)
	}
	defer os.RemoveAll(workDir)

	root, err := materializeSource(ctx, source, opts, workDir)
	if err != nil {
		return Result{}, err
	}
	packageDir, kind, err := findPackageDirectory(root, source.Subdir)
	if err != nil {
		return Result{}, err
	}
	packageID := packageID(opts.PackageID, source.PackageHint)
	targetRoot := opts.ToolRoot
	configName := schema.DefaultToolFilename
	switch kind {
	case "mcp":
		targetRoot = opts.MCPRoot
		configName = schema.DefaultMCPFilename
	case "app":
		targetRoot = opts.AppRoot
		configName = schema.DefaultAppPluginFilename
	}
	if strings.TrimSpace(targetRoot) == "" {
		switch kind {
		case "mcp":
			targetRoot = config.DefaultMCPConfigDir()
		case "app":
			targetRoot = config.DefaultAppPluginConfigDir()
		default:
			targetRoot = config.DefaultToolConfigDir()
		}
	}
	targetDir := filepath.Join(targetRoot, packageID)
	if err := replaceDirectory(targetDir, packageDir); err != nil {
		return Result{}, err
	}
	return Result{
		Source:     opts.Source,
		PackageID:  packageID,
		Kind:       kind,
		ConfigPath: filepath.Join(targetDir, configName),
	}, nil
}

// sourceLocation stores a normalized package source.
type sourceLocation struct {
	Original    string
	LocalPath   string
	ArchiveURL  string
	Subdir      string
	PackageHint string
}

// parseSource resolves a source string into a local path or archive URL.
func parseSource(value string) (sourceLocation, error) {
	if value == "" {
		return sourceLocation{}, fmt.Errorf("source is required")
	}
	if fileInfo, err := os.Stat(value); err == nil {
		hint := filepath.Base(value)
		if !fileInfo.IsDir() {
			hint = filepath.Base(filepath.Dir(value))
		}
		return sourceLocation{Original: value, LocalPath: value, PackageHint: hint}, nil
	}
	if strings.HasPrefix(value, "file://") {
		uri, err := url.Parse(value)
		if err != nil {
			return sourceLocation{}, fmt.Errorf("parse file source: %w", err)
		}
		path := uri.Path
		if path == "" {
			return sourceLocation{}, fmt.Errorf("file source path is required")
		}
		return sourceLocation{Original: value, LocalPath: path, PackageHint: filepath.Base(path)}, nil
	}
	withoutScheme := strings.TrimPrefix(strings.TrimPrefix(value, "https://"), "http://")
	if strings.HasPrefix(withoutScheme, "github.com/") {
		return parseGitHubSource(value, strings.TrimPrefix(withoutScheme, "github.com/"))
	}
	if strings.HasPrefix(withoutScheme, "gitlab.com/") {
		return parseGitLabSource(value, strings.TrimPrefix(withoutScheme, "gitlab.com/"))
	}
	return sourceLocation{}, fmt.Errorf("unsupported source-control source %q", value)
}

// parseGitHubSource builds an archive URL from a GitHub source.
func parseGitHubSource(original string, path string) (sourceLocation, error) {
	path, ref := splitRef(path)
	parts := strings.Split(strings.Trim(path, "/"), "/")
	if len(parts) < 2 {
		return sourceLocation{}, fmt.Errorf("github source must include owner and repository")
	}
	owner, repo := parts[0], strings.TrimSuffix(parts[1], ".git")
	subdir := strings.Join(parts[2:], "/")
	if len(parts) >= 4 && parts[2] == "tree" {
		ref = parts[3]
		subdir = strings.Join(parts[4:], "/")
	}
	if ref == "" {
		ref = defaultArchiveRef
	}
	return sourceLocation{
		Original:    original,
		ArchiveURL:  fmt.Sprintf("https://github.com/%s/%s/archive/%s.zip", owner, repo, url.PathEscape(ref)),
		Subdir:      subdir,
		PackageHint: repo,
	}, nil
}

// parseGitLabSource builds an archive URL from a GitLab source.
func parseGitLabSource(original string, path string) (sourceLocation, error) {
	path, ref := splitRef(path)
	parts := strings.Split(strings.Trim(path, "/"), "/")
	if len(parts) < 2 {
		return sourceLocation{}, fmt.Errorf("gitlab source must include namespace and project")
	}
	namespace, project := parts[0], strings.TrimSuffix(parts[1], ".git")
	subdir := strings.Join(parts[2:], "/")
	if len(parts) >= 5 && parts[2] == "-" && parts[3] == "tree" {
		ref = parts[4]
		subdir = strings.Join(parts[5:], "/")
	}
	if ref == "" {
		ref = defaultArchiveRef
	}
	projectPath := url.PathEscape(namespace + "/" + project)
	return sourceLocation{
		Original:    original,
		ArchiveURL:  fmt.Sprintf("https://gitlab.com/%s/-/archive/%s/%s-%s.zip", projectPath, url.PathEscape(ref), project, url.PathEscape(ref)),
		Subdir:      subdir,
		PackageHint: project,
	}, nil
}

// splitRef separates a trailing @ref selector from a source path.
func splitRef(value string) (string, string) {
	index := strings.LastIndex(value, "@")
	if index <= 0 || index == len(value)-1 {
		return value, ""
	}
	return value[:index], value[index+1:]
}

// materializeSource copies or downloads the source into a local workspace.
func materializeSource(ctx context.Context, source sourceLocation, opts Options, workDir string) (string, error) {
	if source.LocalPath != "" {
		target := filepath.Join(workDir, "local")
		info, err := os.Stat(source.LocalPath)
		if err != nil {
			return "", fmt.Errorf("stat local source: %w", err)
		}
		if info.IsDir() {
			if err := copyDirectory(target, source.LocalPath); err != nil {
				return "", err
			}
		} else {
			if err := os.MkdirAll(target, 0o700); err != nil {
				return "", err
			}
			if err := copyFile(filepath.Join(target, filepath.Base(source.LocalPath)), source.LocalPath); err != nil {
				return "", err
			}
		}
		return target, nil
	}
	archivePath := filepath.Join(workDir, "archive.zip")
	if err := downloadArchive(ctx, opts.HTTPClient, source.ArchiveURL, archivePath); err != nil {
		return "", err
	}
	extractRoot := filepath.Join(workDir, "archive")
	if err := unzipArchive(archivePath, extractRoot); err != nil {
		return "", err
	}
	entries, err := os.ReadDir(extractRoot)
	if err != nil {
		return "", fmt.Errorf("read extracted archive: %w", err)
	}
	if len(entries) == 1 && entries[0].IsDir() {
		return filepath.Join(extractRoot, entries[0].Name()), nil
	}
	return extractRoot, nil
}

// downloadArchive downloads one repository archive.
func downloadArchive(ctx context.Context, client *http.Client, archiveURL string, target string) error {
	if client == nil {
		client = &http.Client{Timeout: 60 * time.Second}
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, archiveURL, nil)
	if err != nil {
		return fmt.Errorf("build archive request: %w", err)
	}
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("download archive: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return fmt.Errorf("download archive: HTTP %d", resp.StatusCode)
	}
	file, err := os.OpenFile(target, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o600)
	if err != nil {
		return fmt.Errorf("create archive file: %w", err)
	}
	defer file.Close()
	if _, err := io.Copy(file, resp.Body); err != nil {
		return fmt.Errorf("write archive file: %w", err)
	}
	return nil
}

// unzipArchive extracts a repository archive using zip-slip protections.
func unzipArchive(archivePath string, targetDir string) error {
	reader, err := zip.OpenReader(archivePath)
	if err != nil {
		return fmt.Errorf("open archive: %w", err)
	}
	defer reader.Close()
	for _, item := range reader.File {
		target := filepath.Join(targetDir, filepath.Clean(item.Name))
		if !strings.HasPrefix(target, filepath.Clean(targetDir)+string(os.PathSeparator)) {
			return fmt.Errorf("archive path escapes target: %s", item.Name)
		}
		if item.FileInfo().IsDir() {
			if err := os.MkdirAll(target, 0o700); err != nil {
				return err
			}
			continue
		}
		if err := os.MkdirAll(filepath.Dir(target), 0o700); err != nil {
			return err
		}
		src, err := item.Open()
		if err != nil {
			return err
		}
		if err := writeFileFromReader(target, src, item.FileInfo().Mode()); err != nil {
			src.Close()
			return err
		}
		src.Close()
	}
	return nil
}

// findPackageDirectory resolves the selected package directory and kind.
func findPackageDirectory(root string, subdir string) (string, string, error) {
	candidate := filepath.Join(root, filepath.Clean(subdir))
	if strings.TrimSpace(subdir) == "" {
		candidate = root
	}
	toolPath := filepath.Join(candidate, schema.DefaultToolFilename)
	mcpPath := filepath.Join(candidate, schema.DefaultMCPFilename)
	appPath := filepath.Join(candidate, schema.DefaultAppPluginFilename)
	toolExists := fileExists(toolPath)
	mcpExists := fileExists(mcpPath)
	appExists := fileExists(appPath)
	found := 0
	for _, exists := range []bool{toolExists, mcpExists, appExists} {
		if exists {
			found++
		}
	}
	switch {
	case found > 1:
		return "", "", fmt.Errorf("package contains multiple AA package manifests")
	case toolExists:
		return candidate, "tool", nil
	case mcpExists:
		return candidate, "mcp", nil
	case appExists:
		return candidate, "app", nil
	}
	return "", "", fmt.Errorf("package must contain %s, %s, or %s", schema.DefaultToolFilename, schema.DefaultMCPFilename, schema.DefaultAppPluginFilename)
}

// replaceDirectory overwrites a target package directory atomically enough for local config.
func replaceDirectory(target string, source string) error {
	if err := os.RemoveAll(target); err != nil {
		return fmt.Errorf("remove existing package: %w", err)
	}
	if err := os.MkdirAll(filepath.Dir(target), 0o700); err != nil {
		return fmt.Errorf("create package root: %w", err)
	}
	return copyDirectory(target, source)
}

// copyDirectory recursively copies a source directory.
func copyDirectory(target string, source string) error {
	info, err := os.Stat(source)
	if err != nil {
		return fmt.Errorf("stat source directory: %w", err)
	}
	if !info.IsDir() {
		return fmt.Errorf("source is not a directory: %s", source)
	}
	return filepath.WalkDir(source, func(path string, entry os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		relative, err := filepath.Rel(source, path)
		if err != nil {
			return err
		}
		if relative == "." {
			return os.MkdirAll(target, 0o700)
		}
		destination := filepath.Join(target, relative)
		if entry.IsDir() {
			return os.MkdirAll(destination, 0o700)
		}
		info, err := entry.Info()
		if err != nil {
			return err
		}
		return copyFile(destination, path, info.Mode())
	})
}

// copyFile copies one file to a target path.
func copyFile(target string, source string, mode ...os.FileMode) error {
	src, err := os.Open(source)
	if err != nil {
		return fmt.Errorf("open source file: %w", err)
	}
	defer src.Close()
	fileMode := os.FileMode(0o600)
	if len(mode) > 0 {
		fileMode = mode[0]
	}
	return writeFileFromReader(target, src, fileMode)
}

// writeFileFromReader writes one file from a reader.
func writeFileFromReader(target string, reader io.Reader, mode os.FileMode) error {
	if err := os.MkdirAll(filepath.Dir(target), 0o700); err != nil {
		return err
	}
	dst, err := os.OpenFile(target, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, mode.Perm())
	if err != nil {
		return fmt.Errorf("create target file: %w", err)
	}
	defer dst.Close()
	_, err = io.Copy(dst, reader)
	return err
}

// packageID returns a safe package id for local installation.
func packageID(requested string, fallback string) string {
	value := strings.TrimSpace(requested)
	if value == "" {
		value = strings.TrimSpace(fallback)
	}
	value = strings.TrimSuffix(value, ".git")
	value = packageIDPattern.ReplaceAllString(value, "-")
	value = strings.Trim(value, "-_.")
	if value == "" {
		return "tool"
	}
	return strings.ToLower(value)
}

// fileExists reports whether a regular file exists.
func fileExists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && !info.IsDir()
}
