// This file runs live and dry-run Cloudflare apply workflows.
package cloudflare

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// ApplyOptions stores dependencies and paths for a live Cloudflare apply.
type ApplyOptions struct {
	WorkerDirectory string
	OutputDirectory string
	Runner          CommandRunner
	API             *APIClient
	WranglerEnv     map[string]string
	Secrets         SecretValues
	DryRun          bool
	HealthTimeout   time.Duration
	Progress        ProgressFunc
}

// ApplyResult stores the outcome of one Cloudflare apply attempt.
type ApplyResult struct {
	Bundle       BundlePaths
	CommandNames []string
	Health       HealthStatus
	AccountID    string
}

// Apply reconciles one per-agent Cloudflare deployment using Wrangler.
func Apply(ctx context.Context, deployment Deployment, options ApplyOptions) (ApplyResult, error) {
	if options.Runner == nil {
		options.Runner = ExecRunner{}
	}
	if options.HealthTimeout <= 0 {
		options.HealthTimeout = 2 * time.Minute
	}
	if strings.TrimSpace(options.WorkerDirectory) == "" {
		return ApplyResult{}, fmt.Errorf("worker directory must not be empty")
	}
	if strings.TrimSpace(options.OutputDirectory) == "" {
		return ApplyResult{}, fmt.Errorf("output directory must not be empty")
	}
	secrets := options.Secrets
	if secrets == nil {
		if options.DryRun {
			secrets = dryRunSecrets(deployment)
		} else {
			return ApplyResult{}, fmt.Errorf("secret values are required for live Cloudflare apply")
		}
	}
	if !options.DryRun {
		if err := validateSecretValues(deployment, secrets); err != nil {
			return ApplyResult{}, err
		}
	}
	bundle, err := WriteBundle(deployment, options.OutputDirectory)
	if err != nil {
		return ApplyResult{}, err
	}
	configPath, cleanup, err := writeDeploymentWorkerConfig(options.WorkerDirectory, deployment)
	if err != nil {
		return ApplyResult{}, err
	}
	defer cleanup()

	result := ApplyResult{Bundle: bundle}
	if options.API != nil {
		result.AccountID = options.API.AccountID()
		result.CommandNames = append(result.CommandNames,
			"cloudflare api validate route "+deployment.Hostname+"/*",
			"cloudflare api r2 bucket ensure "+deployment.BucketName,
		)
		if err := ValidateDeploymentNetwork(ctx, deployment, options.API, options.DryRun, options.Progress); err != nil {
			return result, err
		}
		if err := ReconcileR2Bucket(ctx, deployment, options.API, options.DryRun, options.Progress); err != nil {
			return result, err
		}
		commands, err := ensureWorkerScript(ctx, deployment, options)
		result.CommandNames = append(result.CommandNames, commands...)
		if err != nil {
			return result, err
		}
		for _, name := range deployment.RequiredSecrets {
			result.CommandNames = append(result.CommandNames, "cloudflare api worker secret put "+deployment.WorkerName+"/"+name)
		}
		if err := ReconcileWorkerSecrets(ctx, deployment, secrets, options.API, options.DryRun, options.Progress); err != nil {
			return result, err
		}
	}
	commands := applyCommands(deployment, options.WorkerDirectory, configPath, secrets, options.API != nil, options.API != nil, options.WranglerEnv)
	for _, command := range commands {
		displayName := commandName(command)
		result.CommandNames = append(result.CommandNames, displayName)
		if options.DryRun {
			emitProgress(options.Progress, OperationEvent{Status: OperationPlanned, Command: displayName})
			continue
		}
		emitProgress(options.Progress, OperationEvent{Status: OperationRunning, Command: displayName})
		output, err := options.Runner.Run(ctx, command)
		if err != nil {
			if isIgnorableBucketCreate(command, output.Output) {
				emitProgress(options.Progress, OperationEvent{Status: OperationSkipped, Command: displayName, Message: "bucket already exists"})
				continue
			}
			emitProgress(options.Progress, OperationEvent{Status: OperationFailed, Command: displayName})
			return result, commandFailure(command, output, err)
		}
		emitProgress(options.Progress, OperationEvent{Status: OperationCompleted, Command: displayName})
	}
	if options.DryRun {
		if options.API != nil {
			result.CommandNames = append(result.CommandNames, "cloudflare api route ensure "+deployment.Hostname+"/*")
			if err := EnsureWorkerRoute(ctx, deployment, options.API, true, options.Progress); err != nil {
				return result, err
			}
		}
		return result, nil
	}
	if options.API != nil {
		result.CommandNames = append(result.CommandNames, "cloudflare api route ensure "+deployment.Hostname+"/*")
		if err := EnsureWorkerRoute(ctx, deployment, options.API, false, options.Progress); err != nil {
			return result, err
		}
	}
	emitProgress(options.Progress, OperationEvent{Status: OperationRunning, Command: "health check", Message: deployment.Hostname})
	health, err := WaitForHealth(ctx, deployment, secrets["AGENTAWESOME_GATEWAY_TOKEN"], options.HealthTimeout)
	result.Health = health
	if err != nil {
		emitProgress(options.Progress, OperationEvent{Status: OperationFailed, Command: "health check", Message: deployment.Hostname})
		return result, err
	}
	emitProgress(options.Progress, OperationEvent{Status: OperationCompleted, Command: "health check", Message: deployment.Hostname})
	return result, nil
}

