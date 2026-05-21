// Package transport exposes workflow HTTP and MCP endpoints.
//
// Use this package at process boundaries. Business rules belong in the runtime
// package, while this package handles request decoding, response encoding, and
// route dispatch.
package transport
