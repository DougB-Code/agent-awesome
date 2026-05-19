// This file defines workflow runtime configuration.
package runtime

import "time"

// Config stores service endpoints and durable paths for workflow execution.
type Config struct {
	DefinitionsDir        string
	DatabasePath          string
	HarnessContextBaseURL string
	RequestTimeout        time.Duration
}
