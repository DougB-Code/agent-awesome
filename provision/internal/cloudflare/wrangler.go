package cloudflare

// WranglerConfig stores the Cloudflare Worker deployment manifest.
type WranglerConfig struct {
	Schema         string                 `json:"$schema"`
	Name           string                 `json:"name"`
	Main           string                 `json:"main"`
	Compatibility  string                 `json:"compatibility_date"`
	WorkersDev     bool                   `json:"workers_dev"`
	Routes         []WranglerRoute        `json:"routes,omitempty"`
	Observability  WranglerObservability  `json:"observability"`
	Vars           map[string]string      `json:"vars"`
	Secrets        WranglerSecrets        `json:"secrets"`
	R2Buckets      []WranglerR2Bucket     `json:"r2_buckets"`
	Containers     []WranglerContainer    `json:"containers"`
	DurableObjects WranglerDurableObjects `json:"durable_objects"`
	Migrations     []WranglerMigration    `json:"migrations"`
}

// WranglerRoute stores one Worker route binding.
type WranglerRoute struct {
	Pattern  string `json:"pattern"`
	ZoneName string `json:"zone_name"`
}

// WranglerObservability stores Worker logging configuration.
type WranglerObservability struct {
	Logs   WranglerLogs  `json:"logs"`
	Traces WranglerTrace `json:"traces"`
}

// WranglerLogs stores Worker log settings.
type WranglerLogs struct {
	Enabled        bool `json:"enabled"`
	InvocationLogs bool `json:"invocation_logs"`
}

// WranglerTrace stores Worker trace settings.
type WranglerTrace struct {
	Enabled bool `json:"enabled"`
}

// WranglerSecrets stores required secret names.
type WranglerSecrets struct {
	Required []string `json:"required,omitempty"`
}

// WranglerR2Bucket stores one R2 binding.
type WranglerR2Bucket struct {
	Binding    string `json:"binding"`
	BucketName string `json:"bucket_name"`
}

// WranglerContainer stores one Cloudflare Container binding.
type WranglerContainer struct {
	ClassName         string `json:"class_name"`
	Image             string `json:"image"`
	ImageBuildContext string `json:"image_build_context"`
	MaxInstances      int    `json:"max_instances"`
}

// WranglerDurableObjects stores Durable Object bindings.
type WranglerDurableObjects struct {
	Bindings []WranglerDurableObjectBinding `json:"bindings"`
}

// WranglerDurableObjectBinding stores one Durable Object binding.
type WranglerDurableObjectBinding struct {
	Name      string `json:"name"`
	ClassName string `json:"class_name"`
}

// WranglerMigration stores one Durable Object migration.
type WranglerMigration struct {
	Tag              string   `json:"tag"`
	NewSQLiteClasses []string `json:"new_sqlite_classes"`
}

// Wrangler builds the Worker manifest for this deployment.
func (d Deployment) Wrangler() WranglerConfig {
	return WranglerConfig{
		Schema:        "node_modules/wrangler/config-schema.json",
		Name:          d.WorkerName,
		Main:          "src/index.ts",
		Compatibility: "2026-05-05",
		WorkersDev:    false,
		Routes: []WranglerRoute{
			{Pattern: d.Hostname + "/*", ZoneName: d.ZoneName},
		},
		Observability: WranglerObservability{
			Logs:   WranglerLogs{Enabled: true, InvocationLogs: true},
			Traces: WranglerTrace{Enabled: false},
		},
		Vars:           d.vars(),
		Secrets:        WranglerSecrets{Required: d.RequiredSecrets},
		R2Buckets:      []WranglerR2Bucket{{Binding: "CONTEXT_SNAPSHOTS", BucketName: d.BucketName}},
		Containers:     []WranglerContainer{{ClassName: "AgentAwesomeContainer", Image: "../../../Dockerfile.cloudflare", ImageBuildContext: "../../..", MaxInstances: 1}},
		DurableObjects: WranglerDurableObjects{Bindings: []WranglerDurableObjectBinding{{Name: "AGENT_AWESOME_CONTAINER", ClassName: "AgentAwesomeContainer"}}},
		Migrations:     []WranglerMigration{{Tag: "v1", NewSQLiteClasses: []string{"AgentAwesomeContainer"}}},
	}
}

// BootstrapWrangler builds a private initial manifest without route or required secrets.
func (d Deployment) BootstrapWrangler() WranglerConfig {
	config := d.Wrangler()
	config.Routes = nil
	config.Secrets = WranglerSecrets{}
	return config
}

// vars returns non-secret Worker environment variables for this deployment.
func (d Deployment) vars() map[string]string {
	return map[string]string{
		"AGENTAWESOME_APP_NAME":                defaultAgentAppName,
		"AGENTAWESOME_USER_ID":                 d.UserID,
		"AGENTAWESOME_CONTEXT_API_BASE_URL":    defaultContextAPIBaseURL,
		"AGENTAWESOME_MEMORY_SNAPSHOT_URL":     d.SnapshotURL,
		"AGENTAWESOME_MEMORY_SNAPSHOT_KEY":     d.SnapshotKey,
		"AGENTAWESOME_MODEL_PROVIDER_ID":       defaultModelProviderID,
		"AGENTAWESOME_MODEL_ID":                defaultModelID,
		"AGENTAWESOME_GATEWAY_REQUEST_TIMEOUT": defaultRequestTimeout,
		"AGENTAWESOME_SERVICE_START_TIMEOUT":   defaultStartTimeout,
		"SLACK_ENABLED":                        boolString(d.SlackEnabled),
		"SLACK_SOCKET_MODE":                    "false",
		"SLACK_ALLOWED_TEAM_ID":                d.SlackAllowedTeamID,
		"SLACK_ALLOWED_USER_ID":                d.SlackAllowedUserID,
		"SLACK_ALLOWED_CHANNEL_ID":             d.SlackAllowedChannelID,
	}
}

// zoneName derives the zone apex from the hostname.
func zoneName(hostname string) string {
	parts := splitHost(hostname)
	if len(parts) < 2 {
		return hostname
	}
	return parts[len(parts)-2] + "." + parts[len(parts)-1]
}

// splitHost splits a host without keeping empty labels.
func splitHost(hostname string) []string {
	var labels []string
	start := 0
	for index, current := range hostname {
		if current != '.' {
			continue
		}
		if start < index {
			labels = append(labels, hostname[start:index])
		}
		start = index + 1
	}
	if start < len(hostname) {
		labels = append(labels, hostname[start:])
	}
	return labels
}

// boolString renders booleans in the env format the container already expects.
func boolString(value bool) string {
	if value {
		return "true"
	}
	return "false"
}
