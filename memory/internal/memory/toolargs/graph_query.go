// This file classifies graph query tool requests before service execution.
package toolargs

import (
	"errors"

	"memory/internal/memory/domain"
	graphquery "memory/internal/memory/graph/query"
)

// EnsureReadOnlyGraphQuery rejects mutation grammar on read-only graph tools.
func EnsureReadOnlyGraphQuery(req domain.GraphQueryRequest) error {
	mutating, err := graphQueryMutates(req)
	if err != nil {
		return err
	}
	if mutating {
		return errors.New("query_context_graph only accepts read-only FIND or MATCH statements; use mutate_context_graph for graph mutations")
	}
	return nil
}

// EnsureMutatingGraphQuery rejects read grammar on graph mutation tools.
func EnsureMutatingGraphQuery(req domain.GraphQueryRequest) error {
	mutating, err := graphQueryMutates(req)
	if err != nil {
		return err
	}
	if !mutating {
		return errors.New("mutate_context_graph only accepts INSERT, SET, or DELETE statements; use query_context_graph for graph reads")
	}
	return nil
}

// graphQueryMutates parses a graph query request and reports whether it writes.
func graphQueryMutates(req domain.GraphQueryRequest) (bool, error) {
	req, err := domain.NormalizeGraphQueryRequest(req)
	if err != nil {
		return false, err
	}
	stmt, err := graphquery.Parse(req.Query)
	if err != nil {
		return false, err
	}
	return stmt.Mutating(), nil
}
