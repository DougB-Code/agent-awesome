// This file defines model validation and smoke-check CLI commands.
package cli

import (
	"context"
	"fmt"
	"io"
	"os"

	"agentawesome/internal/app"
	"agentawesome/internal/config"
	"github.com/spf13/cobra"
)

// newModelsCommand creates model validation and smoke-check commands.
func newModelsCommand(ctx context.Context) *cobra.Command {
	return newModelsCommandWithChecker(ctx, os.Stdout, app.CheckModel)
}

// newModelsCommandWithChecker creates model commands with injectable behavior.
func newModelsCommandWithChecker(
	ctx context.Context,
	stdout io.Writer,
	checker func(context.Context, app.ModelCheckOptions) (app.ModelCheckResult, error),
) *cobra.Command {
	cmd := &cobra.Command{
		Use:   "models",
		Short: "Validate configured model providers",
	}
	cmd.AddCommand(newModelsCheckCommand(ctx, stdout, checker))
	return cmd
}

// newModelsCheckCommand creates the provider smoke-check command.
func newModelsCheckCommand(
	ctx context.Context,
	stdout io.Writer,
	checker func(context.Context, app.ModelCheckOptions) (app.ModelCheckResult, error),
) *cobra.Command {
	opts := app.ModelCheckOptions{ModelConfigPath: config.DefaultModelPath()}
	cmd := &cobra.Command{
		Use:   "check",
		Short: "Send one prompt through the selected configured model",
		RunE: func(cmd *cobra.Command, args []string) error {
			result, err := checker(ctx, opts)
			if err != nil {
				return err
			}
			_, err = fmt.Fprintf(stdout, "Model check passed: provider=%s model_id=%s model=%s response=%q\n", result.ProviderName, result.ModelID, result.ModelName, result.ResponseText)
			return err
		},
	}
	cmd.Flags().StringVar(&opts.ModelConfigPath, "model", opts.ModelConfigPath, "model config path")
	cmd.Flags().StringVar(&opts.ProviderName, "provider", opts.ProviderName, "provider name from config")
	cmd.Flags().StringVar(&opts.ModelID, "model-id", opts.ModelID, "model id from provider config")
	cmd.Flags().StringVar(&opts.Prompt, "prompt", opts.Prompt, "smoke-check prompt")
	return cmd
}
