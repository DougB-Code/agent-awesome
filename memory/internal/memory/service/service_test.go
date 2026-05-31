package service

import (
	"context"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"memory/internal/memory/domain"
	graphrepo "memory/internal/memory/graph/repository"
)

// TestSearchMemoryBuildsRetrievalBundle verifies service-level retrieval context.
func TestSearchMemoryBuildsRetrievalBundle(t *testing.T) {
	ctx := context.Background()
	service := newTestService(t)

	first, err := service.Capture(ctx, domain.CaptureRequest{
		Content:  "bundle source one",
		Title:    "Bundle one",
		Firewall: domain.FirewallUser,
		Source:   domain.SourceRef{System: "test", ID: "one"},
	})
	if err != nil {
		t.Fatalf("capture first: %v", err)
	}
	if _, err := service.Capture(ctx, domain.CaptureRequest{
		Content:  "bundle source two",
		Title:    "Bundle two",
		Firewall: domain.FirewallUser,
		Source:   domain.SourceRef{System: "test", ID: "two"},
	}); err != nil {
		t.Fatalf("capture second: %v", err)
	}
	bundle, err := service.SearchMemory(ctx, domain.RetrievalQuery{Firewall: domain.FirewallUser, Text: "bundle", Limit: 10})
	if err != nil {
		t.Fatalf("search memory: %v", err)
	}
	if len(bundle.Primary) != 2 || len(bundle.Supporting) != 1 || len(bundle.Provenance) != 2 {
		t.Fatalf("bundle sizes = primary %d supporting %d provenance %d", len(bundle.Primary), len(bundle.Supporting), len(bundle.Provenance))
	}
	foundFirst := false
	for _, record := range bundle.Primary {
		foundFirst = foundFirst || record.ID == first.MemoryID
	}
	if !foundFirst {
		t.Fatalf("bundle primary records = %#v, want memory %s", bundle.Primary, first.MemoryID)
	}
}

// TestSearchSourcesHydratesRawText verifies source search includes raw content.
func TestSearchSourcesHydratesRawText(t *testing.T) {
	ctx := context.Background()
	service := newTestService(t)

	if _, err := service.Capture(ctx, domain.CaptureRequest{
		Content:  "raw source text to hydrate",
		Title:    "Hydration",
		Firewall: domain.FirewallUser,
	}); err != nil {
		t.Fatalf("capture: %v", err)
	}
	bundle, err := service.SearchSources(ctx, domain.RetrievalQuery{Firewall: domain.FirewallUser, Text: "hydrate"})
	if err != nil {
		t.Fatalf("search sources: %v", err)
	}
	if len(bundle.Primary) != 1 || bundle.Primary[0].Raw == nil {
		t.Fatalf("primary source = %#v, want hydrated raw source", bundle.Primary)
	}
	if !strings.Contains(bundle.Primary[0].Raw.ContentText, "raw source text") {
		t.Fatalf("raw content = %q, want source text", bundle.Primary[0].Raw.ContentText)
	}
}

// TestBetaMemoryFlowRemembersSearchesAndLoadsContext verifies the core beta memory path.
func TestBetaMemoryFlowRemembersSearchesAndLoadsContext(t *testing.T) {
	ctx := context.Background()
	service := newTestService(t)
	captured, err := service.Capture(ctx, domain.CaptureRequest{
		Content:        "Beta memory flow prefers concise status updates.",
		Title:          "Beta status preference",
		Firewall:       domain.FirewallUser,
		Kind:           domain.KindProfileFact,
		TrustLevel:     domain.TrustUserAsserted,
		EntityNames:    []string{"Beta User"},
		Topics:         []string{"status"},
		IdempotencyKey: "beta-memory-flow",
	})
	if err != nil {
		t.Fatalf("capture beta memory: %v", err)
	}
	bundle, err := service.SearchSources(ctx, domain.RetrievalQuery{Firewall: domain.FirewallUser, Text: "concise status", Limit: 10})
	if err != nil {
		t.Fatalf("search beta memory: %v", err)
	}
	if len(bundle.Primary) != 1 || bundle.Primary[0].ID != captured.MemoryID {
		t.Fatalf("primary memory = %#v, want %s", bundle.Primary, captured.MemoryID)
	}
	if bundle.Primary[0].Raw == nil || !strings.Contains(bundle.Primary[0].Raw.ContentText, "concise status") {
		t.Fatalf("raw memory = %#v, want source text", bundle.Primary[0].Raw)
	}
	entityPage, err := service.LoadEntityPage(ctx, domain.FirewallUser, domain.EntityID("entity:beta-user"), "Beta User")
	if err != nil {
		t.Fatalf("load entity page: %v", err)
	}
	timeline, err := service.LoadTimeline(ctx, domain.FirewallUser, "status", domain.EntityID("entity:beta-user"))
	if err != nil {
		t.Fatalf("load timeline: %v", err)
	}
	if entityPage.ID == "" || timeline.ID == "" {
		t.Fatalf("context pages = %#v %#v, want created pages", entityPage, timeline)
	}
}

