package cloudflare

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

// HealthStatus stores the deployed gateway dependency status.
type HealthStatus struct {
	Services []ServiceStatus
}

// ServiceStatus stores one gateway dependency status.
type ServiceStatus struct {
	Name    string `json:"name"`
	State   string `json:"state"`
	Message string `json:"message"`
}

// WaitForHealth polls the deployed gateway until harness and memory are connected.
func WaitForHealth(ctx context.Context, deployment Deployment, gatewayToken string, timeout time.Duration) (HealthStatus, error) {
	if gatewayToken == "" {
		return HealthStatus{}, fmt.Errorf("gateway token is required for health checks")
	}
	deadline, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()
	var last HealthStatus
	for {
		select {
		case <-deadline.Done():
			return last, fmt.Errorf("health check timed out: %w", deadline.Err())
		case <-ticker.C:
			status, err := fetchHealth(deadline, deployment, gatewayToken)
			if err != nil {
				continue
			}
			last = status
			if allServicesConnected(status.Services) {
				return status, nil
			}
		}
	}
}

// fetchHealth reads the gateway status endpoint once.
func fetchHealth(ctx context.Context, deployment Deployment, gatewayToken string) (HealthStatus, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, "https://"+deployment.Hostname+"/api/gateway/status", nil)
	if err != nil {
		return HealthStatus{}, err
	}
	req.Header.Set("Authorization", "Bearer "+gatewayToken)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return HealthStatus{}, err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return HealthStatus{}, fmt.Errorf("gateway status HTTP %d", resp.StatusCode)
	}
	var decoded struct {
		Services []ServiceStatus `json:"services"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&decoded); err != nil {
		return HealthStatus{}, err
	}
	return HealthStatus{Services: decoded.Services}, nil
}

// allServicesConnected reports whether all expected gateway services are connected.
func allServicesConnected(services []ServiceStatus) bool {
	connected := map[string]bool{}
	for _, service := range services {
		if service.State == "connected" {
			connected[service.Name] = true
		}
	}
	return connected["harness"] && connected["memory"]
}
