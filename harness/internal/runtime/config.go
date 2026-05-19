// This file builds and executes ADK runtime launcher configuration.
package runtime

import (
	"context"
	"errors"
	"flag"
	"fmt"

	agentpkg "agentawesome/internal/agent"
	"agentawesome/internal/runtime/callbacks"
	"agentawesome/internal/tools/toolbundle"
	aaagent "google.golang.org/adk/agent"
	"google.golang.org/adk/agent/llmagent"
	"google.golang.org/adk/cmd/launcher"
	"google.golang.org/adk/cmd/launcher/universal"
	"google.golang.org/adk/cmd/launcher/web"
	"google.golang.org/adk/cmd/launcher/web/a2a"
	"google.golang.org/adk/cmd/launcher/web/api"
	"google.golang.org/adk/cmd/launcher/web/triggers/eventarc"
	"google.golang.org/adk/cmd/launcher/web/triggers/pubsub"
	"google.golang.org/adk/cmd/launcher/web/webui"
	llmapi "google.golang.org/adk/model"
)

// Config is the runtime launch configuration owned by this package.
type Config = launcher.Config

// NewConfig builds a runtime configuration for a single Agent Awesome agent.
// It converts the local agent definition into the runtime's LLM agent shape and
// installs any configured tools and toolsets on that agent.
func NewConfig(def agentpkg.Definition, llm llmapi.LLM, tools toolbundle.Bundle) (*Config, error) {
	runtimeAgent, err := llmagent.New(llmagent.Config{
		Name:        def.Name,
		Model:       llm,
		Description: def.Description,
		Instruction: def.Instruction,
		BeforeModelCallbacks: []llmagent.BeforeModelCallback{
			modelSelectionCallback(),
		},
		BeforeToolCallbacks: callbacks.TaskInvariantCallbacks(),
		Tools:               tools.Tools,
		Toolsets:            tools.Toolsets,
	})
	if err != nil {
		return nil, fmt.Errorf("create agent: %w", err)
	}

	return &Config{
		AgentLoader: aaagent.NewSingleLoader(runtimeAgent),
	}, nil
}

// Execute runs the configured agent with runtime-specific arguments.
// Help requests are treated as successful exits because the runtime has already
// printed the requested help text for the user.
func Execute(ctx context.Context, config *Config, args []string) error {
	runtime := delegatedLauncher()
	if err := runtime.Execute(ctx, config, args); err != nil {
		if errors.Is(err, flag.ErrHelp) {
			return nil
		}
		return fmt.Errorf("%w\n\n%s", err, runtime.CommandLineSyntax())
	}
	return nil
}

// Syntax returns the runtime command syntax used in Agent Awesome CLI help.
func Syntax() string {
	return delegatedLauncher().CommandLineSyntax()
}

// delegatedLauncher builds the ADK launcher stack supported by Agent Awesome.
func delegatedLauncher() launcher.Launcher {
	return universal.NewLauncher(web.NewLauncher(
		webui.NewLauncher(),
		a2a.NewLauncher(),
		pubsub.NewLauncher(),
		eventarc.NewLauncher(),
		api.NewLauncher(),
	))
}
