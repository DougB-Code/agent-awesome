// This file renders runtime events for console output.
package console

import (
	"context"
	"fmt"
	"io"
	"strings"

	"google.golang.org/adk/agent"
	"google.golang.org/adk/tool/toolconfirmation"
	"google.golang.org/genai"
)

type consoleEventRenderer struct {
	out io.Writer
}

// Render streams one model turn to the console and returns any requested tool
// confirmation call.
func (r consoleEventRenderer) Render(ctx context.Context, runner consoleRunner, userID, sessionID string, msg *genai.Content, streamingMode agent.StreamingMode) (*genai.FunctionCall, error) {
	fmt.Fprint(r.out, "\nAgent -> ")
	var confirmation *genai.FunctionCall
	prevText := ""
	for event, err := range runner.Run(ctx, userID, sessionID, msg, agent.RunConfig{StreamingMode: streamingMode}) {
		if err != nil {
			return nil, err
		}
		if event == nil || event.LLMResponse.Content == nil {
			continue
		}
		if call := firstConfirmationCall(event.LLMResponse.Content); call != nil {
			confirmation = call
			continue
		}
		text := contentText(event.LLMResponse.Content)
		if text == "" {
			continue
		}
		// SSE streaming emits partial text and may also emit a final response
		// containing the full text. Track printed partials to avoid duplicating
		// the final answer when it matches what the user already saw.
		if streamingMode != agent.StreamingModeSSE {
			fmt.Fprint(r.out, text)
			continue
		}
		if !event.IsFinalResponse() {
			fmt.Fprint(r.out, text)
			prevText += text
			continue
		}
		if text != prevText {
			fmt.Fprint(r.out, text)
		}
		prevText = ""
	}
	return confirmation, nil
}

// firstConfirmationCall finds the runtime's special tool-confirmation function
// call in a model response, if one is present.
func firstConfirmationCall(content *genai.Content) *genai.FunctionCall {
	if content == nil {
		return nil
	}
	for _, part := range content.Parts {
		if part.FunctionCall != nil && part.FunctionCall.Name == toolconfirmation.FunctionCallName {
			return part.FunctionCall
		}
	}
	return nil
}

// contentText concatenates all text parts in a model response.
func contentText(content *genai.Content) string {
	var b strings.Builder
	for _, part := range content.Parts {
		b.WriteString(part.Text)
	}
	return b.String()
}
