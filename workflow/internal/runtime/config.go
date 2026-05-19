// This file defines workflow runtime configuration.
package runtime

import "time"

// Config stores service endpoints and durable paths for workflow execution.
type Config struct {
	DefinitionsDir        string
	DatabasePath          string
	HarnessBaseURL        string
	HarnessContextBaseURL string
	AppName               string
	UserID                string
	RequestTimeout        time.Duration
}
