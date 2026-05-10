// This file defines shared command review option payloads.
package review

// Option describes one action the user can choose during local command review.
type Option struct {
	Action      string `json:"action"`
	Label       string `json:"label"`
	Description string `json:"description"`
}
