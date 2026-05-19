package query

import (
	"context"
	"fmt"
	"path/filepath"
	"testing"
	"time"

	graph "memory/internal/memory/graph/domain"
	graphstore "memory/internal/memory/graph/store"
)

// TestExecuteFindTaskFiltersNonEnglishProperty verifies FIND reads graph facts and values.
func TestExecuteFindTaskFiltersNonEnglishProperty(t *testing.T) {
	ctx := context.Background()
	store := openTestStore(t)
	defer store.Close()

	task := mustNode(t, store, graph.KindTask, "task:cafe", "Préparer le café")
	if _, err := store.UpsertNodeProperty(ctx, graph.UpsertNodePropertyRequest{
		NodeID: task.ID,
		Key:    "project",
		Value:  graph.Value{Type: graph.ValueText, Text: "Équipe Montréal"},
		Actor:  "test",
	}); err != nil {
		t.Fatalf("upsert project property: %v", err)
	}
	if _, err := store.UpsertNodeProperty(ctx, graph.UpsertNodePropertyRequest{
		NodeID: task.ID,
		Key:    "status",
		Value:  graph.Value{Type: graph.ValueText, Text: "open"},
		Actor:  "test",
	}); err != nil {
		t.Fatalf("upsert status property: %v", err)
	}

	result, err := NewExecutor(store).Execute(ctx, Request{
		Query: `FIND task WHERE project = "Équipe Montréal" RETURN id, title, project, status ORDER BY title ASC LIMIT 5`,
	})
	if err != nil {
		t.Fatalf("execute query: %v", err)
	}
	if len(result.Rows) != 1 {
		t.Fatalf("rows = %#v, want one row", result.Rows)
	}
	if result.Rows[0]["title"] != "Préparer le café" || result.Rows[0]["project"] != "Équipe Montréal" || result.Rows[0]["status"] != "open" {
		t.Fatalf("row = %#v, want non-English property row", result.Rows[0])
	}
}

// TestExecuteFindComparisonPredicates verifies WHERE supports inequality, numbers, and time literals.
func TestExecuteFindComparisonPredicates(t *testing.T) {
	ctx := context.Background()
	store := openTestStore(t)
	defer store.Close()

	urgent := mustNode(t, store, graph.KindTask, "task:urgent-risk", "Urgent risk task")
	lowRisk := mustNode(t, store, graph.KindTask, "task:low-risk", "Low risk task")
	done := mustNode(t, store, graph.KindTask, "task:done-risk", "Done risk task")
	upsertTextProperty(t, store, urgent.ID, "status", "open")
	upsertNumberProperty(t, store, urgent.ID, "risk_score", 7.5)
	upsertTimeProperty(t, store, urgent.ID, "due_at", time.Date(2026, 5, 2, 9, 0, 0, 0, time.UTC))
	upsertTextProperty(t, store, lowRisk.ID, "status", "open")
	upsertNumberProperty(t, store, lowRisk.ID, "risk_score", 4)
	upsertTimeProperty(t, store, lowRisk.ID, "due_at", time.Date(2026, 5, 2, 9, 0, 0, 0, time.UTC))
	upsertTextProperty(t, store, done.ID, "status", "done")
	upsertNumberProperty(t, store, done.ID, "risk_score", 8)
	upsertTimeProperty(t, store, done.ID, "due_at", time.Date(2026, 5, 1, 9, 0, 0, 0, time.UTC))

	result, err := NewExecutor(store).Execute(ctx, Request{
		Query: `FIND task WHERE status != "done" AND risk_score >= 6.5 AND due_at < "2026-05-03T00:00:00Z" RETURN title, status, risk_score, due_at LIMIT 10`,
	})
	if err != nil {
		t.Fatalf("execute comparison query: %v", err)
	}
	if len(result.Rows) != 1 {
		t.Fatalf("rows = %#v, want one urgent task", result.Rows)
	}
	row := result.Rows[0]
	if row["title"] != "Urgent risk task" || row["status"] != "open" || row["risk_score"] != 7.5 {
		t.Fatalf("row = %#v, want urgent open risk task", row)
	}
	if dueAt, ok := row["due_at"].(time.Time); !ok || !dueAt.Equal(time.Date(2026, 5, 2, 9, 0, 0, 0, time.UTC)) {
		t.Fatalf("due_at = %#v, want typed due time", row["due_at"])
	}
}

