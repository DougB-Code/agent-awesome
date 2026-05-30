// This file schedules and invokes workflow state-machine runs.
package runtime

import (
	"context"
	"errors"
	"fmt"

	"agentawesome/internal/services/workflow/actions"
	"agentawesome/internal/services/workflow/definition"
)

// executeRun resumes a run according to its hierarchical state-machine definition.
func (s *Service) executeRun(ctx context.Context, runID string) {
	unlock := s.lockRun(runID)
	defer unlock()
	run, err := s.store.GetRun(ctx, runID)
	if err != nil || run.Status == statusCanceled || run.Status == statusSucceeded {
		return
	}
	def, ok := s.DescribeDefinition(run.DefinitionID)
	if !ok {
		s.failRun(ctx, run, fmt.Errorf("workflow definition %q not loaded", run.DefinitionID))
		return
	}
	if !definition.HasStateMachine(def) {
		s.failRun(ctx, run, fmt.Errorf("workflow definition %q is not a state machine", def.ID))
		return
	}
	err = s.executeStateMachine(ctx, def, run)
	if err == nil {
		return
	}
	if errors.Is(err, actions.ErrPending) {
		run, _ = s.store.GetRun(ctx, run.ID)
		_ = s.store.UpdateRunState(ctx, run.ID, statusWaiting, run.State, run.Output)
		return
	}
	s.failRun(ctx, run, err)
}
