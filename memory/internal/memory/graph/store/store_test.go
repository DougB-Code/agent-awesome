package store

import (
	"context"
	"database/sql"
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"testing"

	graph "memory/internal/memory/graph/domain"
)

// TestUpsertNodeReusesStableIdentity verifies node stable keys are idempotent.
func TestUpsertNodeReusesStableIdentity(t *testing.T) {
	ctx := context.Background()
	store := openTestStore(t)
	defer store.Close()

	first, err := store.UpsertNode(ctx, graph.UpsertNodeRequest{
		Kind:      graph.KindTask,
		StableKey: "task:forecast-inputs",
		Title:     "Clean forecast inputs",
		Actor:     "test",
	})
	if err != nil {
		t.Fatalf("upsert first node: %v", err)
	}
	second, err := store.UpsertNode(ctx, graph.UpsertNodeRequest{
		Kind:      graph.KindTask,
		StableKey: "task:forecast-inputs",
		Title:     "Clean forecast input data",
		Actor:     "test",
	})
	if err != nil {
		t.Fatalf("upsert second node: %v", err)
	}
	if second.ID != first.ID {
		t.Fatalf("node id = %s, want reused %s", second.ID, first.ID)
	}
	if second.Title != "Clean forecast input data" {
		t.Fatalf("node title = %q, want update", second.Title)
	}
	if second.Status != graph.StatusActive || second.Scope != graph.ScopeUser || second.Sensitivity != graph.SensitivityPrivate {
		t.Fatalf("node defaults = %#v", second)
	}
}

// TestDirectedEdgesAndEdgeProperties verifies edge direction and edge metadata.
func TestDirectedEdgesAndEdgeProperties(t *testing.T) {
	ctx := context.Background()
	store := openTestStore(t)
	defer store.Close()

	taskA := mustNode(t, store, graph.KindTask, "task:a", "Prepare readout")
	taskB := mustNode(t, store, graph.KindTask, "task:b", "Clean inputs")
	taskC := mustNode(t, store, graph.KindTask, "task:c", "BI export")
	depends, err := store.UpsertEdge(ctx, graph.UpsertEdgeRequest{
		FromNodeID: taskA.ID,
		Type:       graph.RelationDependsOn,
		ToNodeID:   taskB.ID,
		Actor:      "test",
	})
	if err != nil {
		t.Fatalf("upsert depends edge: %v", err)
	}
	if _, err := store.UpsertEdge(ctx, graph.UpsertEdgeRequest{
		FromNodeID: taskC.ID,
		Type:       graph.RelationBlocks,
		ToNodeID:   taskA.ID,
		Actor:      "test",
	}); err != nil {
		t.Fatalf("upsert blocks edge: %v", err)
	}
	outgoing, err := store.ListOutgoingEdges(ctx, taskA.ID, []graph.RelationType{graph.RelationDependsOn})
	if err != nil {
		t.Fatalf("list outgoing: %v", err)
	}
	if len(outgoing) != 1 || outgoing[0].ToNodeID != taskB.ID {
		t.Fatalf("outgoing = %#v, want task A depends_on task B", outgoing)
	}
	incomingBlocks, err := store.ListIncomingEdges(ctx, taskA.ID, []graph.RelationType{graph.RelationBlocks})
	if err != nil {
		t.Fatalf("list incoming blocks: %v", err)
	}
	if len(incomingBlocks) != 1 || incomingBlocks[0].FromNodeID != taskC.ID {
		t.Fatalf("incoming blocks = %#v, want task C blocks task A", incomingBlocks)
	}
	incomingDepends, err := store.ListIncomingEdges(ctx, taskA.ID, []graph.RelationType{graph.RelationDependsOn})
	if err != nil {
		t.Fatalf("list incoming depends: %v", err)
	}
	if len(incomingDepends) != 0 {
		t.Fatalf("incoming depends = %#v, want direction preserved", incomingDepends)
	}
	property, err := store.UpsertEdgeProperty(ctx, graph.UpsertEdgePropertyRequest{
		EdgeID: depends.ID,
		Key:    "lag_days",
		Value:  graph.Value{Type: graph.ValueNumber, Number: 2},
		Actor:  "test",
	})
	if err != nil {
		t.Fatalf("upsert edge property: %v", err)
	}
	if property.Value.Number != 2 {
		t.Fatalf("edge property = %#v, want numeric lag", property)
	}
}

