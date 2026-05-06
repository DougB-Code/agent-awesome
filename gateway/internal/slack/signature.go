// This file verifies Slack HTTP Events API signatures.
package slack

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"
)

const slackSignatureVersion = "v0"

// VerifySignature validates Slack's timestamped HMAC signature for one request.
func VerifySignature(signingSecret string, header http.Header, body []byte, now time.Time) error {
	if signingSecret == "" {
		return fmt.Errorf("signing secret is required")
	}
	timestamp := header.Get("X-Slack-Request-Timestamp")
	if timestamp == "" {
		return fmt.Errorf("missing Slack timestamp")
	}
	seconds, err := strconv.ParseInt(timestamp, 10, 64)
	if err != nil {
		return fmt.Errorf("invalid Slack timestamp")
	}
	if age := now.Sub(time.Unix(seconds, 0)); age > 5*time.Minute || age < -5*time.Minute {
		return fmt.Errorf("stale Slack timestamp")
	}
	actual := header.Get("X-Slack-Signature")
	if !strings.HasPrefix(actual, slackSignatureVersion+"=") {
		return fmt.Errorf("missing Slack signature")
	}
	expected := SlackSignature(signingSecret, timestamp, body)
	if !hmac.Equal([]byte(expected), []byte(actual)) {
		return fmt.Errorf("invalid Slack signature")
	}
	return nil
}

// SlackSignature computes the canonical Slack request signature value.
func SlackSignature(signingSecret string, timestamp string, body []byte) string {
	base := slackSignatureVersion + ":" + timestamp + ":" + string(body)
	mac := hmac.New(sha256.New, []byte(signingSecret))
	_, _ = mac.Write([]byte(base))
	return slackSignatureVersion + "=" + hex.EncodeToString(mac.Sum(nil))
}