// TestOrganizeMemoryCreatesIdempotentFollowUpTasks verifies maintenance follow-ups.
func TestOrganizeMemoryCreatesIdempotentFollowUpTasks(t *testing.T) {
	ctx := context.Background()
	service := newTestService(t)
	captured, err := service.Capture(ctx, domain.CaptureRequest{
		Content:        "Met Jordan",
		Title:          "Untitled memory",
		Firewall:       domain.FirewallUser,
		IdempotencyKey: "needs-clarification",
	})
	if err != nil {
		t.Fatalf("capture unclear memory: %v", err)
	}
	result, err := service.OrganizeMemory(ctx, domain.OrganizeMemoryRequest{
		Actor:    "agent:organizer",
		Firewall: domain.FirewallUser,
		Limit:    10,
	})
	if err != nil {
		t.Fatalf("organize memory: %v", err)
	}
	if result.Reviewed != 1 || len(result.Items) != 1 || len(result.FollowUpTasks) != 1 {
		t.Fatalf("organization result = %#v, want one reviewed follow-up", result)
	}
	item := result.Items[0]
	if item.MemoryID != captured.MemoryID || len(item.Questions) < 3 {
		t.Fatalf("organization item = %#v, want detailed questions for %s", item, captured.MemoryID)
	}
	task := result.FollowUpTasks[0]
	if task.ID == "" || task.MemoryLinks[0].MemoryID != string(captured.MemoryID) {
		t.Fatalf("follow-up task = %#v, want linked memory task", task)
	}

	again, err := service.OrganizeMemory(ctx, domain.OrganizeMemoryRequest{Firewall: domain.FirewallUser})
	if err != nil {
		t.Fatalf("organize memory again: %v", err)
	}
	if len(again.FollowUpTasks) != 1 || again.FollowUpTasks[0].ID != task.ID {
		t.Fatalf("second organization = %#v, want idempotent task %s", again.FollowUpTasks, task.ID)
	}
}

// TestCodebaseCatalogServiceRoundTrip verifies service-level codebase methods.
func TestCodebaseCatalogServiceRoundTrip(t *testing.T) {
	ctx := context.Background()
	service := newTestService(t)
	saved, err := service.UpsertCodebase(ctx, domain.UpsertCodebaseRequest{Codebase: domain.Codebase{
		Name:           "Agent Awesome",
		Aliases:        []string{"AA"},
		RepositoryPath: "/repo/agent",
		DefaultRemote:  "origin",
		DefaultBranch:  "main",
	}})
	if err != nil {
		t.Fatalf("UpsertCodebase() error = %v", err)
	}
	resolved, err := service.ResolveCodebase(ctx, domain.ResolveCodebaseRequest{Query: "AA"})
	if err != nil {
		t.Fatalf("ResolveCodebase() error = %v", err)
	}
	if resolved.Status != "matched" || resolved.Codebase == nil || resolved.Codebase.ID != saved.ID {
		t.Fatalf("resolution = %#v, want saved codebase", resolved)
	}
}

// TestStewardDisabledWorkersComplete verifies the service works without a steward.
func TestStewardDisabledWorkersComplete(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	root := t.TempDir()
	repo, err := graphrepo.OpenPool(ctx, graphrepo.Config{
		DBPath:   filepath.Join(root, "graph.db"),
		DataRoot: filepath.Join(root, "data"),
	})
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	service := New(RepositoriesFrom(repo), nil, Config{WorkerCount: 2, PollInterval: 10 * time.Millisecond})
	service.Start(ctx)
	defer service.Close(context.Background())

	if _, err := service.Capture(ctx, domain.CaptureRequest{Content: "worker source", Firewall: domain.FirewallUser}); err != nil {
		t.Fatalf("capture: %v", err)
	}
	deadline := time.Now().Add(4 * time.Second)
	for time.Now().Before(deadline) {
		metrics, err := service.Metrics(ctx)
		if err != nil {
			t.Fatalf("metrics: %v", err)
		}
		if metrics.PendingJobs == 0 && metrics.FailedJobs == 0 {
			return
		}
		time.Sleep(25 * time.Millisecond)
	}
	metrics, _ := service.Metrics(ctx)
	t.Fatalf("workers did not drain jobs: %#v", metrics)
}

