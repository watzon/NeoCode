package service

import (
	"testing"

	"github.com/watzon/neocode/server/internal/core"
)

func TestEnrichProviderResponseAddsKnownModelLimits(t *testing.T) {
	response := enrichProviderResponse(core.ProviderResponse{
		Providers: []core.Provider{{
			ID:   "openai",
			Name: "OpenAI",
			Models: map[string]core.ProviderModel{
				"gpt-5.4": {ID: "gpt-5.4", ProviderID: "openai", Name: "GPT-5.4"},
			},
		}},
	})

	limits := response.Providers[0].Models["gpt-5.4"].Limits
	if limits == nil {
		t.Fatal("expected inferred limits")
	}
	if limits.Context != 1_000_000 {
		t.Fatalf("unexpected context limit: %d", limits.Context)
	}
}