// TestSourceBackedProperties verifies properties retain source provenance.
func TestSourceBackedProperties(t *testing.T) {
	ctx := context.Background()
	store := openTestStore(t)
	defer store.Close()

	source := mustNode(t, store, graph.KindEvidence, "evidence:standup", "Standup notes")
	task := mustNode(t, store, graph.KindTask, "task:risk", "Resolve risk")
	first, err := store.UpsertNodeProperty(ctx, graph.UpsertNodePropertyRequest{
		NodeID:       task.ID,
		Key:          "status",
		Value:        graph.Value{Type: graph.ValueText, Text: "open"},
		SourceNodeID: source.ID,
		TrustLevel:   graph.TrustSourceOriginal,
		Actor:        "test",
	})
	if err != nil {
		t.Fatalf("upsert first property: %v", err)
	}
	second, err := store.UpsertNodeProperty(ctx, graph.UpsertNodePropertyRequest{
		NodeID:       task.ID,
		Key:          "status",
		Value:        graph.Value{Type: graph.ValueText, Text: "blocked"},
		SourceNodeID: source.ID,
		TrustLevel:   graph.TrustSourceOriginal,
		Actor:        "test",
	})
	if err != nil {
		t.Fatalf("upsert second property: %v", err)
	}
	if second.ID != first.ID {
		t.Fatalf("property id = %s, want reused %s", second.ID, first.ID)
	}
	if second.SourceNodeID != source.ID || second.TrustLevel != graph.TrustSourceOriginal || second.Value.Text != "blocked" {
		t.Fatalf("property = %#v, want source-backed update", second)
	}
	properties, err := store.ListNodeProperties(ctx, task.ID)
	if err != nil {
		t.Fatalf("list properties: %v", err)
	}
	if len(properties) != 1 || properties[0].SourceNodeID != source.ID {
		t.Fatalf("properties = %#v, want one sourced property", properties)
	}
}

// TestLifecycleDeletionExcludesSearch verifies deletion is a lifecycle state.
func TestLifecycleDeletionExcludesSearch(t *testing.T) {
	ctx := context.Background()
	store := openTestStore(t)
	defer store.Close()

	node := mustNode(t, store, graph.KindMemory, "memory:hidden", "Hidden OAuth note")
	if err := store.ReindexNode(ctx, node.ID); err != nil {
		t.Fatalf("reindex node: %v", err)
	}
	before, err := store.SearchNodes(ctx, graph.SearchNodesQuery{Text: "OAuth", Scope: graph.ScopeUser})
	if err != nil {
		t.Fatalf("search before delete: %v", err)
	}
	if !containsNode(before, node.ID) {
		t.Fatalf("search before delete = %#v, want node", before)
	}
	deleted, err := store.SetNodeStatus(ctx, node.ID, graph.StatusDeleted, "test")
	if err != nil {
		t.Fatalf("set node deleted: %v", err)
	}
	if deleted.Status != graph.StatusDeleted {
		t.Fatalf("deleted node status = %q", deleted.Status)
	}
	after, err := store.SearchNodes(ctx, graph.SearchNodesQuery{Text: "OAuth", Scope: graph.ScopeUser})
	if err != nil {
		t.Fatalf("search after delete: %v", err)
	}
	if containsNode(after, node.ID) {
		t.Fatalf("search after delete = %#v, want deleted node excluded", after)
	}
}

