// Package slack adapts Slack Events API traffic into Agent Awesome turns.
//
// Intended use cases:
//   - Receive Slack messages through either HTTP Events API or Socket Mode.
//   - Verify Slack HTTP signatures before accepting public cloud webhooks.
//   - Forward accepted Slack messages into the ADK REST harness and post replies.
//
// High-level examples:
//   - adapter.EventsHandler handles POST /slack/events in cloud deployments.
//   - adapter.RunSocketMode connects to Slack for local development pilots.
//
// This package should not own gateway process supervision or generic API proxying.
package slack
