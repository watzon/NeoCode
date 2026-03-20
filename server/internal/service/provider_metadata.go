package service

import (
	"strings"

	"github.com/watzon/neocode/server/internal/core"
)

func enrichProviderResponse(response core.ProviderResponse) core.ProviderResponse {
	providers := make([]core.Provider, 0, len(response.Providers))
	for _, provider := range response.Providers {
		models := make(map[string]core.ProviderModel, len(provider.Models))
		for key, model := range provider.Models {
			if model.Limits == nil {
				if limits, ok := inferredModelLimits(provider.ID, model.ID); ok {
					model.Limits = &limits
				}
			}
			models[key] = model
		}
		provider.Models = models
		providers = append(providers, provider)
	}
	response.Providers = providers
	return response
}

func inferredModelLimits(providerID, modelID string) (core.ProviderModelLimits, bool) {
	normalizedProvider := strings.ToLower(strings.TrimSpace(providerID))
	normalizedModel := strings.ToLower(strings.TrimSpace(modelID))
	joined := normalizedProvider + "/" + normalizedModel

	switch {
	case normalizedProvider == "openai":
		return core.ProviderModelLimits{Context: 1_000_000, Output: 128_000}, true
	case normalizedProvider == "anthropic":
		return core.ProviderModelLimits{Context: 200_000, Output: 64_000}, true
	case normalizedProvider == "google":
		return core.ProviderModelLimits{Context: 1_000_000, Output: 65_536}, true
	case normalizedProvider == "openrouter":
		switch {
		case strings.Contains(joined, "anthropic/"):
			return core.ProviderModelLimits{Context: 200_000, Output: 64_000}, true
		case strings.Contains(joined, "openai/") || strings.Contains(normalizedModel, "gpt-5") || strings.Contains(normalizedModel, "codex"):
			return core.ProviderModelLimits{Context: 1_000_000, Output: 128_000}, true
		case strings.Contains(joined, "google/") || strings.Contains(normalizedModel, "gemini"):
			return core.ProviderModelLimits{Context: 1_000_000, Output: 65_536}, true
		}
	}

	return core.ProviderModelLimits{}, false
}
