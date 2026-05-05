package repository

import (
	"context"
	"path/filepath"
	"reflect"
	"sort"
	"testing"
	"time"

	"agent-awesome.com/memoryinternal/agent-awesome.com/memorydomain"
)

// TestCaptureProjectsGraphMemory verifies capture writes graph-backed graph-backed memory records.
func TestCaptureProjectsGraphMemory(t *testing.T) {
	ctx := context.Background()
	repo := openTestRepository(t)
	defer repo.Close()

	result, err := repo.Capture(ctx, domain.CaptureRequest{
		Content:     "  remember the normalized source  ",
		Subjects:    []string{" Project ", "project", ""},
		Topics:      []string{" Reporting ", "reporting"},
		EntityNames: []string{" OAuth ", "oauth"},
	})
	if err != nil {
		t.Fatalf("capture: %v", err)
	}
	record, err := repo.GetMemory(ctx, result.MemoryID)
	if err != nil {
		t.Fatalf("get memory: %v", err)
	}
	if record.Kind != domain.KindDocument || record.Scope != domain.ScopeUser {
		t.Fatalf("defaults kind/scope = %q/%q", record.Kind, record.Scope)
	}
	if record.TrustLevel != domain.TrustSourceOriginal || record.Sensitivity != domain.SensitivityPrivate {
		t.Fatalf("defaults trust/sensitivity = %q/%q", record.TrustLevel, record.Sensitivity)
	}
	if !reflect.DeepEqual(record.Subjects, []string{"project"}) {
		t.Fatalf("subjects = %#v, want project", record.Subjects)
	}
	if !reflect.DeepEqual(record.Topics, []string{"reporting"}) {
		t.Fatalf("topics = %#v, want reporting", record.Topics)
	}
	if !reflect.DeepEqual(record.EntityNames, []string{"oauth"}) {
		t.Fatalf("entity names = %#v, want oauth", record.EntityNames)
	}
	content, err := repo.GetEvidenceContent(ctx, result.EvidenceID)
	if err != nil {
		t.Fatalf("get evidence content: %v", err)
	}
	if content != "remember the normalized source" {
		t.Fatalf("content = %q, want trimmed source", content)
	}
	metrics, err := repo.Metrics(ctx)
	if err != nil {
		t.Fatalf("metrics: %v", err)
	}
	if metrics.EvidenceCount != 1 || metrics.MemoryCount != 1 || metrics.PendingJobs != 0 || metrics.RecordsWithSources != 1 {
		t.Fatalf("metrics = %#v, want memory records without jobs", metrics)
	}
}

// TestCaptureIdempotencyReusesGraphNodes verifies duplicate keys do not rewrite.
func TestCaptureIdempotencyReusesGraphNodes(t *testing.T) {
	ctx := context.Background()
	repo := openTestRepository(t)
	defer repo.Close()

	first, err := repo.Capture(ctx, domain.CaptureRequest{Content: "same source", Scope: domain.ScopeUser, IdempotencyKey: " same-key "})
	if err != nil {
		t.Fatalf("first capture: %v", err)
	}
	second, err := repo.Capture(ctx, domain.CaptureRequest{Content: "changed source", Scope: domain.ScopeUser, IdempotencyKey: "same-key"})
	if err != nil {
		t.Fatalf("second capture: %v", err)
	}
	if !second.Duplicate || first.MemoryID != second.MemoryID || first.EvidenceID != second.EvidenceID {
		t.Fatalf("idempotency changed result: first=%#v second=%#v", first, second)
	}
	content, err := repo.GetEvidenceContent(ctx, first.EvidenceID)
	if err != nil {
		t.Fatalf("get evidence content: %v", err)
	}
	if content != "same source" {
		t.Fatalf("evidence content = %q, want first source", content)
	}
}

