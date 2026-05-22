// This file owns shared HTTP JSON request and response helpers.
package httpjson

import (
	"encoding/json"
	"errors"
	"net/http"
)

// ErrPayloadTooLarge identifies requests rejected by the configured body cap.
var ErrPayloadTooLarge = errors.New("payload too large")

// DecodeBounded decodes one JSON request body with a maximum byte count.
func DecodeBounded(w http.ResponseWriter, r *http.Request, limit int64, target any) error {
	body := http.MaxBytesReader(w, r.Body, limit)
	defer body.Close()
	if err := json.NewDecoder(body).Decode(target); err != nil {
		var maxBytesErr *http.MaxBytesError
		if errors.As(err, &maxBytesErr) {
			return ErrPayloadTooLarge
		}
		return err
	}
	return nil
}

// Write writes a JSON response without HTML escaping.
func Write(w http.ResponseWriter, status int, body any) {
	write(w, status, body, false)
}

// WriteEscaped writes a JSON response with encoding/json's default escaping.
func WriteEscaped(w http.ResponseWriter, status int, body any) {
	write(w, status, body, true)
}

// write encodes one JSON response body.
func write(w http.ResponseWriter, status int, body any, escapeHTML bool) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	encoder := json.NewEncoder(w)
	encoder.SetEscapeHTML(escapeHTML)
	_ = encoder.Encode(body)
}