// TestExecuteMatchTaskDependencyReturnsEdgeRows verifies MATCH traverses one edge.
func TestExecuteMatchTaskDependencyReturnsEdgeRows(t *testing.T) {
	ctx := context.Background()
	store := openTestStore(t)
	defer store.Close()

	readout := mustNode(t, store, graph.KindTask, "task:readout", "Prepare readout")
	clean := mustNode(t, store, graph.KindTask, "task:clean", "Clean inputs")
	other := mustNode(t, store, graph.KindTask, "task:other", "Other task")
	if _, err := store.UpsertNodeProperty(ctx, graph.UpsertNodePropertyRequest{
		NodeID: readout.ID,
		Key:    "status",
		Value:  graph.Value{Type: graph.ValueText, Text: "open"},
		Actor:  "test",
	}); err != nil {
		t.Fatalf("upsert readout status: %v", err)
	}
	if _, err := store.UpsertEdge(ctx, graph.UpsertEdgeRequest{
		FromNodeID: readout.ID,
		Type:       graph.RelationDependsOn,
		ToNodeID:   clean.ID,
		Actor:      "test",
	}); err != nil {
		t.Fatalf("upsert dependency edge: %v", err)
	}
	if _, err := store.UpsertEdge(ctx, graph.UpsertEdgeRequest{
		FromNodeID: other.ID,
		Type:       graph.RelationRelatedTo,
		ToNodeID:   clean.ID,
		Actor:      "test",
	}); err != nil {
		t.Fatalf("upsert unrelated edge: %v", err)
	}

	result, err := NewExecutor(store).Execute(ctx, Request{
		Query: `MATCH task -[depends_on]-> task WHERE from.status = "open" RETURN from.title, edge.type, to.title ORDER BY to.title ASC LIMIT 10`,
	})
	if err != nil {
		t.Fatalf("execute match query: %v", err)
	}
	if len(result.Rows) != 1 {
		t.Fatalf("rows = %#v, want one dependency row", result.Rows)
	}
	row := result.Rows[0]
	if row["from.title"] != "Prepare readout" || row["edge.type"] != "depends_on" || row["to.title"] != "Clean inputs" {
		t.Fatalf("row = %#v, want dependency endpoint titles", row)
	}
	if len(result.Paths) != 1 || result.Paths[0].RowIndex != 0 || result.Paths[0].Depth != 1 || len(result.Paths[0].NodeIDs) != 2 || len(result.Paths[0].EdgeIDs) != 1 {
		t.Fatalf("paths = %#v, want one row-linked one-hop path", result.Paths)
	}
}