// TestSearchFiltersGraphMemory verifies retrieval filters compose over graph facts.
func TestSearchFiltersGraphMemory(t *testing.T) {
	ctx := context.Background()
	repo := openTestRepository(t)
	defer repo.Close()

	eventOne := time.Date(2026, 1, 10, 9, 0, 0, 0, time.UTC)
	eventTwo := time.Date(2026, 1, 11, 9, 0, 0, 0, time.UTC)
	eventThree := time.Date(2026, 1, 12, 9, 0, 0, 0, time.UTC)
	userDoc := captureForSearch(t, repo, domain.CaptureRequest{
		Content:     "planning alpha user source",
		Title:       "User planning",
		Kind:        domain.KindDocument,
		Scope:       domain.ScopeUser,
		Topics:      []string{"Planning"},
		EntityNames: []string{"Acme"},
		EventTime:   &eventOne,
	})
	globalTool := captureForSearch(t, repo, domain.CaptureRequest{
		Content:     "planning alpha global source",
		Title:       "Global planning",
		Kind:        domain.KindToolOutput,
		Scope:       domain.ScopeGlobal,
		Topics:      []string{"planning"},
		EntityNames: []string{"ACME"},
		EventTime:   &eventTwo,
	})
	_ = captureForSearch(t, repo, domain.CaptureRequest{
		Content:     "planning alpha artifact source",
		Title:       "Artifact planning",
		Kind:        domain.KindArtifact,
		Scope:       domain.ScopeUser,
		Topics:      []string{"planning"},
		EntityNames: []string{"acme"},
		EventTime:   &eventThree,
	})
	_ = captureForSearch(t, repo, domain.CaptureRequest{
		Content:     "planning alpha project-only source",
		Title:       "Project planning",
		Kind:        domain.KindDocument,
		Scope:       domain.ScopeProject,
		Topics:      []string{"planning"},
		EntityNames: []string{"acme"},
		EventTime:   &eventOne,
	})

	from := eventOne.Add(-time.Hour)
	to := eventTwo.Add(time.Hour)
	records, err := repo.Search(ctx, domain.RetrievalQuery{
		Scope:     domain.ScopeUser,
		Text:      "planning",
		Kinds:     []domain.Kind{domain.KindDocument, domain.KindToolOutput},
		Topics:    []string{" Planning "},
		EntityIDs: []domain.EntityID{userDoc.EntityIDs[0]},
		TimeFrom:  &from,
		TimeTo:    &to,
		Limit:     10,
	})
	if err != nil {
		t.Fatalf("search: %v", err)
	}
	gotIDs := memoryIDs(records)
	wantIDs := []domain.MemoryID{userDoc.ID, globalTool.ID}
	sort.Slice(wantIDs, func(i, j int) bool { return wantIDs[i] < wantIDs[j] })
	if !reflect.DeepEqual(gotIDs, wantIDs) {
		t.Fatalf("memory ids = %#v, want %#v", gotIDs, wantIDs)
	}

	records, err = repo.Search(ctx, domain.RetrievalQuery{Scope: domain.ScopeUser, Text: "project-only", Limit: 10})
	if err != nil {
		t.Fatalf("project search: %v", err)
	}
	if len(records) != 0 {
		t.Fatalf("user search returned project-scoped records: %#v", records)
	}
}

// TestRestrictedGraphMemoryRequiresExplicitSensitivity verifies access trimming.
func TestRestrictedGraphMemoryRequiresExplicitSensitivity(t *testing.T) {
	ctx := context.Background()
	repo := openTestRepository(t)
	defer repo.Close()

	_, err := repo.Capture(ctx, domain.CaptureRequest{
		Content:     "restricted payroll source",
		Title:       "Payroll",
		Scope:       domain.ScopeUser,
		Sensitivity: domain.SensitivityRestricted,
	})
	if err != nil {
		t.Fatalf("capture: %v", err)
	}
	records, err := repo.Search(ctx, domain.RetrievalQuery{Scope: domain.ScopeUser, Text: "payroll"})
	if err != nil {
		t.Fatalf("default search: %v", err)
	}
	if len(records) != 0 {
		t.Fatalf("default search returned restricted records: %d", len(records))
	}
	records, err = repo.Search(ctx, domain.RetrievalQuery{
		Scope:                domain.ScopeUser,
		Text:                 "payroll",
		AllowedSensitivities: []domain.Sensitivity{domain.SensitivityRestricted},
	})
	if err != nil {
		t.Fatalf("restricted search: %v", err)
	}
	if len(records) != 1 {
		t.Fatalf("restricted search returned %d records, want 1", len(records))
	}
}

