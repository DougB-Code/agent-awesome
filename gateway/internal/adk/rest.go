// This file centralizes ADK REST URL and request body shapes.
package adk

import (
	"encoding/json"
	"net/url"
	"strings"
)

const runSSEPath = "/run_sse"

// ConfirmationFunctionName is the ADK runtime function used for tool approvals.
const ConfirmationFunctionName = "adk_request_confirmation"

// RunSSEPath returns the ADK REST path used for SSE run requests.
func RunSSEPath() string {
	return runSSEPath
}

// SessionsURL builds the ADK REST sessions collection URL.
func SessionsURL(baseURL string, appName string, userID string) string {
	return trimTrailingSlash(baseURL) + "/apps/" + url.PathEscape(appName) + "/users/" + url.PathEscape(userID) + "/sessions"
}

// SessionURL builds the ADK REST session resource URL.
func SessionURL(baseURL string, appName string, userID string, sessionID string) string {
	return SessionsURL(baseURL, appName, userID) + "/" + url.PathEscape(sessionID)
}

// RunSSEURL builds the ADK REST run_sse endpoint URL.
func RunSSEURL(baseURL string) string {
	return trimTrailingSlash(baseURL) + runSSEPath
}

// RunRequestBody builds the JSON body for one non-streaming text run.
func RunRequestBody(appName string, userID string, sessionID string, text string) ([]byte, error) {
	return runBody(appName, userID, sessionID, runPart{Text: text})
}

// RunConfirmationResponseBody builds the JSON body for a tool-confirmation reply.
func RunConfirmationResponseBody(appName string, userID string, sessionID string, callID string, confirmed bool) ([]byte, error) {
	return runBody(appName, userID, sessionID, runPart{
		FunctionResponse: &runFunctionResponse{
			ID:   callID,
			Name: ConfirmationFunctionName,
			Response: map[string]any{
				"confirmed": confirmed,
			},
		},
	})
}

// runBody builds the shared ADK run request envelope.
func runBody(appName string, userID string, sessionID string, part runPart) ([]byte, error) {
	return json.Marshal(runRequest{
		AppName:   appName,
		UserID:    userID,
		SessionID: sessionID,
		Streaming: false,
		NewMessage: runMessage{
			Role:  "user",
			Parts: []runPart{part},
		},
	})
}

// SessionCreateBody builds the JSON body for creating an empty ADK session.
func SessionCreateBody() ([]byte, error) {
	return json.Marshal(sessionCreateRequest{
		State: map[string]any{},
	})
}

// runRequest stores the ADK REST run request shape.
type runRequest struct {
	AppName    string     `json:"appName"`
	UserID     string     `json:"userId"`
	SessionID  string     `json:"sessionId"`
	Streaming  bool       `json:"streaming"`
	NewMessage runMessage `json:"newMessage"`
}

// runMessage stores one ADK message in a run request.
type runMessage struct {
	Role  string    `json:"role"`
	Parts []runPart `json:"parts"`
}

// runPart stores one text part in an ADK message.
type runPart struct {
	Text             string               `json:"text,omitempty"`
	FunctionResponse *runFunctionResponse `json:"functionResponse,omitempty"`
}

// runFunctionResponse stores one ADK function response part.
type runFunctionResponse struct {
	ID       string         `json:"id"`
	Name     string         `json:"name"`
	Response map[string]any `json:"response"`
}

// sessionCreateRequest stores the ADK REST session creation shape.
type sessionCreateRequest struct {
	State map[string]any `json:"state"`
}

// trimTrailingSlash removes trailing slashes from a URL string.
func trimTrailingSlash(value string) string {
	return strings.TrimRight(value, "/")
}