// dryRunSecrets builds placeholders so dry runs never require real secrets.
func dryRunSecrets(deployment Deployment) SecretValues {
	secrets := SecretValues{}
	for _, name := range deployment.RequiredSecrets {
		secrets[name] = "dry-run"
	}
	return secrets
}

// validateSecretValues requires every deployment secret before live remote writes.
func validateSecretValues(deployment Deployment, secrets SecretValues) error {
	for _, name := range deployment.RequiredSecrets {
		if strings.TrimSpace(secrets[name]) == "" {
			return fmt.Errorf("secret %s is required", name)
		}
	}
	return nil
}

// writeDeploymentWorkerConfig writes the final transient Worker config.
func writeDeploymentWorkerConfig(workerDirectory string, deployment Deployment) (string, func(), error) {
	return writeWorkerConfig(workerDirectory, ".agent-awesome-"+deployment.AgentID+".wrangler.jsonc", deployment.Wrangler())
}

// writeBootstrapWorkerConfig writes the first-time transient Worker config.
func writeBootstrapWorkerConfig(workerDirectory string, deployment Deployment) (string, func(), error) {
	return writeWorkerConfig(workerDirectory, ".agent-awesome-"+deployment.AgentID+".bootstrap.wrangler.jsonc", deployment.BootstrapWrangler())
}

// writeWorkerConfig writes one transient config beside Worker source files.
func writeWorkerConfig(workerDirectory string, fileName string, config WranglerConfig) (string, func(), error) {
	if err := os.MkdirAll(workerDirectory, 0o755); err != nil {
		return "", func() {}, fmt.Errorf("create worker directory: %w", err)
	}
	path := filepath.Join(workerDirectory, fileName)
	data, err := json.MarshalIndent(config, "", "\t")
	if err != nil {
		return "", func() {}, fmt.Errorf("marshal transient wrangler config: %w", err)
	}
	data = append(data, '\n')
	if err := os.WriteFile(path, data, 0o600); err != nil {
		return "", func() {}, fmt.Errorf("write transient wrangler config: %w", err)
	}
	return path, func() { _ = os.Remove(path) }, nil
}