// TestExecuteVariableMatchReturnsBoundedPaths verifies MATCH supports depth ranges.
func TestExecuteVariableMatchReturnsBoundedPaths(t *testing.T) {
	ctx := context.Background()
	store := openTestStore(t)
	defer store.Close()

	root := mustNode(t, store, graph.KindTask, "task:root", "Render graph query results")
	executor := mustNode(t, store, graph.KindTask, "task:executor", "Implement path executor")
	grammar := mustNode(t, store, graph.KindTask, "task:grammar", "Define query grammar")
	schema := mustNode(t, store, graph.KindTask, "task:schema", "Finalize graph schema")
	upsertEdge(t, store, root.ID, graph.RelationDependsOn, executor.ID)
	upsertEdge(t, store, executor.ID, graph.RelationDependsOn, grammar.ID)
	upsertEdge(t, store, grammar.ID, graph.RelationDependsOn, schema.ID)
	upsertEdge(t, store, schema.ID, graph.RelationDependsOn, root.ID)

	result, err := NewExecutor(store).Execute(ctx, Request{
		Query: `MATCH task -[depends_on*1..3]-> task WHERE from.title = "Render graph query results" RETURN from.title, path.depth, to.title, path.node_ids, path.edge_ids ORDER BY path.depth DESC LIMIT 10`,
	})
	if err != nil {
		t.Fatalf("execute variable match query: %v", err)
	}
	if len(result.Rows) != 3 {
		t.Fatalf("rows = %#v, want three bounded paths from root", result.Rows)
	}
	first := result.Rows[0]
	if first["path.depth"] != 3 || first["to.title"] != "Finalize graph schema" {
		t.Fatalf("first row = %#v, want deepest bounded path to schema", first)
	}
	if len(first["path.node_ids"].([]string)) != 4 || len(first["path.edge_ids"].([]string)) != 3 {
		t.Fatalf("first path ids = %#v/%#v, want node and edge ids", first["path.node_ids"], first["path.edge_ids"])
	}
	if len(result.Paths) != 3 || result.Paths[0].RowIndex != 0 || result.Paths[0].Depth != 3 || len(result.Paths[0].NodeIDs) != 4 || len(result.Paths[0].EdgeIDs) != 3 {
		t.Fatalf("paths = %#v, want row-linked bounded paths", result.Paths)
	}
}

// TestExecuteVariableMatchFiltersPathDepthComparison verifies path fields use numeric predicates.
func TestExecuteVariableMatchFiltersPathDepthComparison(t *testing.T) {
	ctx := context.Background()
	store := openTestStore(t)
	defer store.Close()

	root := mustNode(t, store, graph.KindTask, "task:path-root", "Path root")
	middle := mustNode(t, store, graph.KindTask, "task:path-middle", "Path middle")
	leaf := mustNode(t, store, graph.KindTask, "task:path-leaf", "Path leaf")
	upsertEdge(t, store, root.ID, graph.RelationDependsOn, middle.ID)
	upsertEdge(t, store, middle.ID, graph.RelationDependsOn, leaf.ID)

	result, err := NewExecutor(store).Execute(ctx, Request{
		Query: `MATCH task -[depends_on*1..3]-> task WHERE from.title = "Path root" AND path.depth >= 2 RETURN path.depth, to.title LIMIT 10`,
	})
	if err != nil {
		t.Fatalf("execute path depth query: %v", err)
	}
	if len(result.Rows) != 1 {
		t.Fatalf("rows = %#v, want one path at depth two or deeper", result.Rows)
	}
	if result.Rows[0]["path.depth"] != 2 || result.Rows[0]["to.title"] != "Path leaf" {
		t.Fatalf("row = %#v, want depth two path to leaf", result.Rows[0])
	}
	if len(result.Paths) != 1 || result.Paths[0].Depth != 2 {
		t.Fatalf("paths = %#v, want one depth two path", result.Paths)
	}
}

// TestExecuteFindGroupsByPropertyCount verifies FIND can aggregate filtered graph rows.
func TestExecuteFindGroupsByPropertyCount(t *testing.T) {
	ctx := context.Background()
	store := openTestStore(t)
	defer store.Close()

	first := mustNode(t, store, graph.KindTask, "task:first", "First open task")
	second := mustNode(t, store, graph.KindTask, "task:second", "Second open task")
	done := mustNode(t, store, graph.KindTask, "task:done", "Done task")
	upsertTextProperty(t, store, first.ID, "status", "open")
	upsertTextProperty(t, store, second.ID, "status", "open")
	upsertTextProperty(t, store, done.ID, "status", "done")

	result, err := NewExecutor(store).Execute(ctx, Request{
		Query: `FIND task GROUP BY status ORDER BY count DESC LIMIT 10`,
	})
	if err != nil {
		t.Fatalf("execute grouped find query: %v", err)
	}
	if len(result.Rows) != 2 {
		t.Fatalf("rows = %#v, want two status groups", result.Rows)
	}
	if result.Columns[0] != "status" || result.Columns[1] != "count" {
		t.Fatalf("columns = %#v, want status and count", result.Columns)
	}
	if result.Rows[0]["status"] != "open" || result.Rows[0]["count"] != 2 {
		t.Fatalf("first row = %#v, want open count 2", result.Rows[0])
	}
	if result.Rows[1]["status"] != "done" || result.Rows[1]["count"] != 1 {
		t.Fatalf("second row = %#v, want done count 1", result.Rows[1])
	}
}

