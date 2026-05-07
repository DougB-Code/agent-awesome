package state

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"agentprovision/internal/configpath"
)

// ErrNotFound reports that a requested record does not exist.
var ErrNotFound = errors.New("record not found")

// Store persists non-secret provisioning records.
type Store struct {
	root string
}

// DefaultStore returns the production provisioning state store.
func DefaultStore() (Store, error) {
	root, err := configpath.ProvisioningRoot()
	if err != nil {
		return Store{}, err
	}
	return NewStore(root), nil
}

// NewStore creates a store rooted at one directory.
func NewStore(root string) Store {
	return Store{root: root}
}

// Load reads one provisioned agent record.
func (s Store) Load(agentID string) (AgentRecord, error) {
	path, err := s.path(agentID)
	if err != nil {
		return AgentRecord{}, err
	}
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return AgentRecord{}, ErrNotFound
	}
	if err != nil {
		return AgentRecord{}, fmt.Errorf("read agent record: %w", err)
	}
	var record AgentRecord
	if err := json.Unmarshal(data, &record); err != nil {
		return AgentRecord{}, fmt.Errorf("decode agent record: %w", err)
	}
	return record, nil
}

// Save writes one provisioned agent record.
func (s Store) Save(record AgentRecord) (AgentRecord, error) {
	if strings.TrimSpace(record.AgentID) == "" {
		return AgentRecord{}, fmt.Errorf("agent id is required")
	}
	now := time.Now().UTC()
	if record.CreatedAt.IsZero() {
		record.CreatedAt = now
	}
	record.UpdatedAt = now
	path, err := s.path(record.AgentID)
	if err != nil {
		return AgentRecord{}, err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return AgentRecord{}, fmt.Errorf("create state directory: %w", err)
	}
	data, err := json.MarshalIndent(record, "", "\t")
	if err != nil {
		return AgentRecord{}, fmt.Errorf("encode agent record: %w", err)
	}
	data = append(data, '\n')
	if err := os.WriteFile(path, data, 0o600); err != nil {
		return AgentRecord{}, fmt.Errorf("write agent record: %w", err)
	}
	return record, nil
}

// Delete removes one provisioned agent record.
func (s Store) Delete(agentID string) error {
	path, err := s.path(agentID)
	if err != nil {
		return err
	}
	if err := os.Remove(path); errors.Is(err, os.ErrNotExist) {
		return ErrNotFound
	} else if err != nil {
		return fmt.Errorf("delete agent record: %w", err)
	}
	return nil
}

// List reads all provisioned agent records sorted by agent id.
func (s Store) List() ([]AgentRecord, error) {
	if strings.TrimSpace(s.root) == "" {
		return nil, fmt.Errorf("state root is required")
	}
	agentDir := filepath.Join(s.root, "agents")
	entries, err := os.ReadDir(agentDir)
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("read agent records directory: %w", err)
	}
	var records []AgentRecord
	for _, entry := range entries {
		if entry.IsDir() || filepath.Ext(entry.Name()) != ".json" {
			continue
		}
		agentID := strings.TrimSuffix(entry.Name(), ".json")
		record, err := s.Load(agentID)
		if err != nil {
			return nil, err
		}
		records = append(records, record)
	}
	sort.Slice(records, func(left, right int) bool {
		return records[left].AgentID < records[right].AgentID
	})
	return records, nil
}

// path returns the record path for one agent id.
func (s Store) path(agentID string) (string, error) {
	agentID = strings.TrimSpace(agentID)
	if agentID == "" {
		return "", fmt.Errorf("agent id is required")
	}
	if s.root == "" {
		return "", fmt.Errorf("state root is required")
	}
	return filepath.Join(s.root, "agents", agentID+".json"), nil
}
