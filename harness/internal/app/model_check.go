// This file coordinates model configuration validation and smoke checks.
package app

import (
	"context"
	"fmt"

	"agentawesome/internal/config"
	"agentawesome/internal/model"
)

// ModelCheckOptions contains CLI-selected model smoke-check values.
type ModelCheckOptions struct {
	ModelConfigPath string
	ProviderName    string
	ModelID         string
	Prompt          string
}

// ModelCheckResult summarizes a successful provider smoke check.
type ModelCheckResult struct {
	ProviderName string
	ModelID      string
	ModelName    string
	ResponseText string
}

// CheckModel validates config, creates the selected model, and sends one prompt.
func CheckModel(ctx context.Context, opts ModelCheckOptions) (ModelCheckResult, error) {
	modelCfg, err := config.LoadModel(opts.ModelConfigPath)
	if err != nil {
		return ModelCheckResult{}, err
	}
	factory := model.NewFactory()
	if err := factory.ValidateConfig(modelCfg); err != nil {
		return ModelCheckResult{}, err
	}
	selection, err := modelCfg.ResolveProvider(opts.ProviderName, opts.ModelID)
	if err != nil {
		return ModelCheckResult{}, err
	}
	llm, err := factory.Create(ctx, selection)
	if err != nil {
		return ModelCheckResult{}, fmt.Errorf("create model: %w", err)
	}
	responseText, err := model.SmokeCheck(ctx, llm, opts.Prompt)
	if err != nil {
		return ModelCheckResult{}, fmt.Errorf("smoke check provider %q model %q: %w", selection.Name, selection.Model.ID, err)
	}
	return ModelCheckResult{
		ProviderName: selection.Name,
		ModelID:      selection.Model.ID,
		ModelName:    selection.ModelName(),
		ResponseText: responseText,
	}, nil
}
