// This file defines app plugin CLI commands.
package cli

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"time"

	"agentawesome/internal/appplugins"
	"github.com/spf13/cobra"
	"gopkg.in/yaml.v3"
)

const appPluginRenderTimeout = 5 * time.Second

// appRenderOptions stores app plugin render command flags.
type appRenderOptions struct {
	PackageDir string
	Entrypoint string
	JSON       bool
}

// appTemplateOptions stores app plugin template command flags.
type appTemplateOptions struct {
	Profile string
	JSON    bool
}

// newAppsCommand creates app plugin commands.
func newAppsCommand(ctx context.Context) *cobra.Command {
	return newAppsCommandWithWriter(ctx, os.Stdout)
}

// newAppsCommandWithWriter creates app plugin commands with injectable output.
func newAppsCommandWithWriter(ctx context.Context, stdout io.Writer) *cobra.Command {
	cmd := &cobra.Command{
		Use:   "apps",
		Short: "Render and validate app plugin packages",
	}
	cmd.AddCommand(newAppsRenderCommand(ctx, stdout))
	cmd.AddCommand(newAppsTemplateCommand(stdout))
	return cmd
}

// newAppsRenderCommand creates the Starlark app plugin renderer command.
func newAppsRenderCommand(ctx context.Context, stdout io.Writer) *cobra.Command {
	opts := appRenderOptions{Entrypoint: "app.star"}
	cmd := &cobra.Command{
		Use:   "render PACKAGE",
		Short: "Render an app plugin Starlark entrypoint as a manifest",
		Args: func(cmd *cobra.Command, args []string) error {
			if len(args) != 1 {
				return fmt.Errorf("render requires exactly one PACKAGE")
			}
			opts.PackageDir = args[0]
			return nil
		},
		RunE: func(cmd *cobra.Command, args []string) error {
			renderCtx, cancel := context.WithTimeout(ctx, appPluginRenderTimeout)
			defer cancel()
			manifest, err := appplugins.RenderPackage(renderCtx, opts.PackageDir, opts.Entrypoint)
			if err != nil {
				return err
			}
			if opts.JSON {
				return json.NewEncoder(stdout).Encode(manifest)
			}
			return yaml.NewEncoder(stdout).Encode(manifest)
		},
	}
	cmd.Flags().StringVar(&opts.Entrypoint, "entrypoint", opts.Entrypoint, "package-local Starlark entrypoint")
	cmd.Flags().BoolVar(&opts.JSON, "json", opts.JSON, "write rendered manifest as JSON")
	return cmd
}

// newAppsTemplateCommand creates app plugin template manifests.
func newAppsTemplateCommand(stdout io.Writer) *cobra.Command {
	opts := appTemplateOptions{Profile: "default"}
	cmd := &cobra.Command{
		Use:   "template KIND",
		Short: "Write an app plugin manifest template",
		Args: func(cmd *cobra.Command, args []string) error {
			if len(args) != 1 {
				return fmt.Errorf("template requires exactly one KIND")
			}
			switch args[0] {
			case "apple-calendar":
				return nil
			default:
				return fmt.Errorf("unsupported app plugin template %q", args[0])
			}
		},
		RunE: func(cmd *cobra.Command, args []string) error {
			manifest := appplugins.AppleCalendarTemplate(opts.Profile)
			if opts.JSON {
				return json.NewEncoder(stdout).Encode(manifest)
			}
			return yaml.NewEncoder(stdout).Encode(manifest)
		},
	}
	cmd.Flags().StringVar(&opts.Profile, "profile", opts.Profile, "credential profile id")
	cmd.Flags().BoolVar(&opts.JSON, "json", opts.JSON, "write manifest as JSON")
	return cmd
}
