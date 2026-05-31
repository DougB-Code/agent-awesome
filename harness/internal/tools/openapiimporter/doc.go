// Package openapiimporter converts OpenAPI contracts into AA tool packages.
//
// Use this package when a REST API schema should become deterministic command
// operations backed by the generic command boundary. The importer intentionally
// emits curl operations instead of a first-class REST runtime so workflows keep
// using the same command execution path as other local CLI tools.
package openapiimporter
