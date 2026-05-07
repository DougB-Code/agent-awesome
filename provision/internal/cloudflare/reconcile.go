package cloudflare

import (
	"context"
	"fmt"
	"strings"
)

// ReconcileR2Bucket ensures the deployment's dedicated R2 bucket exists.
func ReconcileR2Bucket(ctx context.Context, deployment Deployment, api *APIClient, dryRun bool, progress ProgressFunc) error {
	command := "cloudflare api r2 bucket ensure " + deployment.BucketName
	if dryRun {
		emitProgress(progress, OperationEvent{Status: OperationPlanned, Command: command})
		return nil
	}
	emitProgress(progress, OperationEvent{Status: OperationRunning, Command: command})
	_, found, err := api.GetR2Bucket(ctx, deployment.BucketName)
	if err != nil {
		emitProgress(progress, OperationEvent{Status: OperationFailed, Command: command})
		return err
	}
	if found {
		emitProgress(progress, OperationEvent{Status: OperationSkipped, Command: command, Message: "bucket already exists"})
		return nil
	}
	if err := api.CreateR2Bucket(ctx, deployment.BucketName); err != nil {
		emitProgress(progress, OperationEvent{Status: OperationFailed, Command: command})
		return err
	}
	emitProgress(progress, OperationEvent{Status: OperationCompleted, Command: command})
	return nil
}

// ReconcileWorkerSecrets creates or updates all Worker secrets required by the deployment.
func ReconcileWorkerSecrets(ctx context.Context, deployment Deployment, secrets SecretValues, api *APIClient, dryRun bool, progress ProgressFunc) error {
	for _, name := range deployment.RequiredSecrets {
		command := "cloudflare api worker secret put " + deployment.WorkerName + "/" + name
		if dryRun {
			emitProgress(progress, OperationEvent{Status: OperationPlanned, Command: command})
			continue
		}
		value := secrets[name]
		if strings.TrimSpace(value) == "" {
			return fmt.Errorf("secret %s is required", name)
		}
		emitProgress(progress, OperationEvent{Status: OperationRunning, Command: command})
		if err := api.PutWorkerSecret(ctx, deployment.WorkerName, name, value); err != nil {
			emitProgress(progress, OperationEvent{Status: OperationFailed, Command: command})
			return err
		}
		emitProgress(progress, OperationEvent{Status: OperationCompleted, Command: command})
	}
	return nil
}

// ValidateDeploymentNetwork checks zone, DNS, and route conflicts before deploy.
func ValidateDeploymentNetwork(ctx context.Context, deployment Deployment, api *APIClient, dryRun bool, progress ProgressFunc) error {
	command := "cloudflare api validate route " + deployment.Hostname + "/*"
	if dryRun {
		emitProgress(progress, OperationEvent{Status: OperationPlanned, Command: command})
		return nil
	}
	emitProgress(progress, OperationEvent{Status: OperationRunning, Command: command})
	zone, err := api.ResolveZone(ctx, deployment.ZoneName)
	if err != nil {
		emitProgress(progress, OperationEvent{Status: OperationFailed, Command: command})
		return err
	}
	if err := validateDNSReady(ctx, api, zone, deployment.Hostname); err != nil {
		emitProgress(progress, OperationEvent{Status: OperationFailed, Command: command})
		return err
	}
	if err := validateWorkerRoute(ctx, api, zone.ID, deployment); err != nil {
		emitProgress(progress, OperationEvent{Status: OperationFailed, Command: command})
		return err
	}
	emitProgress(progress, OperationEvent{Status: OperationCompleted, Command: command, Message: zone.Name})
	return nil
}

// EnsureWorkerRoute creates or repairs the Worker route after deploy.
func EnsureWorkerRoute(ctx context.Context, deployment Deployment, api *APIClient, dryRun bool, progress ProgressFunc) error {
	command := "cloudflare api route ensure " + deployment.Hostname + "/*"
	if dryRun {
		emitProgress(progress, OperationEvent{Status: OperationPlanned, Command: command})
		return nil
	}
	emitProgress(progress, OperationEvent{Status: OperationRunning, Command: command})
	zone, err := api.ResolveZone(ctx, deployment.ZoneName)
	if err != nil {
		emitProgress(progress, OperationEvent{Status: OperationFailed, Command: command})
		return err
	}
	pattern := deployment.Hostname + "/*"
	routes, err := api.ListWorkerRoutes(ctx, zone.ID)
	if err != nil {
		emitProgress(progress, OperationEvent{Status: OperationFailed, Command: command})
		return err
	}
	for _, route := range routes {
		if route.Pattern != pattern {
			continue
		}
		if route.Script == deployment.WorkerName {
			emitProgress(progress, OperationEvent{Status: OperationSkipped, Command: command, Message: "route already assigned"})
			return nil
		}
		if route.Script != "" {
			emitProgress(progress, OperationEvent{Status: OperationFailed, Command: command})
			return fmt.Errorf("route %s is already assigned to Worker %s", pattern, route.Script)
		}
		if _, err := api.UpdateWorkerRoute(ctx, zone.ID, route.ID, pattern, deployment.WorkerName); err != nil {
			emitProgress(progress, OperationEvent{Status: OperationFailed, Command: command})
			return err
		}
		emitProgress(progress, OperationEvent{Status: OperationCompleted, Command: command})
		return nil
	}
	if _, err := api.CreateWorkerRoute(ctx, zone.ID, pattern, deployment.WorkerName); err != nil {
		emitProgress(progress, OperationEvent{Status: OperationFailed, Command: command})
		return err
	}
	emitProgress(progress, OperationEvent{Status: OperationCompleted, Command: command})
	return nil
}

