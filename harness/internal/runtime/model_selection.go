// This file applies per-turn model selection to ADK model requests.
package runtime

import (
	"fmt"
	"strings"

	"google.golang.org/adk/agent"
	"google.golang.org/adk/agent/llmagent"
	llmapi "google.golang.org/adk/model"
)

// RuntimeModelRefStateKey stores the provider:model ref for the current turn.
const RuntimeModelRefStateKey = "agentawesome.model_ref"

// modelSelectionCallback copies session model selection into the LLM request.
func modelSelectionCallback() llmagent.BeforeModelCallback {
	return func(ctx agent.CallbackContext, request *llmapi.LLMRequest) (*llmapi.LLMResponse, error) {
		if ctx == nil || request == nil {
			return nil, nil
		}
		value, err := ctx.State().Get(RuntimeModelRefStateKey)
		if err != nil || value == nil {
			return nil, nil
		}
		ref := strings.TrimSpace(modelRefValue(value))
		if ref == "" {
			return nil, nil
		}
		request.Model = ref
		if err := ctx.State().Set(RuntimeModelRefStateKey, ref); err != nil {
			return nil, err
		}
		return nil, nil
	}
}

// modelRefValue converts session state values into a model ref string.
func modelRefValue(value any) string {
	if ref, ok := value.(string); ok {
		return ref
	}
	return fmt.Sprint(value)
}
