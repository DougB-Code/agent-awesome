// Package store persists workflow definitions, runs, events, outputs, and inbox items.
//
// Use this package from workflowd runtime code that needs durable execution
// state. The store intentionally uses simple JSON columns so declarative
// workflow payloads remain forward-compatible.
package store
