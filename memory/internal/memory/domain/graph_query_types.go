package domain

// GraphQueryRequest asks the service to execute a graph query or mutation.
type GraphQueryRequest struct {
	Actor                string        `json:"actor"`
	Query                string        `json:"query"`
	SourceNodeID         string        `json:"source_node_id,omitempty"`
	DomainID             DomainID      `json:"domain_id,omitempty"`
	Firewall             Firewall      `json:"firewall,omitempty"`
	IncludeGlobal        bool          `json:"include_global,omitempty"`
	AllowedSensitivities []Sensitivity `json:"allowed_sensitivities"`
}

// GraphQueryResult stores rows returned by a graph query or mutation.
type GraphQueryResult struct {
	Columns []string         `json:"columns"`
	Rows    []GraphQueryRow  `json:"rows"`
	Paths   []GraphQueryPath `json:"paths,omitempty"`
	Limit   int              `json:"limit"`
	Query   string           `json:"query"`
}

// GraphQueryRow stores one row returned by a graph query.
type GraphQueryRow map[string]any

// GraphQueryPath stores one graph path associated with a result row.
type GraphQueryPath struct {
	RowIndex int      `json:"row_index"`
	Depth    int      `json:"depth"`
	NodeIDs  []string `json:"node_ids"`
	EdgeIDs  []string `json:"edge_ids"`
}
