package cloudflare

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// TestReconcileR2BucketCreatesMissingBucket verifies direct API bucket creation is idempotent.
func TestReconcileR2BucketCreatesMissingBucket(t *testing.T) {
	var created bool
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.Method == http.MethodGet && r.URL.Path == "/accounts/account/r2/buckets/agent-awesome-sister-memory":
			if created {
				writeAPIResult(w, map[string]string{"name": "agent-awesome-sister-memory"})
				return
			}
			w.WriteHeader(http.StatusNotFound)
			_, _ = w.Write([]byte(`{"success":false,"errors":[{"code":10007,"message":"not found"}]}`))
		case r.Method == http.MethodPost && r.URL.Path == "/accounts/account/r2/buckets":
			created = true
			writeAPIResult(w, map[string]string{"name": "agent-awesome-sister-memory"})
		default:
			t.Fatalf("unexpected request %s %s", r.Method, r.URL.String())
		}
	}))
	defer server.Close()
	api := newTestAPIClient(t, server.URL)
	deployment := testDeployment(t)

	if err := ReconcileR2Bucket(t.Context(), deployment, api, false, nil); err != nil {
		t.Fatalf("ReconcileR2Bucket() error = %v", err)
	}
	if !created {
		t.Fatalf("bucket was not created")
	}
	if err := ReconcileR2Bucket(t.Context(), deployment, api, false, nil); err != nil {
		t.Fatalf("ReconcileR2Bucket() second error = %v", err)
	}
}

// TestValidateDeploymentNetworkRejectsRouteConflict verifies route conflicts stop deploys early.
func TestValidateDeploymentNetworkRejectsRouteConflict(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.Method == http.MethodGet && r.URL.Path == "/zones" && r.URL.Query().Get("name") == "agent-awesome.com":
			writeAPIResult(w, []Zone{{ID: "zone", Name: "agent-awesome.com", Status: "active"}})
		case r.Method == http.MethodGet && r.URL.Path == "/zones/zone/dns_records":
			writeAPIResult(w, []DNSRecord{{ID: "dns", Name: r.URL.Query().Get("name"), Type: "CNAME"}})
		case r.Method == http.MethodGet && r.URL.Path == "/zones/zone/workers/routes":
			writeAPIResult(w, []WorkerRoute{{ID: "route", Pattern: "sister.agent-awesome.com/*", Script: "other-worker"}})
		default:
			t.Fatalf("unexpected request %s %s", r.Method, r.URL.String())
		}
	}))
	defer server.Close()

	err := ValidateDeploymentNetwork(t.Context(), testDeployment(t), newTestAPIClient(t, server.URL), false, nil)
	if err == nil || !strings.Contains(err.Error(), "other-worker") {
		t.Fatalf("ValidateDeploymentNetwork() error = %v, want route conflict", err)
	}
}

// TestReconcileWorkerSecretsPutsRequiredSecrets verifies direct secret upload uses safe names.
func TestReconcileWorkerSecretsPutsRequiredSecrets(t *testing.T) {
	var seen []string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPut || r.URL.Path != "/accounts/account/workers/scripts/agent-awesome-sister/secrets" {
			t.Fatalf("unexpected request %s %s", r.Method, r.URL.String())
		}
		var body map[string]string
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			t.Fatalf("decode request body: %v", err)
		}
		seen = append(seen, body["name"])
		if body["type"] != "secret_text" || body["text"] == "" {
			t.Fatalf("secret request body = %#v", body)
		}
		writeAPIResult(w, map[string]string{"id": body["name"]})
	}))
	defer server.Close()

	deployment := testDeployment(t)
	secrets := SecretValues{
		"OPENAI_API_KEY":                 "openai",
		"AGENTAWESOME_GATEWAY_TOKEN":     "gateway",
		"AGENTAWESOME_PERSISTENCE_TOKEN": "persistence",
	}
	if err := ReconcileWorkerSecrets(t.Context(), deployment, secrets, newTestAPIClient(t, server.URL), false, nil); err != nil {
		t.Fatalf("ReconcileWorkerSecrets() error = %v", err)
	}
	if len(seen) != len(deployment.RequiredSecrets) {
		t.Fatalf("uploaded secrets = %v, want %v", seen, deployment.RequiredSecrets)
	}
}