// TestRepairGraphMemoryUpdatesMetadata verifies repair edits graph facts.
func TestRepairGraphMemoryUpdatesMetadata(t *testing.T) {
	ctx := context.Background()
	repo := openTestRepository(t)
	defer repo.Close()

	result, err := repo.Capture(ctx, domain.CaptureRequest{
		Content:     "original launch evidence",
		Title:       "Old title",
		Scope:       domain.ScopeUser,
		Topics:      []string{"old"},
		EntityNames: []string{"old entity"},
	})
	if err != nil {
		t.Fatalf("capture: %v", err)
	}
	kind := domain.KindSummary
	sensitivity := domain.SensitivityInternal
	title := "New launch record"
	summary := "corrected searchable summary"
	record, err := repo.RepairMemory(ctx, domain.RepairRequest{
		Actor:       "test",
		MemoryID:    result.MemoryID,
		Kind:        &kind,
		Sensitivity: &sensitivity,
		Title:       &title,
		Summary:     &summary,
		Topics:      []string{" Updated "},
		EntityNames: []string{"New Entity"},
	})
	if err != nil {
		t.Fatalf("repair memory: %v", err)
	}
	if record.Kind != kind || record.Sensitivity != sensitivity || record.Title != title || record.Summary != summary {
		t.Fatalf("record metadata after repair = %#v", record)
	}
	if !reflect.DeepEqual(record.Topics, []string{"updated"}) || !reflect.DeepEqual(record.EntityNames, []string{"new entity"}) {
		t.Fatalf("record facets after repair = topics %#v entities %#v", record.Topics, record.EntityNames)
	}
	records, err := repo.Search(ctx, domain.RetrievalQuery{Scope: domain.ScopeUser, Text: "searchable", Topics: []string{"updated"}, Limit: 10})
	if err != nil {
		t.Fatalf("search repaired record: %v", err)
	}
	if len(records) != 1 || records[0].ID != result.MemoryID {
		t.Fatalf("repaired search records = %#v, want memory %s", records, result.MemoryID)
	}
	records, err = repo.Search(ctx, domain.RetrievalQuery{Scope: domain.ScopeUser, Topics: []string{"old"}, Limit: 10})
	if err != nil {
		t.Fatalf("search old topic: %v", err)
	}
	if len(records) != 0 {
		t.Fatalf("old topic search returned repaired record: %#v", records)
	}
}

// TestCorrectionGraphMemoryStoresRelationship verifies corrections remain linked.
func TestCorrectionGraphMemoryStoresRelationship(t *testing.T) {
	ctx := context.Background()
	repo := openTestRepository(t)
	defer repo.Close()

	base, err := repo.Capture(ctx, domain.CaptureRequest{Content: "base memory that needs correction", Title: "Base", Scope: domain.ScopeUser})
	if err != nil {
		t.Fatalf("capture base: %v", err)
	}
	correction, err := repo.CreateCorrection(ctx, domain.CorrectionRequest{Actor: "user", MemoryID: base.MemoryID, Scope: domain.ScopeUser, Text: "corrected fact"})
	if err != nil {
		t.Fatalf("create correction: %v", err)
	}
	record, err := repo.GetMemory(ctx, correction.MemoryID)
	if err != nil {
		t.Fatalf("get correction: %v", err)
	}
	if record.TrustLevel != domain.TrustUserAsserted || record.Source.System != "memory_correction" || record.Source.ID != string(base.MemoryID) {
		t.Fatalf("correction source metadata = %#v", record)
	}
	if len(record.Relationships) != 1 || record.Relationships[0].Type != domain.RelationshipRefersTo || record.Relationships[0].ToID != string(base.MemoryID) {
		t.Fatalf("correction relationships = %#v", record.Relationships)
	}
}

