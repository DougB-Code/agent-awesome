package cloudflare

import (
	"context"
	"fmt"
	"strings"
)

// DeleteOptions stores dependencies and paths for a live Cloudflare delete.
type DeleteOptions struct {
	WorkerDirectory string
	Runner          CommandRunner
	API             *APIClient
	WranglerEnv     map[string]string
	DryRun          bool
	Progress        ProgressFunc
}

// DeleteResult stores the outcome of one Cloudflare delete attempt.
type DeleteResult struct {
	CommandNames []string
	AccountID    string
}

// Delete removes one provisioned Cloudflare Worker and its dedicated R2 bucket.
func Delete(ctx context.Context, deployment Deployment, options DeleteOptions) (DeleteResult, error) {
	if options.Runner == nil {
		options.Runner = ExecRunner{}
	}
	if strings.TrimSpace(options.WorkerDirectory) == "" {
		return DeleteResult{}, fmt.Errorf("worker directory must not be empty")
	}
	configPath, cleanup, err := writeDeploymentWorkerConfig(options.WorkerDirectory, deployment)
	if err != nil {
		return DeleteResult{}, err
	}
	defer cleanup()

	result := DeleteResult{}
	if options.API != nil {
		result.AccountID = options.API.AccountID()
		result.CommandNames = append(result.CommandNames, "cloudflare api route delete "+deployment.Hostname+"/*")
		if err := DeleteDeploymentRoute(ctx, deployment, options.API, options.DryRun, options.Progress); err != nil {
			return result, err
		}
	}
	for _, command := range deleteCommands(deployment, options.WorkerDirectory, configPath, options.API != nil, options.WranglerEnv) {
		displayName := commandName(command)
		result.CommandNames = append(result.CommandNames, displayName)
		if options.DryRun {
			emitProgress(options.Progress, OperationEvent{Status: OperationPlanned, Command: displayName})
			continue
		}
		emitProgress(options.Progress, OperationEvent{Status: OperationRunning, Command: displayName})
		output, err := options.Runner.Run(ctx, command)
		if err != nil {
			if isIgnorableDeleteMissing(output.Output) {
				emitProgress(options.Progress, OperationEvent{Status: OperationSkipped, Command: displayName, Message: "resource already absent"})
				continue
			}
			emitProgress(options.Progress, OperationEvent{Status: OperationFailed, Command: displayName})
			return result, commandFailure(command, output, err)
		}
		emitProgress(options.Progress, OperationEvent{Status: OperationCompleted, Command: displayName})
	}
	if options.API != nil {
		result.CommandNames = append(result.CommandNames, "cloudflare api r2 bucket delete "+deployment.BucketName)
		if err := DeleteR2BucketResource(ctx, deployment, options.API, options.DryRun, options.Progress); err != nil {
			return result, err
		}
	}
	return result, nil
}

// deleteCommands builds the Wrangler commands needed to remove one deployment.
func deleteCommands(deployment Deployment, workerDirectory string, configPath string, useAPI bool, env map[string]string) []Command {
	commands := []Command{{
		Directory: workerDirectory,
		Name:      "npx",
		Arguments: []string{"wrangler", "delete", deployment.WorkerName, "--config", configPath, "--force"},
		Env:       env,
	}}
	if useAPI {
		return append(commands, Command{
			Directory: workerDirectory,
			Name:      "npx",
			Arguments: []string{"wrangler", "r2", "object", "delete", deployment.BucketName + "/" + deployment.SnapshotKey, "--remote", "--force"},
			Env:       env,
		})
	}
	commands = append(commands,
		Command{
			Directory: workerDirectory,
			Name:      "npx",
			Arguments: []string{"wrangler", "r2", "object", "delete", deployment.BucketName + "/" + deployment.SnapshotKey, "--remote", "--force"},
			Env:       env,
		},
		Command{
			Directory: workerDirectory,
			Name:      "npx",
			Arguments: []string{"wrangler", "r2", "bucket", "delete", deployment.BucketName},
			Env:       env,
		},
	)
	return commands
}

// isIgnorableDeleteMissing reports whether deletion failed because a resource is already gone.
func isIgnorableDeleteMissing(output string) bool {
	lower := strings.ToLower(output)
	return strings.Contains(lower, "not found") ||
		strings.Contains(lower, "does not exist") ||
		strings.Contains(lower, "doesn't exist") ||
		strings.Contains(lower, "no such bucket") ||
		strings.Contains(lower, "no such key") ||
		strings.Contains(lower, "specified bucket does not exist")
}