// TestExecuteMatchGroupsByEndpointCount verifies MATCH can aggregate by endpoint fields.
func TestExecuteMatchGroupsByEndpointCount(t *testing.T) {
	ctx := context.Background()
	store := openTestStore(t)
	defer store.Close()

	first := mustNode(t, store, graph.KindTask, "task:owned:first", "First owner task")
	second := mustNode(t, store, graph.KindTask, "task:owned:second", "Second owner task")
	third := mustNode(t, store, graph.KindTask, "task:owned:third", "Third owner task")
	doug := mustNode(t, store, graph.KindPerson, "person:doug", "Doug")
	mina := mustNode(t, store, graph.KindPerson, "person:mina", "Mina")
	upsertEdge(t, store, first.ID, graph.RelationAssignedTo, doug.ID)
	upsertEdge(t, store, second.ID, graph.RelationAssignedTo, doug.ID)
	upsertEdge(t, store, third.ID, graph.RelationAssignedTo, mina.ID)

	result, err := NewExecutor(store).Execute(ctx, Request{
		Query: `MATCH task -[assigned_to]-> person GROUP BY to.title RETURN to.title, count ORDER BY count DESC LIMIT 10`,
	})
	if err != nil {
		t.Fatalf("execute grouped match query: %v", err)
	}
	if len(result.Rows) != 2 {
		t.Fatalf("rows = %#v, want two owner groups", result.Rows)
	}
	if result.Rows[0]["to.title"] != "Doug" || result.Rows[0]["count"] != 2 {
		t.Fatalf("first row = %#v, want Doug count 2", result.Rows[0])
	}
	if result.Rows[1]["to.title"] != "Mina" || result.Rows[1]["count"] != 1 {
		t.Fatalf("second row = %#v, want Mina count 1", result.Rows[1])
	}
	if len(result.Paths) != 0 {
		t.Fatalf("paths = %#v, want grouped aggregate query to omit paths", result.Paths)
	}
}

// TestExecuteFindEnforcesFirewallAndSensitivity verifies node scans honor read policy.
func TestExecuteFindEnforcesFirewallAndSensitivity(t *testing.T) {
	ctx := context.Background()
	store := openTestStore(t)
	defer store.Close()

	_ = mustNodeWithAccess(t, store, graph.KindTask, "task:visible:user", "User visible", graph.FirewallUser, graph.SensitivityPrivate)
	_ = mustNodeWithAccess(t, store, graph.KindTask, "task:visible:global", "Global visible", graph.FirewallGlobal, graph.SensitivityInternal)
	_ = mustNodeWithAccess(t, store, graph.KindTask, "task:hidden:restricted", "Restricted hidden", graph.FirewallUser, graph.SensitivityRestricted)
	_ = mustNodeWithAccess(t, store, graph.KindTask, "task:hidden:project", "Project hidden", graph.FirewallProject, graph.SensitivityPrivate)

	result, err := NewExecutor(store).Execute(ctx, Request{
		Query: `FIND task RETURN title, sensitivity, firewall ORDER BY title ASC LIMIT 10`,
	})
	if err != nil {
		t.Fatalf("execute policy query: %v", err)
	}
	if len(result.Rows) != 1 || result.Rows[0]["title"] != "User visible" {
		t.Fatalf("rows = %#v, want same-firewall visible node only", result.Rows)
	}

	withGlobal, err := NewExecutor(store).Execute(ctx, Request{
		Query:         `FIND task RETURN title, sensitivity, firewall ORDER BY title ASC LIMIT 10`,
		IncludeGlobal: true,
	})
	if err != nil {
		t.Fatalf("execute global policy query: %v", err)
	}
	if len(withGlobal.Rows) != 2 {
		t.Fatalf("global rows = %#v, want visible user and global nodes", withGlobal.Rows)
	}
	if withGlobal.Rows[0]["title"] != "Global visible" || withGlobal.Rows[1]["title"] != "User visible" {
		t.Fatalf("global rows = %#v, want opt-in global visibility", withGlobal.Rows)
	}

	restricted, err := NewExecutor(store).Execute(ctx, Request{
		Query:                `FIND task RETURN title ORDER BY title ASC LIMIT 10`,
		AllowedSensitivities: []graph.Sensitivity{graph.SensitivityRestricted},
	})
	if err != nil {
		t.Fatalf("execute restricted policy query: %v", err)
	}
	if len(restricted.Rows) != 1 || restricted.Rows[0]["title"] != "Restricted hidden" {
		t.Fatalf("restricted rows = %#v, want explicitly granted restricted node", restricted.Rows)
	}
}