// ensureWorkerScript creates a private Worker script before direct secret upload.
func ensureWorkerScript(ctx context.Context, deployment Deployment, options ApplyOptions) ([]string, error) {
	inspectCommand := "cloudflare api worker inspect " + deployment.WorkerName
	bootstrapDisplay := "npx wrangler deploy --config BOOTSTRAP_CONFIG --containers-rollout=immediate (if Worker is absent)"
	if options.DryRun {
		emitProgress(options.Progress, OperationEvent{Status: OperationPlanned, Command: inspectCommand})
		emitProgress(options.Progress, OperationEvent{Status: OperationPlanned, Command: bootstrapDisplay})
		return []string{inspectCommand, bootstrapDisplay}, nil
	}
	emitProgress(options.Progress, OperationEvent{Status: OperationRunning, Command: inspectCommand})
	found, err := options.API.WorkerScriptExists(ctx, deployment.WorkerName)
	if err != nil {
		emitProgress(options.Progress, OperationEvent{Status: OperationFailed, Command: inspectCommand})
		return []string{inspectCommand}, err
	}
	if found {
		emitProgress(options.Progress, OperationEvent{Status: OperationSkipped, Command: inspectCommand, Message: "Worker already exists"})
		return []string{inspectCommand}, nil
	}
	emitProgress(options.Progress, OperationEvent{Status: OperationCompleted, Command: inspectCommand, Message: "Worker is absent"})
	configPath, cleanup, err := writeBootstrapWorkerConfig(options.WorkerDirectory, deployment)
	if err != nil {
		return []string{inspectCommand}, err
	}
	defer cleanup()
	command := Command{
		Directory: options.WorkerDirectory,
		Name:      "npx",
		Arguments: []string{"wrangler", "deploy", "--config", configPath, "--containers-rollout=immediate"},
		Env:       options.WranglerEnv,
	}
	displayName := commandName(command)
	emitProgress(options.Progress, OperationEvent{Status: OperationRunning, Command: displayName})
	output, err := options.Runner.Run(ctx, command)
	if err != nil {
		emitProgress(options.Progress, OperationEvent{Status: OperationFailed, Command: displayName})
		return []string{inspectCommand, displayName}, commandFailure(command, output, err)
	}
	emitProgress(options.Progress, OperationEvent{Status: OperationCompleted, Command: displayName})
	return []string{inspectCommand, displayName}, nil
}

// applyCommands builds the Wrangler commands needed for one deployment.
func applyCommands(deployment Deployment, workerDirectory string, configPath string, secrets SecretValues, skipBucketCreate bool, skipSecretUpload bool, env map[string]string) []Command {
	var commands []Command
	if !skipBucketCreate {
		commands = append(commands, Command{
			Directory: workerDirectory,
			Name:      "npx",
			Arguments: []string{"wrangler", "r2", "bucket", "create", deployment.BucketName},
			Env:       env,
		})
	}
	if !skipSecretUpload {
		for _, name := range deployment.RequiredSecrets {
			commands = append(commands, Command{
				Directory: workerDirectory,
				Name:      "npx",
				Arguments: []string{"wrangler", "secret", "put", name, "--config", configPath},
				Stdin:     secrets[name] + "\n",
				Env:       env,
			})
		}
	}
	commands = append(commands, Command{
		Directory: workerDirectory,
		Name:      "npx",
		Arguments: []string{"wrangler", "deploy", "--config", configPath, "--containers-rollout=immediate"},
		Env:       env,
	})
	return commands
}

// commandName returns a display-safe command name without secret values.
func commandName(command Command) string {
	return command.Name + " " + strings.Join(command.Arguments, " ")
}

// isIgnorableBucketCreate reports whether bucket creation failed because it already exists.
func isIgnorableBucketCreate(command Command, output string) bool {
	if len(command.Arguments) < 5 || command.Arguments[0] != "wrangler" || command.Arguments[1] != "r2" {
		return false
	}
	lower := strings.ToLower(output)
	return strings.Contains(lower, "already exists") || strings.Contains(lower, "already own")
}
