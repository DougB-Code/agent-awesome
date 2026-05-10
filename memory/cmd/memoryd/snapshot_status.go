// This file tracks memory snapshot operation state for health responses.
package main

import (
	"sync"
	"time"
)

// snapshotRuntimeStatus stores in-process snapshot restore and save telemetry.
type snapshotRuntimeStatus struct {
	mu      sync.Mutex
	enabled bool
	restore snapshotOperationStatus
	save    snapshotOperationStatus
}

// snapshotOperationStatus stores one snapshot operation state.
type snapshotOperationStatus struct {
	State       string `json:"state"`
	CompletedAt string `json:"completed_at,omitempty"`
	Error       string `json:"error,omitempty"`
}

// snapshotRuntimeStatusView is the JSON-safe health response payload.
type snapshotRuntimeStatusView struct {
	Enabled bool                    `json:"enabled"`
	Restore snapshotOperationStatus `json:"restore"`
	Save    snapshotOperationStatus `json:"save"`
}

// newSnapshotRuntimeStatus initializes snapshot telemetry for this daemon.
func newSnapshotRuntimeStatus(enabled bool) *snapshotRuntimeStatus {
	state := "disabled"
	if enabled {
		state = "pending"
	}
	return &snapshotRuntimeStatus{
		enabled: enabled,
		restore: snapshotOperationStatus{State: state},
		save:    snapshotOperationStatus{State: state},
	}
}

// restoreComplete records a successful startup snapshot restore.
func (s *snapshotRuntimeStatus) restoreComplete() {
	s.setRestore(snapshotOperationStatus{State: "complete", CompletedAt: time.Now().UTC().Format(time.RFC3339)})
}

// restoreFailed records a failed startup snapshot restore.
func (s *snapshotRuntimeStatus) restoreFailed(err error) {
	s.setRestore(snapshotOperationStatus{State: "failed", Error: err.Error()})
}

// saveBegin records that graceful shutdown snapshot upload has started.
func (s *snapshotRuntimeStatus) saveBegin() {
	s.setSave(snapshotOperationStatus{State: "saving"})
}

// saveComplete records a successful graceful shutdown snapshot upload.
func (s *snapshotRuntimeStatus) saveComplete() {
	s.setSave(snapshotOperationStatus{State: "complete", CompletedAt: time.Now().UTC().Format(time.RFC3339)})
}

// saveFailed records a failed graceful shutdown snapshot upload.
func (s *snapshotRuntimeStatus) saveFailed(err error) {
	s.setSave(snapshotOperationStatus{State: "failed", Error: err.Error()})
}

// view returns a copy safe to serialize without holding the mutex.
func (s *snapshotRuntimeStatus) view() snapshotRuntimeStatusView {
	s.mu.Lock()
	defer s.mu.Unlock()
	return snapshotRuntimeStatusView{Enabled: s.enabled, Restore: s.restore, Save: s.save}
}

// setRestore stores a restore operation snapshot.
func (s *snapshotRuntimeStatus) setRestore(status snapshotOperationStatus) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.restore = status
}

// setSave stores a save operation snapshot.
func (s *snapshotRuntimeStatus) setSave(status snapshotOperationStatus) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.save = status
}