// TestExecuteMatchEnforcesEndpointAccess verifies traversals cannot leak hidden endpoints.
func TestExecuteMatchEnforcesEndpointAccess(t *testing.T) {
	ctx := context.Background()
	store := openTestStore(t)
	defer store.Close()

	work := mustNodeWithAccess(t, store, graph.KindTask, "task:policy:work", "Policy work", graph.FirewallUser, graph.SensitivityPrivate)
	visible := mustNodeWithAccess(t, store, graph.KindPerson, "person:policy:visible", "Visible Owner", graph.FirewallUser, graph.SensitivityPrivate)
	restricted := mustNodeWithAccess(t, store, graph.KindPerson, "person:policy:restricted", "Restricted Owner", graph.FirewallUser, graph.SensitivityRestricted)
	project := mustNodeWithAccess(t, store, graph.KindPerson, "person:policy:project", "Project Owner", graph.FirewallProject, graph.SensitivityPrivate)
	upsertEdge(t, store, work.ID, graph.RelationAssignedTo, visible.ID)
	upsertEdge(t, store, work.ID, graph.RelationAssignedTo, restricted.ID)
	upsertEdge(t, store, work.ID, graph.RelationAssignedTo, project.ID)

	result, err := NewExecutor(store).Execute(ctx, Request{
		Query: `MATCH task -[assigned_to]-> person RETURN from.title, to.title ORDER BY to.title ASC LIMIT 10`,
	})
	if err != nil {
		t.Fatalf("execute endpoint policy query: %v", err)
	}
	if len(result.Rows) != 1 || result.Rows[0]["to.title"] != "Visible Owner" {
		t.Fatalf("rows = %#v, want only default-visible endpoint", result.Rows)
	}

	granted, err := NewExecutor(store).Execute(ctx, Request{
		Query:                `MATCH task -[assigned_to]-> person RETURN to.title ORDER BY to.title ASC LIMIT 10`,
		AllowedSensitivities: []graph.Sensitivity{graph.SensitivityPrivate, graph.SensitivityRestricted},
	})
	if err != nil {
		t.Fatalf("execute granted endpoint policy query: %v", err)
	}
	if len(granted.Rows) != 2 || granted.Rows[0]["to.title"] != "Restricted Owner" || granted.Rows[1]["to.title"] != "Visible Owner" {
		t.Fatalf("granted rows = %#v, want private and restricted endpoints", granted.Rows)
	}
}