// TestEnsureWorkerRouteCreatesMissingRoute verifies direct route reconciliation can repair drift.
func TestEnsureWorkerRouteCreatesMissingRoute(t *testing.T) {
	var created bool
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.Method == http.MethodGet && r.URL.Path == "/zones" && r.URL.Query().Get("name") == "agent-awesome.com":
			writeAPIResult(w, []Zone{{ID: "zone", Name: "agent-awesome.com"}})
		case r.Method == http.MethodGet && r.URL.Path == "/zones/zone/workers/routes":
			writeAPIResult(w, []WorkerRoute{})
		case r.Method == http.MethodPost && r.URL.Path == "/zones/zone/workers/routes":
			created = true
			writeAPIResult(w, WorkerRoute{ID: "route", Pattern: "sister.agent-awesome.com/*", Script: "agent-awesome-sister"})
		default:
			t.Fatalf("unexpected request %s %s", r.Method, r.URL.String())
		}
	}))
	defer server.Close()

	if err := EnsureWorkerRoute(t.Context(), testDeployment(t), newTestAPIClient(t, server.URL), false, nil); err != nil {
		t.Fatalf("EnsureWorkerRoute() error = %v", err)
	}
	if !created {
		t.Fatalf("route was not created")
	}
}

// TestDeleteDeploymentRouteDeletesOwnedRoute verifies direct route cleanup avoids stale routes.
func TestDeleteDeploymentRouteDeletesOwnedRoute(t *testing.T) {
	var deleted bool
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.Method == http.MethodGet && r.URL.Path == "/zones" && r.URL.Query().Get("name") == "agent-awesome.com":
			writeAPIResult(w, []Zone{{ID: "zone", Name: "agent-awesome.com"}})
		case r.Method == http.MethodGet && r.URL.Path == "/zones/zone/workers/routes":
			writeAPIResult(w, []WorkerRoute{{ID: "route", Pattern: "sister.agent-awesome.com/*", Script: "agent-awesome-sister"}})
		case r.Method == http.MethodDelete && r.URL.Path == "/zones/zone/workers/routes/route":
			deleted = true
			writeAPIResult(w, nil)
		default:
			t.Fatalf("unexpected request %s %s", r.Method, r.URL.String())
		}
	}))
	defer server.Close()

	if err := DeleteDeploymentRoute(t.Context(), testDeployment(t), newTestAPIClient(t, server.URL), false, nil); err != nil {
		t.Fatalf("DeleteDeploymentRoute() error = %v", err)
	}
	if !deleted {
		t.Fatalf("route was not deleted")
	}
}

// TestDeleteR2BucketResourceIgnoresMissingBucket verifies delete can repair partial cleanup.
func TestDeleteR2BucketResourceIgnoresMissingBucket(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodDelete {
			t.Fatalf("unexpected method %s", r.Method)
		}
		if r.URL.Path != "/accounts/account/r2/buckets/agent-awesome-sister-memory" {
			t.Fatalf("unexpected path %s", r.URL.String())
		}
		w.WriteHeader(http.StatusNotFound)
		_, _ = w.Write([]byte(`{"success":false,"errors":[{"message":"not found"}]}`))
	}))
	defer server.Close()

	if err := DeleteR2BucketResource(t.Context(), testDeployment(t), newTestAPIClient(t, server.URL), false, nil); err != nil {
		t.Fatalf("DeleteR2BucketResource() error = %v", err)
	}
}

// newTestAPIClient creates one direct API test client.
func newTestAPIClient(t *testing.T, baseURL string) *APIClient {
	t.Helper()
	api, err := NewAPIClient(APIClientOptions{
		AccountID: "account",
		APIToken:  "token",
		BaseURL:   baseURL,
	})
	if err != nil {
		t.Fatalf("NewAPIClient() error = %v", err)
	}
	return api
}

// testDeployment returns one valid Cloudflare deployment for API tests.
func testDeployment(t *testing.T) Deployment {
	t.Helper()
	deployment, err := NewDeployment(DeploymentInput{
		AgentID:  "sister",
		UserID:   "sister",
		Hostname: "sister.agent-awesome.com",
		ZoneName: "agent-awesome.com",
	})
	if err != nil {
		t.Fatalf("NewDeployment() error = %v", err)
	}
	return deployment
}

// writeAPIResult writes one Cloudflare API success envelope.
func writeAPIResult(w http.ResponseWriter, result any) {
	w.Header().Set("Content-Type", "application/json")
	data, _ := json.Marshal(map[string]any{
		"success": true,
		"errors":  []any{},
		"result":  result,
	})
	_, _ = w.Write(data)
}