// TestBetaTaskFlowUpdatesCompletesListsAndProjects verifies the core beta task path.
func TestBetaTaskFlowUpdatesCompletesListsAndProjects(t *testing.T) {
	ctx := context.Background()
	service := newTestService(t)
	created, err := service.CreateTask(ctx, domain.CreateTaskRequest{
		Title:  "Send beta welcome note",
		Topics: []string{"beta"},
	})
	if err != nil {
		t.Fatalf("create beta task: %v", err)
	}
	priority := domain.TaskPriorityHigh
	updated, err := service.UpdateTask(ctx, domain.UpdateTaskRequest{
		TaskID:   created.ID,
		Priority: &priority,
		Topics:   []string{"beta", "welcome"},
	})
	if err != nil {
		t.Fatalf("update beta task: %v", err)
	}
	if updated.Priority != domain.TaskPriorityHigh {
		t.Fatalf("updated priority = %q, want high", updated.Priority)
	}
	completed, err := service.CompleteTask(ctx, domain.TaskIDRequest{TaskID: created.ID})
	if err != nil {
		t.Fatalf("complete beta task: %v", err)
	}
	if completed.Status != domain.TaskStatusDone {
		t.Fatalf("completed status = %q, want done", completed.Status)
	}
	tasks, err := service.ListTasks(ctx, domain.TaskQuery{Topics: []string{"welcome"}, IncludeDone: true, Limit: 10})
	if err != nil {
		t.Fatalf("list beta tasks: %v", err)
	}
	if len(tasks) != 1 || tasks[0].ID != created.ID {
		t.Fatalf("listed tasks = %#v, want %s", tasks, created.ID)
	}
	summary, err := service.ProjectExecutiveSummary(ctx, domain.ExecutiveSummaryQuery{Now: timePtr(time.Date(2026, 5, 9, 9, 24, 0, 0, time.UTC))})
	if err != nil {
		t.Fatalf("project beta summary: %v", err)
	}
	if len(summary.Metrics) != 4 {
		t.Fatalf("summary metrics = %#v, want beta projection metrics", summary.Metrics)
	}
}

// TestProjectExecutiveSummaryReturnsEmptyUsefulProjection verifies empty graphs stay explicit.
func TestProjectExecutiveSummaryReturnsEmptyUsefulProjection(t *testing.T) {
	ctx := context.Background()
	service := newTestService(t)
	now := time.Date(2026, 5, 9, 9, 24, 0, 0, time.UTC)

	summary, err := service.ProjectExecutiveSummary(ctx, domain.ExecutiveSummaryQuery{Now: &now})
	if err != nil {
		t.Fatalf("project executive summary: %v", err)
	}
	if summary.SchemaVersion != domain.ExecutiveSummarySchemaVersion || summary.Title != "Today" {
		t.Fatalf("summary identity = %q/%q, want Today schema", summary.SchemaVersion, summary.Title)
	}
	if len(summary.Metrics) != 4 || len(summary.OpenLoops.Categories) == 0 || len(summary.TimeHorizon.Buckets) != 5 {
		t.Fatalf("summary sections missing: metrics=%d open_loops=%d horizon=%d", len(summary.Metrics), len(summary.OpenLoops.Categories), len(summary.TimeHorizon.Buckets))
	}
	if summary.Quality.Label != "Sparse" || !containsTestString(summary.Coverage.NotConnected, "Calendar") {
		t.Fatalf("quality/coverage = %#v %#v, want sparse unknown integrations", summary.Quality, summary.Coverage)
	}
}

