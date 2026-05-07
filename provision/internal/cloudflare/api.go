package cloudflare

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

const defaultAPIBaseURL = "https://api.cloudflare.com/client/v4"

// APIClientOptions stores Cloudflare API client credentials and transport.
type APIClientOptions struct {
	AccountID  string
	APIToken   string
	BaseURL    string
	HTTPClient *http.Client
}

// APIClient calls the Cloudflare v4 API for resources Wrangler does not need to own.
type APIClient struct {
	accountID  string
	apiToken   string
	baseURL    string
	httpClient *http.Client
}

// NewAPIClient creates a direct Cloudflare API client.
func NewAPIClient(options APIClientOptions) (*APIClient, error) {
	accountID := strings.TrimSpace(options.AccountID)
	if accountID == "" {
		return nil, fmt.Errorf("Cloudflare account id is required")
	}
	baseURL := strings.TrimRight(strings.TrimSpace(options.BaseURL), "/")
	if baseURL == "" {
		baseURL = defaultAPIBaseURL
	}
	httpClient := options.HTTPClient
	if httpClient == nil {
		httpClient = &http.Client{Timeout: 30 * time.Second}
	}
	return &APIClient{
		accountID:  accountID,
		apiToken:   strings.TrimSpace(options.APIToken),
		baseURL:    baseURL,
		httpClient: httpClient,
	}, nil
}

// AccountID returns the configured Cloudflare account id.
func (c *APIClient) AccountID() string {
	if c == nil {
		return ""
	}
	return c.accountID
}

// Zone stores one Cloudflare zone summary.
type Zone struct {
	ID     string `json:"id"`
	Name   string `json:"name"`
	Status string `json:"status"`
}

// R2Bucket stores one Cloudflare R2 bucket summary.
type R2Bucket struct {
	Name         string `json:"name"`
	CreationDate string `json:"creation_date"`
}

// WorkerRoute stores one Cloudflare Workers route.
type WorkerRoute struct {
	ID      string `json:"id"`
	Pattern string `json:"pattern"`
	Script  string `json:"script"`
}

// WorkerSecret stores one Worker secret name.
type WorkerSecret struct {
	Name string `json:"name"`
	Type string `json:"type"`
}

// DNSRecord stores one Cloudflare DNS record summary.
type DNSRecord struct {
	ID      string `json:"id"`
	Type    string `json:"type"`
	Name    string `json:"name"`
	Content string `json:"content"`
	Proxied *bool  `json:"proxied"`
}

// APIError stores one Cloudflare API failure.
type APIError struct {
	StatusCode int
	Errors     []APIErrorItem
}

// APIErrorItem stores one Cloudflare API error body item.
type APIErrorItem struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

// Error returns a concise operator-facing Cloudflare API error.
func (e APIError) Error() string {
	message := fmt.Sprintf("Cloudflare API HTTP %d", e.StatusCode)
	if len(e.Errors) > 0 {
		var parts []string
		for _, item := range e.Errors {
			if item.Code != 0 {
				parts = append(parts, fmt.Sprintf("%d: %s", item.Code, item.Message))
			} else {
				parts = append(parts, item.Message)
			}
		}
		message += ": " + strings.Join(parts, "; ")
	}
	if diagnosis := diagnoseAPIError(e); diagnosis != "" {
		message += "\n" + diagnosis
	}
	return message
}

// IsNotFound reports whether an API failure is a missing resource.
func (e APIError) IsNotFound() bool {
	return e.StatusCode == http.StatusNotFound
}

// ResolveZone finds the exact Cloudflare zone by name.
func (c *APIClient) ResolveZone(ctx context.Context, zoneName string) (Zone, error) {
	var zones []Zone
	query := url.Values{}
	query.Set("name", strings.TrimSpace(zoneName))
	query.Set("per_page", "50")
	if err := c.get(ctx, "/zones?"+query.Encode(), &zones); err != nil {
		return Zone{}, err
	}
	for _, zone := range zones {
		if strings.EqualFold(zone.Name, strings.TrimSpace(zoneName)) {
			return zone, nil
		}
	}
	return Zone{}, fmt.Errorf("Cloudflare zone %q was not found", zoneName)
}

// GetR2Bucket reads one R2 bucket and reports whether it exists.
func (c *APIClient) GetR2Bucket(ctx context.Context, bucketName string) (R2Bucket, bool, error) {
	var bucket R2Bucket
	err := c.get(ctx, "/accounts/"+url.PathEscape(c.accountID)+"/r2/buckets/"+url.PathEscape(bucketName), &bucket)
	if apiErr, ok := err.(APIError); ok && apiErr.IsNotFound() {
		return R2Bucket{}, false, nil
	}
	if err != nil {
		return R2Bucket{}, false, err
	}
	return bucket, true, nil
}

