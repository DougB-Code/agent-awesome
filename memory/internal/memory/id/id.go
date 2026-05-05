package id

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"time"
)

// New returns an identifier with a readable prefix and random suffix.
func New(prefix string) (string, error) {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		return "", fmt.Errorf("generate id: %w", err)
	}
	return fmt.Sprintf("%s_%x_%s", prefix, time.Now().UTC().UnixMilli(), hex.EncodeToString(b[:])), nil
}