// TestCreateTaskWritesGraphFacts verifies task creation uses graph nodes and edges.
func TestCreateTaskWritesGraphFacts(t *testing.T) {
	ctx := context.Background()
	repo := openTestRepository(t)
	defer repo.Close()

	due := time.Date(2026, 5, 5, 14, 0, 0, 0, time.UTC)
	task, err := repo.CreateTask(ctx, domain.CreateTaskRequest{
		Actor:           "user",
		Title:           "Prepare model readout",
		Description:     "Summarize forecast model output.",
		Priority:        domain.TaskPriorityHigh,
		DueAt:           &due,
		Topics:          []string{"Forecasting", "forecasting"},
		EstimateMinutes: 90,
		Project:         "Forecasting",
		Person:          "Doug",
		Source:          "test",
		WorkBreakdown: domain.TaskWorkBreakdown{
			Code:               "1.1",
			Deliverable:        "Forecast readout",
			StartCriteria:      []string{"Model output is ready"},
			AcceptanceCriteria: []string{"Summary reviewed"},
			Resources: []domain.TaskResourceRequirement{
				{Name: "Reviewer", Type: "person", Quantity: 1, Unit: "person"},
			},
			SpendCents:    2500,
			SpendCurrency: "USD",
		},
		IdempotencyKey: "task-readout",
	})
	if err != nil {
		t.Fatalf("create task: %v", err)
	}
	if task.ID == "" || task.Title != "Prepare model readout" || task.Status != domain.TaskStatusOpen || task.Priority != domain.TaskPriorityHigh {
		t.Fatalf("task = %#v, want graph-backed task", task)
	}
	if task.EstimateMinutes != 90 || task.Project != "Forecasting" || task.Person != "Doug" || !reflect.DeepEqual(task.Topics, []string{"forecasting"}) {
		t.Fatalf("task metadata = %#v", task)
	}
	if task.WorkBreakdown.Code != "1.1" || task.WorkBreakdown.Resources[0].Name != "Reviewer" {
		t.Fatalf("task WBS = %#v, want persisted work-breakdown metadata", task.WorkBreakdown)
	}
	again, err := repo.CreateTask(ctx, domain.CreateTaskRequest{
		Actor:          "user",
		Title:          "Changed title",
		IdempotencyKey: "task-readout",
	})
	if err != nil {
		t.Fatalf("repeat create task: %v", err)
	}
	if again.ID != task.ID || again.Title != task.Title {
		t.Fatalf("idempotent task = %#v, want original %#v", again, task)
	}
}

// TestListTasksFiltersGraphFacts verifies task list filters use graph facts.
func TestListTasksFiltersGraphFacts(t *testing.T) {
	ctx := context.Background()
	repo := openTestRepository(t)
	defer repo.Close()

	if _, err := repo.CreateTask(ctx, domain.CreateTaskRequest{Title: "Open forecast task", Topics: []string{"forecast"}, Priority: domain.TaskPriorityHigh}); err != nil {
		t.Fatalf("create open task: %v", err)
	}
	if _, err := repo.CreateTask(ctx, domain.CreateTaskRequest{Title: "Done forecast task", Topics: []string{"forecast"}, Status: domain.TaskStatusDone}); err != nil {
		t.Fatalf("create done task: %v", err)
	}
	tasks, err := repo.ListTasks(ctx, domain.TaskQuery{Topics: []string{"forecast"}, Priorities: []domain.TaskPriority{domain.TaskPriorityHigh}, IncludeDone: false})
	if err != nil {
		t.Fatalf("list tasks: %v", err)
	}
	if len(tasks) != 1 || tasks[0].Title != "Open forecast task" {
		t.Fatalf("tasks = %#v, want only high-priority open task", tasks)
	}
	all, err := repo.ListTasks(ctx, domain.TaskQuery{Topics: []string{"forecast"}, IncludeDone: true})
	if err != nil {
		t.Fatalf("list all tasks: %v", err)
	}
	if len(all) != 2 {
		t.Fatalf("all tasks = %#v, want open and done", all)
	}
}

