// Package ports declares service dependencies that keep the memory domain
// independent from storage engines, transports, and model runtimes.
//
// Implement these interfaces in infrastructure packages. Agent harnesses should
// call the memory service transport, not these storage ports directly.
package ports
