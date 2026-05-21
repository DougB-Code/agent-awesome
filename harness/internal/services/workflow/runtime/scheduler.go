// This file starts simple daily cron schedules for loaded workflows.
package runtime

import (
	"context"
	"strconv"
	"strings"
	"time"
)

// StartScheduler starts the lightweight workflow scheduler loop.
func (s *Service) StartScheduler(ctx context.Context) {
	ticker := time.NewTicker(time.Minute)
	defer ticker.Stop()
	last := map[string]string{}
	for {
		select {
		case <-ctx.Done():
			return
		case now := <-ticker.C:
			s.fireDueSchedules(ctx, now, last)
		}
	}
}

// fireDueSchedules starts workflows whose simple daily cron is due.
func (s *Service) fireDueSchedules(ctx context.Context, now time.Time, last map[string]string) {
	s.mu.RLock()
	defs := make([]string, 0, len(s.defs))
	for id := range s.defs {
		defs = append(defs, id)
	}
	s.mu.RUnlock()
	for _, id := range defs {
		def, ok := s.DescribeDefinition(id)
		if !ok || !cronDue(def.Schedule, now) {
			continue
		}
		key := id + ":" + now.Format("2006-01-02T15:04")
		if last[id] == key {
			continue
		}
		last[id] = key
		_, _ = s.StartWorkflow(ctx, id, map[string]any{"scheduled_at": now.UTC().Format(time.RFC3339)})
	}
}

// cronDue supports the V1 daily shape "minute hour * * *".
func cronDue(schedule string, now time.Time) bool {
	fields := strings.Fields(schedule)
	if len(fields) != 5 || fields[2] != "*" || fields[3] != "*" || fields[4] != "*" {
		return false
	}
	minute, err := strconv.Atoi(fields[0])
	if err != nil {
		return false
	}
	hour, err := strconv.Atoi(fields[1])
	if err != nil {
		return false
	}
	return now.Minute() == minute && now.Hour() == hour
}
