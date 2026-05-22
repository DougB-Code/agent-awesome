// This file connects gateway startup to shared logging setup.
package logging

import (
	"time"

	platformlogging "agentawesome.dev/platform/logging"
)

// Configure initializes zerolog and bridges standard-library logs into it.
func Configure(logFile string) (func(), error) {
	return platformlogging.Configure(platformlogging.Options{
		LogFile:           logFile,
		ComponentFallback: "gateway",
		DefaultFormat:     platformlogging.FormatJSON,
		ConsoleTimeFormat: time.RFC3339,
	})
}