// TestLinkTaskMemoryCreatesGraphEdge verifies tasks can link to memory.
func TestLinkTaskMemoryCreatesGraphEdge(t *testing.T) {
	ctx := context.Background()
	repo := openTestRepository(t)
	defer repo.Close()

	memory, err := repo.Capture(ctx, domain.CaptureRequest{Content: "Use the BI export notes.", Title: "BI export notes", Scope: domain.ScopeUser})
	if err != nil {
		t.Fatalf("capture memory: %v", err)
	}
	task, err := repo.CreateTask(ctx, domain.CreateTaskRequest{Title: "Prepare BI readout"})
	if err != nil {
		t.Fatalf("create task: %v", err)
	}
	link, err := repo.LinkTaskMemory(ctx, domain.LinkTaskMemoryRequest{
		TaskID: task.ID,
		Link: domain.MemoryLinkRequest{
			MemoryID:         string(memory.MemoryID),
			MemoryEvidenceID: string(memory.EvidenceID),
			Relationship:     domain.TaskMemoryOriginatedFrom,
			Note:             "User asked to remember BI context.",
		},
	})
	if err != nil {
		t.Fatalf("link task memory: %v", err)
	}
	if link.ID == "" || link.Relationship != domain.TaskMemoryOriginatedFrom || link.MemoryID != string(memory.MemoryID) || link.MemoryEvidenceID != string(memory.EvidenceID) {
		t.Fatalf("link = %#v, want graph-backed memory link", link)
	}
	hydrated, err := repo.GetTask(ctx, domain.TaskIDRequest{TaskID: task.ID})
	if err != nil {
		t.Fatalf("get task: %v", err)
	}
	if len(hydrated.MemoryLinks) != 1 || hydrated.MemoryLinks[0].Note != "User asked to remember BI context." {
		t.Fatalf("task links = %#v, want note-bearing graph edge", hydrated.MemoryLinks)
	}
}

// TestUpdateTaskPatchesGraphFacts verifies task updates replace scalar and facet facts.
func TestUpdateTaskPatchesGraphFacts(t *testing.T) {
	ctx := context.Background()
	repo := openTestRepository(t)
	defer repo.Close()

	memory, err := repo.Capture(ctx, domain.CaptureRequest{Content: "Original task request.", Title: "Task request", Scope: domain.ScopeUser})
	if err != nil {
		t.Fatalf("capture memory: %v", err)
	}
	task, err := repo.CreateTask(ctx, domain.CreateTaskRequest{
		Title:   "Draft readout",
		Topics:  []string{"draft"},
		Project: "Old project",
		Source:  "manual",
	})
	if err != nil {
		t.Fatalf("create task: %v", err)
	}
	if _, err := repo.LinkTaskMemory(ctx, domain.LinkTaskMemoryRequest{
		TaskID: task.ID,
		Link: domain.MemoryLinkRequest{
			MemoryID:     string(memory.MemoryID),
			Relationship: domain.TaskMemoryOriginatedFrom,
		},
	}); err != nil {
		t.Fatalf("link task memory: %v", err)
	}

	title := "Finalize readout"
	description := "Updated execution notes."
	project := "Forecasting"
	source := "planner"
	estimate := 0
	priority := domain.TaskPriorityUrgent
	updated, err := repo.UpdateTask(ctx, domain.UpdateTaskRequest{
		TaskID:          task.ID,
		Title:           &title,
		Description:     &description,
		Priority:        &priority,
		Topics:          []string{"forecast"},
		Project:         &project,
		Source:          &source,
		EstimateMinutes: &estimate,
	})
	if err != nil {
		t.Fatalf("update task: %v", err)
	}
	if updated.Title != title || updated.Description != description || updated.Priority != priority || updated.Project != project || updated.Source != source {
		t.Fatalf("updated task = %#v", updated)
	}
	if updated.EstimateMinutes != 0 || !reflect.DeepEqual(updated.Topics, []string{"forecast"}) {
		t.Fatalf("updated numeric/topics = %#v", updated)
	}
	if len(updated.MemoryLinks) != 1 || updated.MemoryLinks[0].MemoryID != string(memory.MemoryID) {
		t.Fatalf("memory links after source replacement = %#v, want memory link preserved", updated.MemoryLinks)
	}
}