// DeleteR2BucketResource removes the dedicated R2 bucket after object cleanup.
func DeleteR2BucketResource(ctx context.Context, deployment Deployment, api *APIClient, dryRun bool, progress ProgressFunc) error {
	return deleteR2Bucket(ctx, deployment, api, dryRun, progress)
}

// DeleteDeploymentRoute removes the exact Worker route owned by the deployment.
func DeleteDeploymentRoute(ctx context.Context, deployment Deployment, api *APIClient, dryRun bool, progress ProgressFunc) error {
	command := "cloudflare api route delete " + deployment.Hostname + "/*"
	if dryRun {
		emitProgress(progress, OperationEvent{Status: OperationPlanned, Command: command})
		return nil
	}
	emitProgress(progress, OperationEvent{Status: OperationRunning, Command: command})
	zone, err := api.ResolveZone(ctx, deployment.ZoneName)
	if err != nil {
		emitProgress(progress, OperationEvent{Status: OperationFailed, Command: command})
		return err
	}
	pattern := deployment.Hostname + "/*"
	routes, err := api.ListWorkerRoutes(ctx, zone.ID)
	if err != nil {
		emitProgress(progress, OperationEvent{Status: OperationFailed, Command: command})
		return err
	}
	for _, route := range routes {
		if route.Pattern != pattern {
			continue
		}
		if route.Script != "" && route.Script != deployment.WorkerName {
			emitProgress(progress, OperationEvent{Status: OperationSkipped, Command: command, Message: "route belongs to another Worker"})
			return nil
		}
		deleted, err := api.DeleteWorkerRoute(ctx, zone.ID, route.ID)
		if err != nil {
			emitProgress(progress, OperationEvent{Status: OperationFailed, Command: command})
			return err
		}
		if !deleted {
			emitProgress(progress, OperationEvent{Status: OperationSkipped, Command: command, Message: "route already absent"})
			return nil
		}
		emitProgress(progress, OperationEvent{Status: OperationCompleted, Command: command})
		return nil
	}
	emitProgress(progress, OperationEvent{Status: OperationSkipped, Command: command, Message: "route already absent"})
	return nil
}

// validateDNSReady checks for an exact or wildcard DNS record for the agent host.
func validateDNSReady(ctx context.Context, api *APIClient, zone Zone, hostname string) error {
	exact, err := api.ListDNSRecordsByName(ctx, zone.ID, hostname)
	if err != nil {
		return err
	}
	if len(exact) > 0 {
		return nil
	}
	if strings.EqualFold(hostname, zone.Name) {
		return fmt.Errorf("DNS record for %s was not found", hostname)
	}
	wildcard := "*." + zone.Name
	wildcardRecords, err := api.ListDNSRecordsByName(ctx, zone.ID, wildcard)
	if err != nil {
		return err
	}
	if len(wildcardRecords) > 0 {
		return nil
	}
	return fmt.Errorf("DNS record for %s was not found; add an exact or wildcard DNS record in zone %s", hostname, zone.Name)
}

// validateWorkerRoute checks for an existing route owned by a different Worker.
func validateWorkerRoute(ctx context.Context, api *APIClient, zoneID string, deployment Deployment) error {
	routes, err := api.ListWorkerRoutes(ctx, zoneID)
	if err != nil {
		return err
	}
	pattern := deployment.Hostname + "/*"
	for _, route := range routes {
		if route.Pattern != pattern {
			continue
		}
		if route.Script == "" || route.Script == deployment.WorkerName {
			return nil
		}
		return fmt.Errorf("route %s is already assigned to Worker %s", pattern, route.Script)
	}
	return nil
}

// deleteR2Bucket removes the dedicated R2 bucket.
func deleteR2Bucket(ctx context.Context, deployment Deployment, api *APIClient, dryRun bool, progress ProgressFunc) error {
	command := "cloudflare api r2 bucket delete " + deployment.BucketName
	if dryRun {
		emitProgress(progress, OperationEvent{Status: OperationPlanned, Command: command})
		return nil
	}
	emitProgress(progress, OperationEvent{Status: OperationRunning, Command: command})
	deleted, err := api.DeleteR2Bucket(ctx, deployment.BucketName)
	if err != nil {
		emitProgress(progress, OperationEvent{Status: OperationFailed, Command: command})
		return err
	}
	if !deleted {
		emitProgress(progress, OperationEvent{Status: OperationSkipped, Command: command, Message: "bucket already absent"})
		return nil
	}
	emitProgress(progress, OperationEvent{Status: OperationCompleted, Command: command})
	return nil
}
