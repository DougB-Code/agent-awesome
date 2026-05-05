package domain

import "fmt"

// NormalizeTaskGraphProjectionQuery validates graph projection filters.
func NormalizeTaskGraphProjectionQuery(q TaskGraphProjectionQuery) (TaskGraphProjectionQuery, error) {
	tasks, err := NormalizeTaskQuery(q.Tasks)
	if err != nil {
		return q, err
	}
	q.Tasks = tasks
	for _, relation := range q.RelationTypes {
		if !ValidTaskRelationType(relation) {
			return q, fmt.Errorf("invalid task relation type %q", relation)
		}
	}
	return q, nil
}
