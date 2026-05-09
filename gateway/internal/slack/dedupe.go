// This file deduplicates Slack event deliveries for a short retry window.
package slack

import (
	"sync"
	"time"
)

const defaultEventDedupTTL = 10 * time.Minute

// eventDeduper remembers recently accepted Slack event keys.
type eventDeduper struct {
	mu   sync.Mutex
	ttl  time.Duration
	now  func() time.Time
	seen map[string]time.Time
}

// newEventDeduper creates a TTL-based Slack event deduper.
func newEventDeduper(ttl time.Duration) *eventDeduper {
	if ttl <= 0 {
		ttl = defaultEventDedupTTL
	}
	return &eventDeduper{
		ttl:  ttl,
		now:  func() time.Time { return time.Now().UTC() },
		seen: make(map[string]time.Time),
	}
}

// accept records a key and reports whether it has not been seen recently.
func (d *eventDeduper) accept(key string) bool {
	if d == nil || key == "" {
		return true
	}
	now := d.now()
	d.mu.Lock()
	defer d.mu.Unlock()
	d.prune(now)
	if expiresAt, ok := d.seen[key]; ok && expiresAt.After(now) {
		return false
	}
	d.seen[key] = now.Add(d.ttl)
	return true
}

// prune removes expired keys from the dedupe table.
func (d *eventDeduper) prune(now time.Time) {
	for key, expiresAt := range d.seen {
		if !expiresAt.After(now) {
			delete(d.seen, key)
		}
	}
}
