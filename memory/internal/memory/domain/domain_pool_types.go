package domain

// MemoryDomainInfo describes one SQLite database managed by the memory pool.
type MemoryDomainInfo struct {
	// DomainID is the routable memory domain id.
	DomainID DomainID `json:"domain_id"`

	// Path is the SQLite database path for diagnostics.
	Path string `json:"path,omitempty"`

	// Open reports whether this database currently has an open pool handle.
	Open bool `json:"open"`

	// Exists reports whether the database file is present on disk.
	Exists bool `json:"exists"`
}

// MemoryDomainListRequest carries actor metadata for listing pool databases.
type MemoryDomainListRequest struct {
	// Actor identifies the caller for service policy checks and audit.
	Actor string `json:"actor,omitempty"`

	// DomainID optionally restricts the list to one authorized database.
	DomainID DomainID `json:"domain_id,omitempty"`
}

// MemoryDomainRequest selects one memory pool database.
type MemoryDomainRequest struct {
	// Actor identifies the caller for service policy checks and audit.
	Actor string `json:"actor,omitempty"`

	// DomainID selects the database to add, detach, or delete.
	DomainID DomainID `json:"domain_id,omitempty"`

	// DeleteFiles removes the domain directory from disk when true.
	DeleteFiles bool `json:"delete_files,omitempty"`
}
