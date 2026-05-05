// This file implements the built-in interactive console loop.
package console

import (
	"bufio"
	"context"
	"fmt"
	"io"
	"strings"

	"google.golang.org/adk/agent"
	"google.golang.org/genai"
)

// This file contains the REPL shell for Agent Awesome's built-in console mode.
// Runtime setup lives in console_runtime.go, and option parsing lives in
// console_options.go.

// Console owns interactive terminal input and output for console mode.
type Console struct {
	reader *bufio.Reader
	out    io.Writer
}

// NewConsole creates a console bound to the provided input and output streams.
func NewConsole(stdin io.Reader, stdout io.Writer) *Console {
	return &Console{
		reader: bufio.NewReader(stdin),
		out:    stdout,
	}
}

// Run starts the terminal chat loop for the configured console runner.
func (c *Console) Run(ctx context.Context, r consoleRunner, userID, sessionID string, streamingMode agent.StreamingMode) error {
	fmt.Fprintln(c.out)
	for {
		fmt.Fprint(c.out, "\nUser -> ")
		line, err := c.reader.ReadString('\n')
		if err != nil {
			if err == io.EOF {
				fmt.Fprintln(c.out, "\nEOF detected, exiting...")
				return nil
			}
			return fmt.Errorf("read user input: %w", err)
		}
		if strings.TrimSpace(line) == "" {
			continue
		}
		if err := c.RunTurn(ctx, r, userID, sessionID, genai.NewContentFromText(line, genai.RoleUser), streamingMode); err != nil {
			fmt.Fprintf(c.out, "\nAGENT_ERROR: %v\n", err)
		}
	}
}

// RunTurn sends one user message through the runner and coordinates any
// confirmation loop requested by the runtime.
func (c *Console) RunTurn(ctx context.Context, r consoleRunner, userID, sessionID string, msg *genai.Content, streamingMode agent.StreamingMode) error {
	renderer := consoleEventRenderer{out: c.out}
	for {
		confirmation, err := renderer.Render(ctx, r, userID, sessionID, msg, streamingMode)
		if err != nil {
			return err
		}
		if confirmation == nil {
			return nil
		}
		response, err := c.PromptForConfirmation(confirmation)
		if err != nil {
			return err
		}
		msg = response
	}
}
