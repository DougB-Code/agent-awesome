package cloudflare

// OperationStatus describes one provisioning operation lifecycle state.
type OperationStatus string

const (
	// OperationPlanned reports an operation that would run during a dry run.
	OperationPlanned OperationStatus = "planned"
	// OperationRunning reports an operation that is about to run.
	OperationRunning OperationStatus = "running"
	// OperationCompleted reports an operation that finished successfully.
	OperationCompleted OperationStatus = "completed"
	// OperationSkipped reports an operation that was already satisfied.
	OperationSkipped OperationStatus = "skipped"
	// OperationFailed reports an operation that failed.
	OperationFailed OperationStatus = "failed"
)

// OperationEvent stores display-safe progress for one provisioning operation.
type OperationEvent struct {
	Status  OperationStatus
	Command string
	Message string
}

// ProgressFunc receives display-safe provisioning progress events.
type ProgressFunc func(OperationEvent)

// emitProgress sends a progress event when a reporter is configured.
func emitProgress(progress ProgressFunc, event OperationEvent) {
	if progress == nil {
		return
	}
	progress(event)
}
