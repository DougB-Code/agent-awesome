// This file creates default HTTP clients for model providers.
package model

import (
	"net/http"
	"time"
)

const defaultHTTPTimeout = 60 * time.Second

// defaultHTTPClient returns a provider HTTP client with the standard timeout.
func defaultHTTPClient() *http.Client {
	return &http.Client{Timeout: defaultHTTPTimeout}
}