// TestExecuteAuditedNodeMutations verifies node mutations require provenance and audit.
func TestExecuteAuditedNodeMutations(t *testing.T) {
	ctx := context.Background()
	store := openTestStore(t)
	defer store.Close()

	source := mustNode(t, store, graph.KindSource, "source:phase6:node", "Phase 6 source")
	executor := NewExecutor(store)
	missingActor := Request{
		Query:        `INSERT NODE task SET title = "No actor"`,
		SourceNodeID: string(source.ID),
	}
	if _, err := executor.Execute(ctx, missingActor); err == nil {
		t.Fatalf("mutation without actor returned nil error")
	}
	missingSource := Request{
		Actor: "tester",
		Query: `INSERT NODE task SET title = "No source"`,
	}
	if _, err := executor.Execute(ctx, missingSource); err == nil {
		t.Fatalf("mutation without source returned nil error")
	}

	insert, err := executor.Execute(ctx, Request{
		Actor:        "tester",
		SourceNodeID: string(source.ID),
		Query:        `INSERT NODE task SET stable_key = "task:phase6", title = "Phase 6 task", status = "open", risk = 0.8 RETURN id, title, status, risk`,
	})
	if err != nil {
		t.Fatalf("insert node mutation: %v", err)
	}
	if len(insert.Rows) != 1 || insert.Rows[0]["title"] != "Phase 6 task" || insert.Rows[0]["status"] != "open" || insert.Rows[0]["risk"] != 0.8 {
		t.Fatalf("insert row = %#v, want typed node mutation row", insert.Rows)
	}
	nodeID := graph.NodeID(insert.Rows[0]["id"].(string))
	reinsert, err := executor.Execute(ctx, Request{
		Actor:        "tester",
		SourceNodeID: string(source.ID),
		Query:        `INSERT NODE task SET stable_key = "task:phase6", title = "Phase 6 task again" RETURN id, title`,
	})
	if err != nil {
		t.Fatalf("reinsert node mutation: %v", err)
	}
	if reinsert.Rows[0]["id"] != string(nodeID) || reinsert.Rows[0]["title"] != "Phase 6 task again" {
		t.Fatalf("reinsert row = %#v, want idempotent node upsert", reinsert.Rows[0])
	}

	set, err := executor.Execute(ctx, Request{
		Actor:        "tester",
		SourceNodeID: string(source.ID),
		Query:        fmt.Sprintf(`SET NODE %s SET title = "Updated Phase 6 task", priority = "high" RETURN title, priority`, nodeID),
	})
	if err != nil {
		t.Fatalf("set node mutation: %v", err)
	}
	if set.Rows[0]["title"] != "Updated Phase 6 task" || set.Rows[0]["priority"] != "high" {
		t.Fatalf("set row = %#v, want updated title and priority", set.Rows[0])
	}

	deleted, err := executor.Execute(ctx, Request{
		Actor:        "tester",
		SourceNodeID: string(source.ID),
		Query:        fmt.Sprintf(`DELETE NODE %s`, nodeID),
	})
	if err != nil {
		t.Fatalf("delete node mutation: %v", err)
	}
	if deleted.Rows[0]["lifecycle_status"] != "deleted" {
		t.Fatalf("delete row = %#v, want deleted lifecycle status", deleted.Rows[0])
	}
	events, err := store.ListAuditEvents(ctx, 20)
	if err != nil {
		t.Fatalf("list audit events: %v", err)
	}
	if !containsAudit(events, "query_insert_node", nodeID, "", source.ID) || !containsAudit(events, "query_set_node_property", nodeID, "", source.ID) || !containsAudit(events, "query_delete_node", nodeID, "", source.ID) {
		t.Fatalf("audit events = %#v, want node insert/property/delete audits", events)
	}
}

