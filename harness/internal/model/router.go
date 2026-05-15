// This file routes runtime LLM requests across configured provider/model pairs.
package model

import (
	"context"
	"fmt"
	"iter"
	"strings"
	"sync"

	"agentawesome/internal/config/schema"
	"github.com/rs/zerolog/log"
	llmapi "google.golang.org/adk/model"
)

// RoutingLLM dispatches each ADK model request to the selected configured LLM.
type RoutingLLM struct {
	config           *schema.ModelConfig
	factory          *Factory
	defaultSelection schema.ProviderSelection

	mu      sync.Mutex
	clients map[string]llmapi.LLM
}

var _ llmapi.LLM = (*RoutingLLM)(nil)

const (
	routeMetadataModelRefKey  = "agentawesome.model_ref"
	routeMetadataProviderKey  = "agentawesome.provider"
	routeMetadataModelIDKey   = "agentawesome.model_id"
	routeMetadataModelNameKey = "agentawesome.model_name"
	routeMetadataRequestedKey = "agentawesome.requested_model_ref"
	routeMetadataAdapterKey   = "agentawesome.adapter"
)

// CreateRouter builds an LLM that can switch among models in one config.
func (f *Factory) CreateRouter(ctx context.Context, cfg *schema.ModelConfig, defaultSelection schema.ProviderSelection) (llmapi.LLM, error) {
	if f == nil {
		return nil, fmt.Errorf("model factory is nil")
	}
	if cfg == nil {
		return nil, fmt.Errorf("model config is nil")
	}
	router := &RoutingLLM{
		config:           cfg,
		factory:          f,
		defaultSelection: defaultSelection,
		clients:          make(map[string]llmapi.LLM),
	}
	if _, err := router.client(ctx, defaultSelection); err != nil {
		return nil, err
	}
	return router, nil
}

// ModelRef returns the stable provider:model reference for a selection.
func ModelRef(selection schema.ProviderSelection) string {
	return strings.TrimSpace(selection.Name) + ":" + strings.TrimSpace(selection.Model.ID)
}

// Name returns the default model ref exposed to ADK request construction.
func (r *RoutingLLM) Name() string {
	return ModelRef(r.defaultSelection)
}

// GenerateContent delegates the request to the configured model selected by
// req.Model, falling back to the startup default when no override is present.
func (r *RoutingLLM) GenerateContent(ctx context.Context, req *llmapi.LLMRequest, stream bool) iter.Seq2[*llmapi.LLMResponse, error] {
	return func(yield func(*llmapi.LLMResponse, error) bool) {
		selection, err := r.selectionForRequest(req)
		if err != nil {
			yield(nil, err)
			return
		}
		if stream && !selection.Model.Capabilities.Streaming {
			yield(nil, fmt.Errorf("provider %q model %q does not declare streaming support", selection.Name, selection.Model.ID))
			return
		}
		r.logSelection(req, selection)
		llm, err := r.client(ctx, selection)
		if err != nil {
			yield(nil, err)
			return
		}
		if req == nil {
			req = &llmapi.LLMRequest{}
		}
		reqCopy := *req
		reqCopy.Model = ""
		for response, responseErr := range llm.GenerateContent(ctx, &reqCopy, stream) {
			annotateRoutedResponse(response, req, selection)
			if !yield(response, responseErr) {
				return
			}
		}
	}
}

// logSelection records the concrete provider route used for a model request.
func (r *RoutingLLM) logSelection(req *llmapi.LLMRequest, selection schema.ProviderSelection) {
	log.Info().
		Str("requested_model_ref", requestedModelRef(req)).
		Str("selected_model_ref", ModelRef(selection)).
		Str("provider", selection.Name).
		Str("adapter", selection.Adapter()).
		Str("model_id", selection.Model.ID).
		Str("model", selection.ModelName()).
		Msg("routing model request")
}

// requestedModelRef returns the unmodified model selector from an ADK request.
func requestedModelRef(req *llmapi.LLMRequest) string {
	if req == nil {
		return ""
	}
	return strings.TrimSpace(req.Model)
}

// annotateRoutedResponse stamps responses with the selected route for clients
// and diagnostics that need to distinguish local and hosted model turns.
func annotateRoutedResponse(response *llmapi.LLMResponse, req *llmapi.LLMRequest, selection schema.ProviderSelection) {
	if response == nil {
		return
	}
	response.ModelVersion = ModelRef(selection)
	if response.CustomMetadata == nil {
		response.CustomMetadata = make(map[string]any)
	}
	response.CustomMetadata[routeMetadataRequestedKey] = requestedModelRef(req)
	response.CustomMetadata[routeMetadataModelRefKey] = ModelRef(selection)
	response.CustomMetadata[routeMetadataProviderKey] = strings.TrimSpace(selection.Name)
	response.CustomMetadata[routeMetadataAdapterKey] = strings.TrimSpace(selection.Adapter())
	response.CustomMetadata[routeMetadataModelIDKey] = strings.TrimSpace(selection.Model.ID)
	response.CustomMetadata[routeMetadataModelNameKey] = strings.TrimSpace(selection.ModelName())
}

// selectionForRequest resolves the configured provider/model requested by ADK.
func (r *RoutingLLM) selectionForRequest(req *llmapi.LLMRequest) (schema.ProviderSelection, error) {
	ref := ""
	if req != nil {
		ref = strings.TrimSpace(req.Model)
	}
	if ref == "" || ref == r.Name() || ref == r.defaultSelection.ModelName() {
		return r.defaultSelection, nil
	}
	providerName, modelID, ok := parseModelRef(ref)
	if !ok {
		return schema.ProviderSelection{}, fmt.Errorf("model ref %q must be provider:model", ref)
	}
	selection, err := r.config.ResolveProvider(providerName, modelID)
	if err != nil {
		return schema.ProviderSelection{}, err
	}
	return selection, nil
}

// client returns a cached provider client for the configured selection.
func (r *RoutingLLM) client(ctx context.Context, selection schema.ProviderSelection) (llmapi.LLM, error) {
	if !selectionCacheable(selection) {
		return r.factory.Create(ctx, selection)
	}
	ref := ModelRef(selection)
	r.mu.Lock()
	defer r.mu.Unlock()
	if llm, ok := r.clients[ref]; ok {
		return llm, nil
	}
	llm, err := r.factory.Create(ctx, selection)
	if err != nil {
		return nil, err
	}
	r.clients[ref] = llm
	return llm, nil
}

// selectionCacheable reports whether a provider client can safely stay in memory.
func selectionCacheable(selection schema.ProviderSelection) bool {
	return strings.TrimSpace(selection.Provider.APIKeyEnv) == ""
}

// parseModelRef splits provider:model refs while preserving colons in model ids.
func parseModelRef(ref string) (providerName string, modelID string, ok bool) {
	parts := strings.SplitN(strings.TrimSpace(ref), ":", 2)
	if len(parts) != 2 {
		return "", "", false
	}
	providerName = strings.TrimSpace(parts[0])
	modelID = strings.TrimSpace(parts[1])
	if providerName == "" || modelID == "" {
		return "", "", false
	}
	return providerName, modelID, true
}
