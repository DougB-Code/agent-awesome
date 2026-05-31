// This file creates opaque runbook runtime identifiers.
package runtime

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
)

// newRunID creates an opaque durable run id.
func newRunID() (string, error) {
	return randomID("run")
}

// newPendingID creates an opaque pending item id.
func newPendingID() (string, error) {
	return randomID("pending")
}

// randomID creates a prefixed random hex id.
func randomID(prefix string) (string, error) {
	var bytes [8]byte
	if _, err := rand.Read(bytes[:]); err != nil {
		return "", fmt.Errorf("create %s id: %w", prefix, err)
	}
	return prefix + "_" + hex.EncodeToString(bytes[:]), nil
}
