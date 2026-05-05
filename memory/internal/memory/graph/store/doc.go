// Package store implements durable SQLite storage for the context graph.
//
// Use this package for graph-native persistence under the memory service. It
// should not import task or memory projections; those packages should depend on
// this store through explicit service boundaries.
package store
