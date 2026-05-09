package cli

import (
	"context"

	"github.com/spf13/cobra"
)

// Execute runs the Agent Awesome command tree.
func Execute(ctx context.Context) {
	cobra.CheckErr(NewRootCommand(ctx).Execute())
}

// NewRootCommand builds the Agent Awesome command tree.
func NewRootCommand(ctx context.Context) *cobra.Command {
	root := &cobra.Command{
		Use:           "agent-awesome",
		Short:         "Run Agent Awesome",
		SilenceUsage:  true,
		SilenceErrors: true,
		RunE: func(cmd *cobra.Command, args []string) error {
			return cmd.Help()
		},
	}
	root.AddCommand(newRunCommand(ctx))
	root.AddCommand(newModelsCommand(ctx))
	root.AddCommand(NewCredentialsCommand())
	return root
}