// TestExecuteAuditedEdgeMutations verifies edge mutations and lifecycle delete are audited.
func TestExecuteAuditedEdgeMutations(t *testing.T) {
	ctx := context.Background()
	store := openTestStore(t)
	defer store.Close()

	source := mustNode(t, store, graph.KindSource, "source:phase6:edge", "Phase 6 edge source")
	from := mustNode(t, store, graph.KindTask, "task:phase6:from", "Phase 6 from")
	to := mustNode(t, store, graph.KindTask, "task:phase6:to", "Phase 6 to")
	executor := NewExecutor(store)

	insert, err := executor.Execute(ctx, Request{
		Actor:        "tester",
		SourceNodeID: string(source.ID),
		Query:        fmt.Sprintf(`INSERT EDGE %s -[depends_on]-> %s SET note = "needs this first" RETURN edge.id, edge.type, note`, from.ID, to.ID),
	})
	if err != nil {
		t.Fatalf("insert edge mutation: %v", err)
	}
	if len(insert.Rows) != 1 || insert.Rows[0]["edge.type"] != "depends_on" || insert.Rows[0]["note"] != "needs this first" {
		t.Fatalf("insert edge row = %#v, want dependency edge with note", insert.Rows)
	}
	edgeID := graph.EdgeID(insert.Rows[0]["edge.id"].(string))
	reinsert, err := executor.Execute(ctx, Request{
		Actor:        "tester",
		SourceNodeID: string(source.ID),
		Query:        fmt.Sprintf(`INSERT EDGE %s -[depends_on]-> %s SET note = "needs this first" RETURN edge.id, note`, from.ID, to.ID),
	})
	if err != nil {
		t.Fatalf("reinsert edge mutation: %v", err)
	}
	if reinsert.Rows[0]["edge.id"] != string(edgeID) || reinsert.Rows[0]["note"] != "needs this first" {
		t.Fatalf("reinsert edge row = %#v, want idempotent edge upsert", reinsert.Rows[0])
	}

	set, err := executor.Execute(ctx, Request{
		Actor:        "tester",
		SourceNodeID: string(source.ID),
		Query:        fmt.Sprintf(`SET EDGE %s SET confidence = 0.5, note = "updated note" RETURN edge.id, edge.confidence, note`, edgeID),
	})
	if err != nil {
		t.Fatalf("set edge mutation: %v", err)
	}
	if set.Rows[0]["edge.confidence"] != 0.5 || set.Rows[0]["note"] != "updated note" {
		t.Fatalf("set edge row = %#v, want confidence and note", set.Rows[0])
	}

	deleted, err := executor.Execute(ctx, Request{
		Actor:        "tester",
		SourceNodeID: string(source.ID),
		Query:        fmt.Sprintf(`DELETE EDGE %s`, edgeID),
	})
	if err != nil {
		t.Fatalf("delete edge mutation: %v", err)
	}
	if deleted.Rows[0]["edge.lifecycle_status"] != "deleted" {
		t.Fatalf("delete edge row = %#v, want deleted lifecycle status", deleted.Rows[0])
	}
	events, err := store.ListAuditEvents(ctx, 20)
	if err != nil {
		t.Fatalf("list audit events: %v", err)
	}
	if !containsAudit(events, "query_insert_edge", "", edgeID, source.ID) || !containsAudit(events, "query_set_edge_property", "", edgeID, source.ID) || !containsAudit(events, "query_delete_edge", "", edgeID, source.ID) {
		t.Fatalf("audit events = %#v, want edge insert/property/delete audits", events)
	}
}

// TestParseRejectsUnsupportedMutations verifies unsupported mutation grammar is explicit.
func TestParseRejectsUnsupportedMutations(t *testing.T) {
	if _, err := Parse(`UPDATE NODE node_1 SET title = "x"`); err == nil {
		t.Fatalf("parse unsupported mutation returned nil error")
	}
}

// TestParseRejectsInvalidGroupedReturn verifies aggregate rows stay deterministic.
func TestParseRejectsInvalidGroupedReturn(t *testing.T) {
	if _, err := Parse(`FIND task GROUP BY status RETURN title, count`); err == nil {
		t.Fatalf("parse invalid grouped return returned nil error")
	}
}

// upsertTextProperty writes one text property for query tests.
func upsertTextProperty(t *testing.T, store *graphstore.Store, nodeID graph.NodeID, key string, value string) {
	t.Helper()
	if _, err := store.UpsertNodeProperty(context.Background(), graph.UpsertNodePropertyRequest{
		NodeID: nodeID,
		Key:    key,
		Value:  graph.Value{Type: graph.ValueText, Text: value},
		Actor:  "test",
	}); err != nil {
		t.Fatalf("upsert property %s=%s: %v", key, value, err)
	}
}