// TestTaskLifecycleMutations verifies terminal status helpers and deletion.
func TestTaskLifecycleMutations(t *testing.T) {
	ctx := context.Background()
	repo := openTestRepository(t)
	defer repo.Close()

	task, err := repo.CreateTask(ctx, domain.CreateTaskRequest{Title: "Ship graph task lifecycle"})
	if err != nil {
		t.Fatalf("create task: %v", err)
	}
	done, err := repo.CompleteTask(ctx, domain.TaskIDRequest{TaskID: task.ID})
	if err != nil {
		t.Fatalf("complete task: %v", err)
	}
	if done.Status != domain.TaskStatusDone || done.CompletedAt == nil || done.CanceledAt != nil {
		t.Fatalf("completed task = %#v", done)
	}
	canceled, err := repo.CancelTask(ctx, domain.TaskIDRequest{TaskID: task.ID})
	if err != nil {
		t.Fatalf("cancel task: %v", err)
	}
	if canceled.Status != domain.TaskStatusCanceled || canceled.CanceledAt == nil || canceled.CompletedAt != nil {
		t.Fatalf("canceled task = %#v", canceled)
	}
	if err := repo.DeleteTask(ctx, domain.TaskIDRequest{TaskID: task.ID}); err != nil {
		t.Fatalf("delete task: %v", err)
	}
	if _, err := repo.GetTask(ctx, domain.TaskIDRequest{TaskID: task.ID}); err == nil {
		t.Fatalf("get deleted task returned nil error")
	}
	tasks, err := repo.ListTasks(ctx, domain.TaskQuery{IncludeDone: true})
	if err != nil {
		t.Fatalf("list tasks after delete: %v", err)
	}
	if len(tasks) != 0 {
		t.Fatalf("tasks after delete = %#v, want none", tasks)
	}
}

// TestTaskRelationsUseDirectedGraphEdges verifies relation direction and lifecycle.
func TestTaskRelationsUseDirectedGraphEdges(t *testing.T) {
	ctx := context.Background()
	repo := openTestRepository(t)
	defer repo.Close()

	readout, err := repo.CreateTask(ctx, domain.CreateTaskRequest{Title: "Prepare readout"})
	if err != nil {
		t.Fatalf("create readout: %v", err)
	}
	clean, err := repo.CreateTask(ctx, domain.CreateTaskRequest{Title: "Clean inputs"})
	if err != nil {
		t.Fatalf("create clean: %v", err)
	}
	bi, err := repo.CreateTask(ctx, domain.CreateTaskRequest{Title: "Wait for BI"})
	if err != nil {
		t.Fatalf("create bi: %v", err)
	}
	depends, err := repo.UpsertTaskRelation(ctx, domain.UpsertTaskRelationRequest{
		FromTaskID: readout.ID,
		Type:       domain.TaskRelationDependsOn,
		ToTaskID:   clean.ID,
		Note:       "Readout needs clean data.",
		LagMinutes: 30,
	})
	if err != nil {
		t.Fatalf("upsert depends relation: %v", err)
	}
	if _, err := repo.UpsertTaskRelation(ctx, domain.UpsertTaskRelationRequest{
		FromTaskID: bi.ID,
		Type:       domain.TaskRelationBlocks,
		ToTaskID:   readout.ID,
	}); err != nil {
		t.Fatalf("upsert blocks relation: %v", err)
	}
	outgoing, err := repo.ListTaskRelations(ctx, domain.TaskRelationQuery{TaskID: readout.ID, Types: []domain.TaskRelationType{domain.TaskRelationDependsOn}})
	if err != nil {
		t.Fatalf("list outgoing relations: %v", err)
	}
	if len(outgoing) != 1 || outgoing[0].ToTaskID != clean.ID || outgoing[0].Note != "Readout needs clean data." || outgoing[0].LagMinutes != 30 {
		t.Fatalf("outgoing relations = %#v", outgoing)
	}
	incoming, err := repo.ListTaskRelations(ctx, domain.TaskRelationQuery{TaskID: readout.ID, Direction: "incoming"})
	if err != nil {
		t.Fatalf("list incoming relations: %v", err)
	}
	if len(incoming) != 1 || incoming[0].FromTaskID != bi.ID || incoming[0].Type != domain.TaskRelationBlocks {
		t.Fatalf("incoming relations = %#v", incoming)
	}
	all, err := repo.ListTaskRelations(ctx, domain.TaskRelationQuery{})
	if err != nil {
		t.Fatalf("list all relations: %v", err)
	}
	if len(all) != 2 {
		t.Fatalf("all relations = %#v, want two task relations", all)
	}
	if err := repo.DeleteTaskRelation(ctx, domain.DeleteTaskRelationRequest{RelationID: depends.ID}); err != nil {
		t.Fatalf("delete relation: %v", err)
	}
	afterDelete, err := repo.ListTaskRelations(ctx, domain.TaskRelationQuery{TaskID: readout.ID, Direction: "outgoing"})
	if err != nil {
		t.Fatalf("list outgoing after delete: %v", err)
	}
	if len(afterDelete) != 0 {
		t.Fatalf("outgoing after delete = %#v, want none", afterDelete)
	}
}

