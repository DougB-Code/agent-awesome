// This file parses console runtime options and syntax.
package console

import (
	"flag"
	"fmt"
	"strings"

	"agent-awesome.com/harnessinternal/config/schema"
	"google.golang.org/adk/agent"
)

type consoleOptions struct {
	streamingMode agent.StreamingMode
}

// ShouldRun reports whether the run command should use Agent Awesome's
// built-in console instead of delegating to another runtime mode.
func ShouldRun(args []string) bool {
	return len(args) == 0 || args[0] == "console"
}

// parseConsoleOptions parses console runtime flags after the optional console
// subcommand token.
func parseConsoleOptions(args []string) (consoleOptions, error) {
	if len(args) > 0 && args[0] == "console" {
		args = args[1:]
	}

	opts := consoleOptions{}
	flags := newConsoleFlagSet(&opts)
	if err := flags.Parse(args); err != nil {
		return consoleOptions{}, fmt.Errorf("cannot parse console args: %w", err)
	}
	if flags.NArg() > 0 {
		return consoleOptions{}, fmt.Errorf("cannot parse following console arguments: %v", flags.Args())
	}

	if opts.streamingMode == "" {
		opts.streamingMode = agent.StreamingModeNone
	}
	if opts.streamingMode != agent.StreamingModeNone && opts.streamingMode != agent.StreamingModeSSE {
		return consoleOptions{}, fmt.Errorf("invalid streaming_mode: %s", opts.streamingMode)
	}
	return opts, nil
}

// Syntax returns the Agent Awesome console syntax. Console mode is handled by
// the harness so it can support local confirmation prompts while still running
// the agent through ADK.
func Syntax() string {
	opts := consoleOptions{}
	var b strings.Builder
	fmt.Fprintf(&b, "  console - runs an agent in Agent Awesome console mode.\n")
	fmt.Fprintf(&b, "  console flags:\n")
	flags := newConsoleFlagSet(&opts)
	flags.SetOutput(&b)
	flags.PrintDefaults()
	return b.String()
}

// newConsoleFlagSet builds the flag set used by console mode and help text.
func newConsoleFlagSet(opts *consoleOptions) *flag.FlagSet {
	flags := flag.NewFlagSet("console", flag.ContinueOnError)
	flags.Var((*streamingModeValue)(&opts.streamingMode), "streaming_mode", fmt.Sprintf("defines streaming mode (%s|%s)", agent.StreamingModeNone, agent.StreamingModeSSE))
	return flags
}

type streamingModeValue agent.StreamingMode

// Set stores a streaming mode flag value.
func (v *streamingModeValue) Set(value string) error {
	*v = streamingModeValue(value)
	return nil
}

// String renders the streaming mode flag value.
func (v *streamingModeValue) String() string {
	if v == nil {
		return ""
	}
	return string(*v)
}

// RequestedModelCapabilities returns the model capabilities requested by console
// options. Other runtime entrypoints do not request console-specific
// capabilities.
func RequestedModelCapabilities(args []string) (schema.ModelCapabilities, error) {
	if ShouldRun(args) {
		opts, err := parseConsoleOptions(args)
		if err != nil {
			return schema.ModelCapabilities{}, err
		}
		return schema.ModelCapabilities{
			Streaming: opts.streamingMode == agent.StreamingModeSSE,
		}, nil
	}
	return schema.ModelCapabilities{}, nil
}
