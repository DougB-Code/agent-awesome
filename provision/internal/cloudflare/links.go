package cloudflare

import "net/url"

// WorkerDashboardURL returns the Cloudflare dashboard URL for one Worker.
func WorkerDashboardURL(accountID string, workerName string) string {
	return "https://dash.cloudflare.com/" + url.PathEscape(accountID) + "/workers/services/view/" + url.PathEscape(workerName)
}

// WorkerLogsURL returns the Cloudflare dashboard logs URL for one Worker.
func WorkerLogsURL(accountID string, workerName string) string {
	return WorkerDashboardURL(accountID, workerName) + "/production/observability/logs"
}
