// Package queueworker leases and runs Launchpad queue items through HTTP.
//
// Intended use cases:
//   - Run from cron or another external scheduler against the gateway API.
//   - Recover expired Launchpad leases before looking for new work.
//   - Enqueue due Launchpad schedules and process one eligible queued run.
//
// High-level example:
//   - runbook-service queue-worker --gateway-base-url https://agent.example.com/api --target-id cloud-overnight
package queueworker
