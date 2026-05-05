// This file translates runtime tool declarations into provider schemas.
package protocol

import (
	llmapi "google.golang.org/adk/model"
	"google.golang.org/genai"
)

// This file contains helpers for translating runtime tool declarations into
// provider-specific request schemas.

// @TODO I question if this package needs to exist, or if the providers themselves
// should / can provide this functionality.

// FunctionDeclarations collects all function declarations from a model request.
func FunctionDeclarations(req *llmapi.LLMRequest) []*genai.FunctionDeclaration {
	if req == nil || req.Config == nil {
		return nil
	}
	var declarations []*genai.FunctionDeclaration
	for _, tool := range req.Config.Tools {
		if tool == nil {
			continue
		}
		declarations = append(declarations, tool.FunctionDeclarations...)
	}
	return declarations
}

// DeclarationParameters returns the JSON-schema-like parameters object expected
// by OpenAI-compatible and Anthropic tool APIs.
func DeclarationParameters(decl *genai.FunctionDeclaration) any {
	if decl == nil {
		return nil
	}
	if decl.ParametersJsonSchema != nil {
		return decl.ParametersJsonSchema
	}
	if decl.Parameters != nil {
		return decl.Parameters
	}
	return map[string]any{"type": "object", "properties": map[string]any{}}
}
