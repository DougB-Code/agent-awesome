// This file tests Slack Web API request construction and response handling.
package slack

import (
	"encoding/json"
	"net/http"
	"strings"
	"testing"
)

// roundTripFunc adapts a function into an HTTP transport for Web API tests.
type roundTripFunc func(*http.Request) (*http.Response, error)

// RoundTrip executes the wrapped transport function.
func (f roundTripFunc) RoundTrip(req *http.Request) (*http.Response, error) {
	return f(req)
}

// TestWebAPIOpenSocketURLUsesAppToken verifies Socket Mode uses app auth.
func TestWebAPIOpenSocketURLUsesAppToken(t *testing.T) {
	api := NewWebAPI(&http.Client{Transport: roundTripFunc(func(req *http.Request) (*http.Response, error) {
		if req.URL.Path != "/api/apps.connections.open" {
			t.Fatalf("path = %q, want apps.connections.open", req.URL.Path)
		}
		if got := req.Header.Get("Authorization"); got != "Bearer xapp-test" {
			t.Fatalf("Authorization = %q, want app token", got)
		}
		return testHTTPResponse(http.StatusOK, `{"ok":true,"url":"wss://socket.test"}`), nil
	})}, "", "xapp-test")

	socketURL, err := api.OpenSocketURL(t.Context())
	if err != nil {
		t.Fatalf("OpenSocketURL() error = %v", err)
	}
	if socketURL != "wss://socket.test" {
		t.Fatalf("socketURL = %q, want Slack socket URL", socketURL)
	}
}

// TestWebAPIPostMessageUsesBotTokenAndJSON verifies message posts use bot auth.
func TestWebAPIPostMessageUsesBotTokenAndJSON(t *testing.T) {
	api := NewWebAPI(&http.Client{Transport: roundTripFunc(func(req *http.Request) (*http.Response, error) {
		if req.URL.Path != "/api/chat.postMessage" {
			t.Fatalf("path = %q, want chat.postMessage", req.URL.Path)
		}
		if got := req.Header.Get("Authorization"); got != "Bearer xoxb-test" {
			t.Fatalf("Authorization = %q, want bot token", got)
		}
		if got := req.Header.Get("Content-Type"); got != "application/json" {
			t.Fatalf("Content-Type = %q, want application/json", got)
		}
		var body map[string]string
		if err := json.NewDecoder(req.Body).Decode(&body); err != nil {
			t.Fatalf("decode request body: %v", err)
		}
		if body["channel"] != "C1" || body["thread_ts"] != "1.0" || body["text"] != "hello" {
			t.Fatalf("body = %#v, want Slack message payload", body)
		}
		return testHTTPResponse(http.StatusOK, `{"ok":true}`), nil
	})}, "xoxb-test", "")

	if err := api.PostMessage(t.Context(), "C1", "1.0", "hello"); err != nil {
		t.Fatalf("PostMessage() error = %v", err)
	}
}

// TestWebAPIPostMessageReportsSlackError verifies Slack failure envelopes surface.
func TestWebAPIPostMessageReportsSlackError(t *testing.T) {
	api := NewWebAPI(&http.Client{Transport: roundTripFunc(func(_ *http.Request) (*http.Response, error) {
		return testHTTPResponse(http.StatusOK, `{"ok":false,"error":"channel_not_found"}`), nil
	})}, "xoxb-test", "")

	err := api.PostMessage(t.Context(), "C1", "", "hello")
	if err == nil || !strings.Contains(err.Error(), "channel_not_found") {
		t.Fatalf("PostMessage() error = %v, want Slack error", err)
	}
}