// TestEvidenceBlobAuditAndFTSSearch verifies evidence IO, audit, and FTS search.
func TestEvidenceBlobAuditAndFTSSearch(t *testing.T) {
	ctx := context.Background()
	store := openTestStore(t)
	defer store.Close()

	evidence := mustNode(t, store, graph.KindEvidence, "evidence:oauth-report", "OAuth report")
	blob, err := store.WriteEvidenceBlob(ctx, graph.WriteEvidenceBlobRequest{
		NodeID:       evidence.ID,
		Content:      "OAuth browser automation reporting notes",
		MediaType:    "text/plain",
		SourceSystem: "test",
		SourceID:     "source-1",
		Actor:        "test",
	})
	if err != nil {
		t.Fatalf("write evidence: %v", err)
	}
	content, err := store.ReadEvidenceBlobContent(ctx, evidence.ID)
	if err != nil {
		t.Fatalf("read evidence: %v", err)
	}
	if content != "OAuth browser automation reporting notes" || blob.SizeBytes == 0 || blob.Checksum == "" {
		t.Fatalf("blob = %#v content = %q, want persisted evidence", blob, content)
	}
	events, err := store.ListAuditEvents(ctx, 10)
	if err != nil {
		t.Fatalf("list audit events: %v", err)
	}
	if !containsAuditEvent(events, "write_evidence_blob", evidence.ID, "", evidence.ID) {
		t.Fatalf("events = %#v, want evidence write audit", events)
	}
	if _, err := store.UpsertAlias(ctx, graph.UpsertAliasRequest{NodeID: evidence.ID, Alias: "OAuth automation", Kind: "name"}); err != nil {
		t.Fatalf("upsert alias: %v", err)
	}
	if _, err := store.UpsertNodeProperty(ctx, graph.UpsertNodePropertyRequest{
		NodeID: evidence.ID,
		Key:    "summary",
		Value:  graph.Value{Type: graph.ValueText, Text: "Browser automation reporting"},
		Actor:  "test",
	}); err != nil {
		t.Fatalf("upsert evidence property: %v", err)
	}
	if _, err := store.AppendAudit(ctx, graph.AppendAuditRequest{
		Kind:          "capture",
		Actor:         "test",
		SubjectNodeID: evidence.ID,
		Message:       "captured evidence",
	}); err != nil {
		t.Fatalf("append audit: %v", err)
	}
	if err := store.ReindexNode(ctx, evidence.ID); err != nil {
		t.Fatalf("reindex evidence: %v", err)
	}
	results, err := store.SearchNodes(ctx, graph.SearchNodesQuery{Text: "automation", Scope: graph.ScopeUser, Kinds: []graph.NodeKind{graph.KindEvidence}})
	if err != nil {
		t.Fatalf("search evidence: %v", err)
	}
	if len(results) != 1 || results[0].ID != evidence.ID {
		t.Fatalf("results = %#v, want evidence node", results)
	}
}

// TestUnitOfWorkRollsBackGraphWrites verifies failed transactions leave no nodes.
func TestUnitOfWorkRollsBackGraphWrites(t *testing.T) {
	ctx := context.Background()
	store := openTestStore(t)
	defer store.Close()
	sentinel := errors.New("rollback")

	err := store.WithUnitOfWork(ctx, func(tx *Store) error {
		if _, err := tx.UpsertNode(ctx, graph.UpsertNodeRequest{
			Kind:      graph.KindMemory,
			StableKey: "memory:rollback",
			Title:     "Rolled back memory",
			Actor:     "test",
		}); err != nil {
			return err
		}
		return sentinel
	})
	if !errors.Is(err, sentinel) {
		t.Fatalf("WithUnitOfWork() error = %v, want sentinel", err)
	}
	count, err := store.CountNodes(ctx, graph.KindMemory, graph.StatusActive)
	if err != nil {
		t.Fatalf("count nodes: %v", err)
	}
	if count != 0 {
		t.Fatalf("count = %d, want rollback to remove node", count)
	}
}