// ListR2Buckets reads the account R2 bucket list.
func (c *APIClient) ListR2Buckets(ctx context.Context) ([]R2Bucket, error) {
	var result struct {
		Buckets []R2Bucket `json:"buckets"`
	}
	if err := c.get(ctx, "/accounts/"+url.PathEscape(c.accountID)+"/r2/buckets", &result); err != nil {
		return nil, err
	}
	return result.Buckets, nil
}

// CreateR2Bucket creates one R2 bucket.
func (c *APIClient) CreateR2Bucket(ctx context.Context, bucketName string) error {
	body := map[string]string{"name": bucketName}
	return c.post(ctx, "/accounts/"+url.PathEscape(c.accountID)+"/r2/buckets", body, nil)
}

// DeleteR2Bucket deletes one R2 bucket and reports whether it was present.
func (c *APIClient) DeleteR2Bucket(ctx context.Context, bucketName string) (bool, error) {
	err := c.delete(ctx, "/accounts/"+url.PathEscape(c.accountID)+"/r2/buckets/"+url.PathEscape(bucketName))
	if apiErr, ok := err.(APIError); ok && apiErr.IsNotFound() {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	return true, nil
}

// WorkerScriptExists reports whether one Worker script exists.
func (c *APIClient) WorkerScriptExists(ctx context.Context, workerName string) (bool, error) {
	err := c.raw(ctx, http.MethodGet, "/accounts/"+url.PathEscape(c.accountID)+"/workers/scripts/"+url.PathEscape(workerName))
	if apiErr, ok := err.(APIError); ok && apiErr.IsNotFound() {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	return true, nil
}

// PutWorkerSecret creates or updates one Worker secret.
func (c *APIClient) PutWorkerSecret(ctx context.Context, workerName string, secretName string, secretValue string) error {
	body := map[string]string{
		"name": strings.TrimSpace(secretName),
		"text": secretValue,
		"type": "secret_text",
	}
	return c.put(ctx, "/accounts/"+url.PathEscape(c.accountID)+"/workers/scripts/"+url.PathEscape(workerName)+"/secrets", body, nil)
}

// DeleteWorkerSecret deletes one Worker secret and reports whether it was present.
func (c *APIClient) DeleteWorkerSecret(ctx context.Context, workerName string, secretName string) (bool, error) {
	err := c.delete(ctx, "/accounts/"+url.PathEscape(c.accountID)+"/workers/scripts/"+url.PathEscape(workerName)+"/secrets/"+url.PathEscape(secretName))
	if apiErr, ok := err.(APIError); ok && apiErr.IsNotFound() {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	return true, nil
}

// ListWorkerRoutes reads all Worker routes for one zone.
func (c *APIClient) ListWorkerRoutes(ctx context.Context, zoneID string) ([]WorkerRoute, error) {
	var routes []WorkerRoute
	err := c.get(ctx, "/zones/"+url.PathEscape(zoneID)+"/workers/routes?per_page=100", &routes)
	return routes, err
}

// CreateWorkerRoute creates one Worker route.
func (c *APIClient) CreateWorkerRoute(ctx context.Context, zoneID string, pattern string, workerName string) (WorkerRoute, error) {
	var route WorkerRoute
	body := map[string]string{
		"pattern": pattern,
		"script":  workerName,
	}
	err := c.post(ctx, "/zones/"+url.PathEscape(zoneID)+"/workers/routes", body, &route)
	return route, err
}

// UpdateWorkerRoute updates one Worker route.
func (c *APIClient) UpdateWorkerRoute(ctx context.Context, zoneID string, routeID string, pattern string, workerName string) (WorkerRoute, error) {
	var route WorkerRoute
	body := map[string]string{
		"pattern": pattern,
		"script":  workerName,
	}
	err := c.put(ctx, "/zones/"+url.PathEscape(zoneID)+"/workers/routes/"+url.PathEscape(routeID), body, &route)
	return route, err
}

// DeleteWorkerRoute deletes one Worker route and reports whether it was present.
func (c *APIClient) DeleteWorkerRoute(ctx context.Context, zoneID string, routeID string) (bool, error) {
	err := c.delete(ctx, "/zones/"+url.PathEscape(zoneID)+"/workers/routes/"+url.PathEscape(routeID))
	if apiErr, ok := err.(APIError); ok && apiErr.IsNotFound() {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	return true, nil
}

// ListDNSRecordsByName reads DNS records matching one exact name.
func (c *APIClient) ListDNSRecordsByName(ctx context.Context, zoneID string, name string) ([]DNSRecord, error) {
	var records []DNSRecord
	query := url.Values{}
	query.Set("name", strings.TrimSpace(name))
	query.Set("per_page", "100")
	err := c.get(ctx, "/zones/"+url.PathEscape(zoneID)+"/dns_records?"+query.Encode(), &records)
	return records, err
}

// get sends one authenticated GET request.
func (c *APIClient) get(ctx context.Context, path string, result any) error {
	return c.do(ctx, http.MethodGet, path, nil, result)
}

// post sends one authenticated POST request.
func (c *APIClient) post(ctx context.Context, path string, body any, result any) error {
	return c.do(ctx, http.MethodPost, path, body, result)
}

// put sends one authenticated PUT request.
func (c *APIClient) put(ctx context.Context, path string, body any, result any) error {
	return c.do(ctx, http.MethodPut, path, body, result)
}

// delete sends one authenticated DELETE request.
func (c *APIClient) delete(ctx context.Context, path string) error {
	return c.do(ctx, http.MethodDelete, path, nil, nil)
}

// raw sends one authenticated Cloudflare API request without decoding a success envelope.
func (c *APIClient) raw(ctx context.Context, method string, path string) error {
	if strings.TrimSpace(c.apiToken) == "" {
		return fmt.Errorf("Cloudflare API token is required")
	}
	req, err := http.NewRequestWithContext(ctx, method, c.baseURL+path, nil)
	if err != nil {
		return fmt.Errorf("create Cloudflare API request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+c.apiToken)
	resp, err := c.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("call Cloudflare API: %w", err)
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("read Cloudflare API response: %w", err)
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return decodeAPIError(resp.StatusCode, data)
	}
	return nil
}

// do sends one authenticated Cloudflare API request.
func (c *APIClient) do(ctx context.Context, method string, path string, body any, result any) error {
	if strings.TrimSpace(c.apiToken) == "" {
		return fmt.Errorf("Cloudflare API token is required")
	}
	requestBody, err := encodeRequestBody(body)
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, method, c.baseURL+path, requestBody)
	if err != nil {
		return fmt.Errorf("create Cloudflare API request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+c.apiToken)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, err := c.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("call Cloudflare API: %w", err)
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("read Cloudflare API response: %w", err)
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return decodeAPIError(resp.StatusCode, data)
	}
	if result == nil || len(bytes.TrimSpace(data)) == 0 {
		return nil
	}
	return decodeAPIResult(data, result)
}

// encodeRequestBody marshals one optional JSON request body.
func encodeRequestBody(body any) (io.Reader, error) {
	if body == nil {
		return nil, nil
	}
	data, err := json.Marshal(body)
	if err != nil {
		return nil, fmt.Errorf("encode Cloudflare API request: %w", err)
	}
	return bytes.NewReader(data), nil
}

// decodeAPIResult decodes a Cloudflare API envelope into the requested result.
func decodeAPIResult(data []byte, result any) error {
	var envelope struct {
		Success bool             `json:"success"`
		Errors  []APIErrorItem   `json:"errors"`
		Result  *json.RawMessage `json:"result"`
	}
	if err := json.Unmarshal(data, &envelope); err != nil {
		return fmt.Errorf("decode Cloudflare API response: %w", err)
	}
	if !envelope.Success {
		return APIError{StatusCode: http.StatusOK, Errors: envelope.Errors}
	}
	if envelope.Result == nil {
		return nil
	}
	if err := json.Unmarshal(*envelope.Result, result); err != nil {
		return fmt.Errorf("decode Cloudflare API result: %w", err)
	}
	return nil
}

// decodeAPIError decodes a Cloudflare API error envelope.
func decodeAPIError(statusCode int, data []byte) error {
	var envelope struct {
		Errors []APIErrorItem `json:"errors"`
	}
	if err := json.Unmarshal(data, &envelope); err != nil || len(envelope.Errors) == 0 {
		return APIError{StatusCode: statusCode, Errors: []APIErrorItem{{Message: strings.TrimSpace(string(data))}}}
	}
	return APIError{StatusCode: statusCode, Errors: envelope.Errors}
}

// diagnoseAPIError returns known remediation guidance for API failures.
func diagnoseAPIError(err APIError) string {
	switch err.StatusCode {
	case http.StatusUnauthorized:
		return "diagnosis: the Cloudflare API token is invalid or expired."
	case http.StatusForbidden:
		return "diagnosis: the Cloudflare API token is missing a required permission for this resource."
	case http.StatusNotFound:
		return "diagnosis: the Cloudflare resource was not found, or the token cannot access it."
	default:
		for _, item := range err.Errors {
			lower := strings.ToLower(item.Message)
			if strings.Contains(lower, "already exists") || strings.Contains(lower, "already own") {
				return "diagnosis: the Cloudflare resource already exists."
			}
		}
		return ""
	}
}
