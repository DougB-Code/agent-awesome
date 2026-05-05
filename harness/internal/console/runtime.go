// This file adapts ADK runtime execution to the built-in console.
package console

import (
	"context"
	"fmt"
	"iter"
	"os"

	"google.golang.org/adk/agent"
	"google.golang.org/adk/cmd/launcher"
	"google.golang.org/adk/runner"
	"google.golang.org/adk/session"
	"google.golang.org/genai"
)

type consoleRunner interface {
	Run(context.Context, string, string, *genai.Content, agent.RunConfig) iter.Seq2[*session.Event, error]
}

type adkConsoleRunner struct {
	runner *runner.Runner
}

type consoleRuntime struct {
	runner    consoleRunner
	userID    string
	sessionID string
}

// Run delegates one console turn to the underlying ADK runner.
func (r adkConsoleRunner) Run(ctx context.Context, userID, sessionID string, msg *genai.Content, cfg agent.RunConfig) iter.Seq2[*session.Event, error] {
	return r.runner.Run(ctx, userID, sessionID, msg, cfg)
}

// Run starts Agent Awesome's built-in terminal runtime mode.
func Run(ctx context.Context, cfg *launcher.Config, args []string) error {
	opts, err := parseConsoleOptions(args)
	if err != nil {
		return err
	}

	runtime, err := newConsoleRuntime(ctx, cfg)
	if err != nil {
		return err
	}
	return NewConsole(os.Stdin, os.Stdout).Run(ctx, runtime.runner, runtime.userID, runtime.sessionID, opts.streamingMode)
}

// newConsoleRuntime creates the ADK runner and session used by console mode.
func newConsoleRuntime(ctx context.Context, cfg *launcher.Config) (consoleRuntime, error) {
	// The console is a local single-user experience, so fixed IDs are enough to
	// keep the session stable for the lifetime of the command.
	userID, appName := "console_user", "console_app"
	sessionService := cfg.SessionService
	if sessionService == nil {
		sessionService = session.InMemoryService()
	}
	createResp, err := sessionService.Create(ctx, &session.CreateRequest{
		AppName: appName,
		UserID:  userID,
	})
	if err != nil {
		return consoleRuntime{}, fmt.Errorf("create console session: %w", err)
	}

	r, err := runner.New(runner.Config{
		AppName:         appName,
		Agent:           cfg.AgentLoader.RootAgent(),
		SessionService:  sessionService,
		ArtifactService: cfg.ArtifactService,
		MemoryService:   cfg.MemoryService,
		PluginConfig:    cfg.PluginConfig,
	})
	if err != nil {
		return consoleRuntime{}, fmt.Errorf("create console runner: %w", err)
	}
	return consoleRuntime{
		runner:    adkConsoleRunner{runner: r},
		userID:    userID,
		sessionID: createResp.Session.ID(),
	}, nil
}
