// This file owns shared HTTP JSON request and response helpers.
package httpjson

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
)

// ErrPayloadTooLarge identifies requests rejected by the configured body cap.
var ErrPayloadTooLarge = errors.New("payload too large")

// DecodeBounded decodes one JSON request body with a maximum byte count.
func DecodeBounded(w http.ResponseWriter, r *http.Request, limit int64, target any) error {
	body := http.MaxBytesReader(w, r.Body, limit)
	defer body.Close()
	decoder := json.NewDecoder(body)
	if err := decodeJSONValue(decoder, target); err != nil {
		return err
	}
	var extra any
	if err := decodeJSONValue(decoder, &extra); !errors.Is(err, io.EOF) {
		if err != nil {
			return err
		}
		return errors.New("request body must contain only one JSON value")
	}
	return nil
}

// decodeJSONValue decodes one JSON value and normalizes bounded-body errors.
func decodeJSONValue(decoder *json.Decoder, target any) error {
	if err := decoder.Decode(target); err != nil {
		var maxBytesErr *http.MaxBytesError
		if errors.As(err, &maxBytesErr) {
			return ErrPayloadTooLarge
		}
		return err
	}
	return nil
}

// ReadBounded reads one request body with a maximum byte count.
func ReadBounded(w http.ResponseWriter, r *http.Request, limit int64) ([]byte, error) {
	body := http.MaxBytesReader(w, r.Body, limit)
	defer body.Close()
	data, err := io.ReadAll(body)
	if err != nil {
		var maxBytesErr *http.MaxBytesError
		if errors.As(err, &maxBytesErr) {
			return nil, ErrPayloadTooLarge
		}
		return nil, err
	}
	return data, nil
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
