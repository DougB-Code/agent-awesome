// This file configures process-wide logging.
package logging

import (
	"time"

	platformlogging "agentawesome.dev/platform/logging"
)

// Configure initializes process-wide zerolog and standard-library log output.
func Configure(logFile string) error {
	_, err := platformlogging.Configure(platformlogging.Options{
		LogFile:           logFile,
		ComponentFallback: "harness",
		DefaultFormat:     platformlogging.FormatText,
		ConsoleTimeFormat: time.Kitchen,
	})
	if err != nil {
		return err
	}
	return nil
}