// TestProjectExecutiveSummaryClassifiesTaskGraph verifies core Today policies.
func TestProjectExecutiveSummaryClassifiesTaskGraph(t *testing.T) {
	ctx := context.Background()
	service := newTestService(t)
	now := time.Date(2026, 5, 9, 9, 24, 0, 0, time.UTC)
	yesterday := now.Add(-24 * time.Hour)
	decision, err := service.CreateTask(ctx, domain.CreateTaskRequest{
		Title: "Approve vendor payment prep",
		DueAt: &yesterday,
	})
	if err != nil {
		t.Fatalf("create decision: %v", err)
	}
	if _, err := service.CreateTask(ctx, domain.CreateTaskRequest{
		Title:           "Draft Jordan follow-up",
		Description:     "Safe note for review",
		Project:         "Relationships",
		EstimateMinutes: 30,
	}); err != nil {
		t.Fatalf("create delegation: %v", err)
	}
	if _, err := service.CreateTask(ctx, domain.CreateTaskRequest{
		Title:      "Reply to Sarah",
		Person:     "Sarah",
		FollowUpAt: &yesterday,
	}); err != nil {
		t.Fatalf("create follow-up: %v", err)
	}
	blocker, err := service.CreateTask(ctx, domain.CreateTaskRequest{
		Title:           "Collect forecast inputs",
		EstimateMinutes: 15,
		Person:          "Alex",
	})
	if err != nil {
		t.Fatalf("create blocker: %v", err)
	}
	blockedStatus := domain.TaskStatusBlocked
	blocked, err := service.CreateTask(ctx, domain.CreateTaskRequest{
		Title:  "Budget decision",
		Status: blockedStatus,
	})
	if err != nil {
		t.Fatalf("create blocked: %v", err)
	}
	if _, err := service.UpsertTaskRelation(ctx, domain.UpsertTaskRelationRequest{
		FromTaskID: blocker.ID,
		Type:       domain.TaskRelationBlocks,
		ToTaskID:   blocked.ID,
	}); err != nil {
		t.Fatalf("upsert blocker relation: %v", err)
	}

	summary, err := service.ProjectExecutiveSummary(ctx, domain.ExecutiveSummaryQuery{Now: &now, MaxItems: 12})
	if err != nil {
		t.Fatalf("project executive summary: %v", err)
	}
	if !summaryHasLane(summary, "decide") || !summaryHasLane(summary, "follow_up") || !summaryHasLane(summary, "delegate") {
		t.Fatalf("attention lanes = %#v, want decide/follow_up/delegate", summary.Attention.Items)
	}
	if delegationBucket(summary, "can_do_now") == 0 || len(summary.RiskUnblocks.Chains) == 0 {
		t.Fatalf("delegation/risk = %#v %#v, want safe delegation and unblock chain", summary.Delegation, summary.RiskUnblocks)
	}
	explanation, err := service.ExplainExecutiveSummaryItem(ctx, domain.ExplainExecutiveSummaryItemQuery{
		ItemID: "attention:decide:" + string(decision.ID),
	})
	if err != nil {
		t.Fatalf("explain executive summary item: %v", err)
	}
	if explanation.Title != decision.Title || len(explanation.Evidence) == 0 {
		t.Fatalf("explanation = %#v, want decision sources", explanation)
	}
}

// newTestService creates an isolated service with local durable storage.
func newTestService(t *testing.T) *Service {
	t.Helper()
	root := t.TempDir()
	repo, err := graphrepo.OpenPool(context.Background(), graphrepo.Config{
		DBPath:   filepath.Join(root, "graph.db"),
		DataRoot: filepath.Join(root, "data"),
	})
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	t.Cleanup(func() { _ = repo.Close() })
	return New(RepositoriesFrom(repo), nil, Config{})
}

// containsTestString reports whether a test slice contains a value.
func containsTestString(values []string, value string) bool {
	for _, candidate := range values {
		if candidate == value {
			return true
		}
	}
	return false
}

// summaryHasLane reports whether a projection includes one attention lane.
func summaryHasLane(summary domain.ExecutiveSummaryProjection, lane string) bool {
	for _, item := range summary.Attention.Items {
		if item.Lane == lane {
			return true
		}
	}
	return false
}

// delegationBucket returns one delegation bucket count by id.
func delegationBucket(summary domain.ExecutiveSummaryProjection, id string) int {
	for _, bucket := range summary.Delegation.Buckets {
		if bucket.ID == id {
			return bucket.Count
		}
	}
	return 0
}

// timePtr returns a pointer to one test timestamp.
func timePtr(value time.Time) *time.Time {
	return &value
}