// TestUnitOfWorkRollsBackEvidenceFile verifies staged blobs are cleaned up.
func TestUnitOfWorkRollsBackEvidenceFile(t *testing.T) {
	ctx := context.Background()
	store := openTestStore(t)
	defer store.Close()
	sentinel := errors.New("rollback")
	var blob graph.EvidenceBlob

	err := store.WithUnitOfWork(ctx, func(tx *Store) error {
		evidence := mustNode(t, tx, graph.KindEvidence, "evidence:rollback", "Rollback evidence")
		var err error
		blob, err = tx.WriteEvidenceBlob(ctx, graph.WriteEvidenceBlobRequest{
			NodeID:       evidence.ID,
			Content:      "temporary evidence",
			MediaType:    "text/plain",
			SourceSystem: "test",
			SourceID:     "source-rollback",
			Actor:        "test",
		})
		if err != nil {
			return err
		}
		if content, err := tx.ReadEvidenceBlobContent(ctx, evidence.ID); err != nil || content != "temporary evidence" {
			return errors.New("staged evidence content was unreadable")
		}
		return sentinel
	})
	if !errors.Is(err, sentinel) {
		t.Fatalf("WithUnitOfWork() error = %v, want sentinel", err)
	}
	if _, err := store.GetEvidenceBlob(ctx, blob.NodeID); !errors.Is(err, sql.ErrNoRows) {
		t.Fatalf("GetEvidenceBlob() error = %v, want sql.ErrNoRows", err)
	}
	if _, err := os.Stat(filepath.Join(store.dataRoot, blob.Path)); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("evidence file stat error = %v, want missing file", err)
	}
}

// containsAuditEvent reports whether an audit event exists for a graph subject.
func containsAuditEvent(events []graph.AuditEvent, kind string, nodeID graph.NodeID, edgeID graph.EdgeID, sourceID graph.NodeID) bool {
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

// TestSearchEnforcesSensitivity verifies restricted nodes require permission.
func TestSearchEnforcesSensitivity(t *testing.T) {
	ctx := context.Background()
	store := openTestStore(t)
	defer store.Close()

	restricted, err := store.UpsertNode(ctx, graph.UpsertNodeRequest{
		Kind:        graph.KindMemory,
		StableKey:   "memory:payroll",
		Title:       "Payroll note",
		Sensitivity: graph.SensitivityRestricted,
		Actor:       "test",
	})
	if err != nil {
		t.Fatalf("upsert restricted node: %v", err)
	}
	if err := store.ReindexNode(ctx, restricted.ID); err != nil {
		t.Fatalf("reindex restricted node: %v", err)
	}
	defaultResults, err := store.SearchNodes(ctx, graph.SearchNodesQuery{Text: "Payroll", Scope: graph.ScopeUser})
	if err != nil {
		t.Fatalf("default search: %v", err)
	}
	if len(defaultResults) != 0 {
		t.Fatalf("default results = %#v, want restricted node excluded", defaultResults)
	}
	restrictedResults, err := store.SearchNodes(ctx, graph.SearchNodesQuery{
		Text:                 "Payroll",
		Scope:                graph.ScopeUser,
		AllowedSensitivities: []graph.Sensitivity{graph.SensitivityRestricted},
	})
	if err != nil {
		t.Fatalf("restricted search: %v", err)
	}
	if got := nodeIDs(restrictedResults); !reflect.DeepEqual(got, []graph.NodeID{restricted.ID}) {
		t.Fatalf("restricted results = %#v, want %s", got, restricted.ID)
	}
}

// openTestStore creates an isolated graph store.
func openTestStore(t *testing.T) *Store {
	t.Helper()
	root := t.TempDir()
	store, err := Open(context.Background(), Config{
		DBPath:   filepath.Join(root, "graph.db"),
		DataRoot: filepath.Join(root, "data"),
	})
	if err != nil {
		t.Fatalf("open graph store: %v", err)
	}
	return store
}

// mustNode creates a graph node or fails the test.
func mustNode(t *testing.T, store *Store, kind graph.NodeKind, stableKey string, title string) graph.Node {
	t.Helper()
	node, err := store.UpsertNode(context.Background(), graph.UpsertNodeRequest{
		Kind:      kind,
		StableKey: stableKey,
		Title:     title,
		Actor:     "test",
	})
	if err != nil {
		t.Fatalf("upsert node %s: %v", stableKey, err)
	}
	return node
}

// containsNode reports whether a node slice includes an id.
func containsNode(nodes []graph.Node, id graph.NodeID) bool {
	for _, node := range nodes {
		if node.ID == id {
			return true
		}
	}
	return false
}

// nodeIDs returns node ids in result order.
func nodeIDs(nodes []graph.Node) []graph.NodeID {
	ids := make([]graph.NodeID, 0, len(nodes))
	for _, node := range nodes {
		ids = append(ids, node.ID)
	}
	return ids
}