// upsertNumberProperty writes one number property for query tests.
func upsertNumberProperty(t *testing.T, store *graphstore.Store, nodeID graph.NodeID, key string, value float64) {
	t.Helper()
	if _, err := store.UpsertNodeProperty(context.Background(), graph.UpsertNodePropertyRequest{
		NodeID: nodeID,
		Key:    key,
		Value:  graph.Value{Type: graph.ValueNumber, Number: value},
		Actor:  "test",
	}); err != nil {
		t.Fatalf("upsert property %s=%f: %v", key, value, err)
	}
}

// upsertTimeProperty writes one time property for query tests.
func upsertTimeProperty(t *testing.T, store *graphstore.Store, nodeID graph.NodeID, key string, value time.Time) {
	t.Helper()
	if _, err := store.UpsertNodeProperty(context.Background(), graph.UpsertNodePropertyRequest{
		NodeID: nodeID,
		Key:    key,
		Value:  graph.Value{Type: graph.ValueTime, Time: &value},
		Actor:  "test",
	}); err != nil {
		t.Fatalf("upsert property %s=%s: %v", key, value.Format(time.RFC3339Nano), err)
	}
}

// upsertEdge writes one graph edge for query tests.
func upsertEdge(t *testing.T, store *graphstore.Store, from graph.NodeID, relation graph.RelationType, to graph.NodeID) graph.Edge {
	t.Helper()
	edge, err := store.UpsertEdge(context.Background(), graph.UpsertEdgeRequest{
		FromNodeID: from,
		Type:       relation,
		ToNodeID:   to,
		Actor:      "test",
	})
	if err != nil {
		t.Fatalf("upsert edge %s -> %s: %v", from, to, err)
	}
	return edge
}

// openTestStore creates an isolated graph store for query tests.
func openTestStore(t *testing.T) *graphstore.Store {
	t.Helper()
	root := t.TempDir()
	store, err := graphstore.Open(context.Background(), graphstore.Config{
		DBPath:   filepath.Join(root, "graph.db"),
		DataRoot: filepath.Join(root, "data"),
	})
	if err != nil {
		t.Fatalf("open graph store: %v", err)
	}
	return store
}

// mustNode writes one graph node for query tests.
func mustNode(t *testing.T, store *graphstore.Store, kind graph.NodeKind, stableKey string, title string) graph.Node {
	t.Helper()
	node, err := store.UpsertNode(context.Background(), graph.UpsertNodeRequest{
		Kind:      kind,
		StableKey: stableKey,
		Title:     title,
		Actor:     "test",
	})
	if err != nil {
		t.Fatalf("upsert node %s: %v", title, err)
	}
	return node
}

// mustNodeWithAccess writes one graph node with explicit read-policy metadata.
func mustNodeWithAccess(t *testing.T, store *graphstore.Store, kind graph.NodeKind, stableKey string, title string, firewall graph.Firewall, sensitivity graph.Sensitivity) graph.Node {
	t.Helper()
	node, err := store.UpsertNode(context.Background(), graph.UpsertNodeRequest{
		Kind:        kind,
		StableKey:   stableKey,
		Title:       title,
		Firewall:    firewall,
		Sensitivity: sensitivity,
		Actor:       "test",
	})
	if err != nil {
		t.Fatalf("upsert node %s: %v", title, err)
	}
	return node
}

// containsAudit reports whether a mutation audit event exists for a subject.
func containsAudit(events []graph.AuditEvent, kind string, nodeID graph.NodeID, edgeID graph.EdgeID, sourceID graph.NodeID) bool {
	for _, event := range events {
		if event.Kind != kind || event.SourceNodeID != sourceID {
			continue
		}
		if nodeID != "" && event.SubjectNodeID == nodeID {
			return true
		}
		if edgeID != "" && event.SubjectEdgeID == edgeID {
			return true
		}
	}
	return false
}
