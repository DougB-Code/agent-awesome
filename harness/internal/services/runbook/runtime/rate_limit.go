// This file enforces bounded in-process runbook invocation rates.
package runtime

import (
	"fmt"
	"strings"
	"time"

	"agentawesome/internal/services/runbook/contracts"
)

const (
	// rateLimitWindow is the evaluation window for per-minute runtime limits.
	rateLimitWindow = time.Minute
	// rateLimitFallbackKey groups unnamed invocations under a deterministic bucket.
	rateLimitFallbackKey = "runbook-node"
)

// checkInvocationRateLimit records an invocation or returns a deterministic rate error.
func (s *Service) checkInvocationRateLimit(key string, runtime contracts.Runtime) error {
	if runtime.RateLimitPerMinute <= 0 {
		return nil
	}
	normalized := strings.TrimSpace(key)
	if normalized == "" {
		normalized = rateLimitFallbackKey
	}
	now := time.Now().UTC()
	cutoff := now.Add(-rateLimitWindow)
	s.rateMu.Lock()
	defer s.rateMu.Unlock()
	recent := s.rateHits[normalized][:0]
	for _, hit := range s.rateHits[normalized] {
		if hit.After(cutoff) {
			recent = append(recent, hit)
		}
	}
	if len(recent) >= runtime.RateLimitPerMinute {
		s.rateHits[normalized] = recent
		return fmt.Errorf("runtime rate limit for %q exceeded %d invocations per minute", normalized, runtime.RateLimitPerMinute)
	}
	recent = append(recent, now)
	s.rateHits[normalized] = recent
	return nil
}
