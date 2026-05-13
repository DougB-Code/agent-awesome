// This file installs a runtime plugin that captures sessions after each run.
package adkmemory

import (
	"context"
	"time"

	"github.com/rs/zerolog/log"
	"google.golang.org/adk/agent"
	"google.golang.org/adk/plugin"
)

const sessionCaptureTimeout = 10 * time.Second

// NewSessionCapturePlugin creates a best-effort post-run memory capture plugin.
func NewSessionCapturePlugin() (*plugin.Plugin, error) {
	return plugin.New(plugin.Config{
		Name:             "agentawesome-memory-capture",
		AfterRunCallback: captureSessionAfterRun,
	})
}

// captureSessionAfterRun asks the configured memory service to save new events.
func captureSessionAfterRun(invocation agent.InvocationContext) {
	if invocation == nil || invocation.Memory() == nil || invocation.Session() == nil {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), sessionCaptureTimeout)
	defer cancel()
	if err := invocation.Memory().AddSessionToMemory(ctx, invocation.Session()); err != nil {
		log.Error().Err(err).Msg("persist runtime session to memory")
	}
}
