// Package store persists runbook definitions, runs, events, outputs, and inbox items.
//
// Use this package from runbook runtime code that needs durable execution
// state. The store intentionally uses simple JSON columns so declarative
// runbook payloads remain forward-compatible.
package store