// TestTraverseTaskRelationsReturnsBoundedPaths verifies graph relation path projection.
func TestTraverseTaskRelationsReturnsBoundedPaths(t *testing.T) {
	ctx := context.Background()
	repo := openTestRepository(t)
	defer repo.Close()

	root, err := repo.CreateTask(ctx, domain.CreateTaskRequest{Title: "Render graph query results"})
	if err != nil {
		t.Fatalf("create root: %v", err)
	}
	middle, err := repo.CreateTask(ctx, domain.CreateTaskRequest{Title: "Implement path executor"})
	if err != nil {
		t.Fatalf("create middle: %v", err)
	}
	leaf, err := repo.CreateTask(ctx, domain.CreateTaskRequest{Title: "Finalize graph vocabulary"})
	if err != nil {
		t.Fatalf("create leaf: %v", err)
	}
	if _, err := repo.UpsertTaskRelation(ctx, domain.UpsertTaskRelationRequest{FromTaskID: root.ID, Type: domain.TaskRelationDependsOn, ToTaskID: middle.ID}); err != nil {
		t.Fatalf("upsert root relation: %v", err)
	}
	if _, err := repo.UpsertTaskRelation(ctx, domain.UpsertTaskRelationRequest{FromTaskID: middle.ID, Type: domain.TaskRelationDependsOn, ToTaskID: leaf.ID}); err != nil {
		t.Fatalf("upsert middle relation: %v", err)
	}
	traversal, err := repo.TraverseTaskRelations(ctx, domain.TaskRelationTraversalQuery{
		RootTaskID:   root.ID,
		Types:        []domain.TaskRelationType{domain.TaskRelationDependsOn},
		MaxDepth:     4,
		IncludeTasks: true,
	})
	if err != nil {
		t.Fatalf("traverse task relations: %v", err)
	}
	if traversal.Direction != "outgoing" || traversal.MaxDepth != 4 || len(traversal.Paths) != 1 {
		t.Fatalf("traversal = %#v, want one outgoing path", traversal)
	}
	path := traversal.Paths[0]
	if path.Depth != 2 || path.TaskIDs[0] != root.ID || path.TaskIDs[1] != middle.ID || path.TaskIDs[2] != leaf.ID {
		t.Fatalf("path = %#v, want root -> middle -> leaf", path)
	}
	if len(path.Tasks) != 3 || path.Tasks[2].Title != "Finalize graph vocabulary" {
		t.Fatalf("hydrated tasks = %#v, want task DTOs on path", path.Tasks)
	}
	downstream, err := repo.TraverseTaskRelations(ctx, domain.TaskRelationTraversalQuery{
		RootTaskID: leaf.ID,
		Types:      []domain.TaskRelationType{domain.TaskRelationDependsOn},
		Direction:  "incoming",
		MaxDepth:   4,
	})
	if err != nil {
		t.Fatalf("traverse incoming task relations: %v", err)
	}
	if len(downstream.Paths) != 1 || downstream.Paths[0].TaskIDs[2] != root.ID {
		t.Fatalf("incoming traversal = %#v, want leaf -> middle -> root", downstream)
	}
}

// TestTaskGraphProjectionReturnsNodesEdgesAndFacets verifies UI-facing graph snapshots.
func TestTaskGraphProjectionReturnsNodesEdgesAndFacets(t *testing.T) {
	ctx := context.Background()
	repo := openTestRepository(t)
	defer repo.Close()

	readout, err := repo.CreateTask(ctx, domain.CreateTaskRequest{
		Title:   "Prepare graph readout",
		Project: "Context Graph",
		Person:  "Doug",
		Topics:  []string{"graph", "query"},
		Risk:    0.4,
		Value:   0.9,
	})
	if err != nil {
		t.Fatalf("create readout: %v", err)
	}
	inputs, err := repo.CreateTask(ctx, domain.CreateTaskRequest{
		Title:   "Clean graph inputs",
		Project: "Context Graph",
		Person:  "Mina",
		Topics:  []string{"graph"},
	})
	if err != nil {
		t.Fatalf("create inputs: %v", err)
	}
	if _, err := repo.UpsertTaskRelation(ctx, domain.UpsertTaskRelationRequest{
		FromTaskID: readout.ID,
		Type:       domain.TaskRelationDependsOn,
		ToTaskID:   inputs.ID,
		Note:       "Readout requires cleaned graph inputs.",
	}); err != nil {
		t.Fatalf("upsert relation: %v", err)
	}
	projection, err := repo.TaskGraphProjection(ctx, domain.TaskGraphProjectionQuery{
		Tasks:         domain.TaskQuery{IncludeDone: true},
		IncludeFacets: true,
	})
	if err != nil {
		t.Fatalf("task graph projection: %v", err)
	}
	if projection.SchemaVersion == "" || projection.Quality.TaskCount != 2 || projection.Quality.RelationCount != 1 {
		t.Fatalf("projection quality = %#v version=%q", projection.Quality, projection.SchemaVersion)
	}
	if len(projection.Nodes) != 2 || len(projection.Relations) != 1 {
		t.Fatalf("projection nodes/relations = %d/%d, want 2/1", len(projection.Nodes), len(projection.Relations))
	}
	if !projectionHasEdge(projection, string(readout.ID), string(inputs.ID), "depends_on") {
		t.Fatalf("projection edges = %#v, want depends_on relation edge", projection.Edges)
	}
	if !projectionHasFacet(projection, "project", "Context Graph") || !projectionHasFacet(projection, "person", "Doug") || !projectionHasFacet(projection, "topic", "query") {
		t.Fatalf("projection facets = %#v, want project/person/topic facets", projection.Facets)
	}
	if projection.Quality.RelationCoverage != 1 {
		t.Fatalf("relation coverage = %g, want 1", projection.Quality.RelationCoverage)
	}
}

// openTestRepository creates an isolated graph-backed repository.
func openTestRepository(t *testing.T) *Repository {
	t.Helper()
	root := t.TempDir()
	repo, err := Open(context.Background(), Config{
		DBPath:   filepath.Join(root, "graph.db"),
		DataRoot: filepath.Join(root, "data"),
	})
	if err != nil {
		t.Fatalf("open graph repository: %v", err)
	}
	return repo
}

// projectionHasEdge reports whether a projection contains one edge.
func projectionHasEdge(projection domain.TaskGraphProjection, from string, to string, edgeType string) bool {
	for _, edge := range projection.Edges {
		if edge.FromNodeID == from && edge.ToNodeID == to && edge.Type == edgeType {
			return true
		}
	}
	return false
}

// projectionHasFacet reports whether a projection contains one facet.
func projectionHasFacet(projection domain.TaskGraphProjection, kind string, label string) bool {
	for _, facet := range projection.Facets {
		if facet.Kind == kind && facet.Label == label {
			return true
		}
	}
	return false
}

// captureForSearch stores a request and returns the hydrated memory record.
func captureForSearch(t *testing.T, repo *Repository, req domain.CaptureRequest) domain.MemoryRecord {
	t.Helper()
	result, err := repo.Capture(context.Background(), req)
	if err != nil {
		t.Fatalf("capture %q: %v", req.Title, err)
	}
	record, err := repo.GetMemory(context.Background(), result.MemoryID)
	if err != nil {
		t.Fatalf("get memory %s: %v", result.MemoryID, err)
	}
	return record
}

// memoryIDs returns sorted memory IDs for order-independent assertions.
func memoryIDs(records []domain.MemoryRecord) []domain.MemoryID {
	ids := make([]domain.MemoryID, 0, len(records))
	for _, record := range records {
		ids = append(ids, record.ID)
	}
	sort.Slice(ids, func(i, j int) bool { return ids[i] < ids[j] })
	return ids
}
