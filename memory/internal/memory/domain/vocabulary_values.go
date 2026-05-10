// This file exposes domain vocabulary value lists for validators and schemas.
package domain

import "memory/internal/memory/vocabulary"

// KindStrings returns memory object kind values.
func KindStrings() []string {
	return vocabulary.StringValues(Kinds())
}

// CompiledPageKindStrings returns memory page kind values.
func CompiledPageKindStrings() []string {
	return vocabulary.StringValues(CompiledPageKinds())
}

// RelationshipTypeStrings returns memory relationship values.
func RelationshipTypeStrings() []string {
	return vocabulary.StringValues(RelationshipTypes())
}

// ScopeStrings returns shared ownership scope values.
func ScopeStrings() []string {
	return vocabulary.ScopeStrings()
}

// SensitivityStrings returns shared sensitivity values.
func SensitivityStrings() []string {
	return vocabulary.SensitivityStrings()
}

// TrustLevelStrings returns shared trust level values.
func TrustLevelStrings() []string {
	return vocabulary.TrustLevelStrings()
}

// StatusStrings returns memory lifecycle status values.
func StatusStrings() []string {
	return vocabulary.MemoryStatusStrings()
}

// TaskStatusStrings returns task lifecycle status values.
func TaskStatusStrings() []string {
	return vocabulary.StringValues(TaskStatuses())
}

// TaskPriorityStrings returns task priority values.
func TaskPriorityStrings() []string {
	return vocabulary.StringValues(TaskPriorities())
}

// TaskMemoryRelationshipStrings returns task-to-memory relationship values.
func TaskMemoryRelationshipStrings() []string {
	return vocabulary.StringValues(TaskMemoryRelationships())
}

// TaskRelationTypeStrings returns directed task relation values.
func TaskRelationTypeStrings() []string {
	return vocabulary.StringValues(TaskRelationTypes())
}

// TaskRelationDirectionStrings returns accepted task relation direction values.
func TaskRelationDirectionStrings() []string {
	return []string{"outgoing", "incoming", "either"}
}

// ExecutiveSummaryHorizonStrings returns supported projection horizons.
func ExecutiveSummaryHorizonStrings() []string {
	return []string{"now", "today", "tomorrow", "week", "all"}
}

// ExecutiveSummaryChannelStrings returns supported projection presentation channels.
func ExecutiveSummaryChannelStrings() []string {
	return []string{"ui", "slack", "chat", "api"}
}

// TaskRelationTypes returns directed task relation values as typed constants.
func TaskRelationTypes() []TaskRelationType {
	return []TaskRelationType{TaskRelationBlocks, TaskRelationDependsOn, TaskRelationEnables, TaskRelationPartOf, TaskRelationRelated}
}

// TaskRelationDirectionSemantics describes projection edge direction.
func TaskRelationDirectionSemantics(relationType TaskRelationType) string {
	switch relationType {
	case TaskRelationBlocks:
		return "from_blocks_to"
	case TaskRelationDependsOn:
		return "from_depends_on_to"
	case TaskRelationEnables:
		return "from_enables_to"
	case TaskRelationPartOf:
		return "from_part_of_to"
	default:
		return "from_related_to_to"
	}
}

// Kinds returns memory object kind values as typed constants.
func Kinds() []Kind {
	return []Kind{KindConversation, KindDocument, KindToolOutput, KindArtifact, KindSummary, KindEntityPage, KindTimeline, KindProfileFact}
}

// CompiledPageKinds returns memory page kind values as typed constants.
func CompiledPageKinds() []Kind {
	return []Kind{KindEntityPage, KindTimeline}
}

// RelationshipTypes returns memory relationship values as typed constants.
func RelationshipTypes() []RelationshipType {
	return []RelationshipType{RelationshipGeneratedBy, RelationshipRefersTo, RelationshipSupersedes, RelationshipContradicts, RelationshipDuplicates, RelationshipRelatedToEvent}
}

// TaskStatuses returns task lifecycle status values as typed constants.
func TaskStatuses() []TaskStatus {
	return []TaskStatus{TaskStatusOpen, TaskStatusWaiting, TaskStatusBlocked, TaskStatusDone, TaskStatusCanceled}
}

// TaskPriorities returns task priority values as typed constants.
func TaskPriorities() []TaskPriority {
	return []TaskPriority{TaskPriorityLow, TaskPriorityNormal, TaskPriorityHigh, TaskPriorityUrgent}
}

// TaskMemoryRelationships returns task-to-memory relationship values as typed constants.
func TaskMemoryRelationships() []TaskMemoryRelationship {
	return []TaskMemoryRelationship{TaskMemoryOriginatedFrom, TaskMemoryContext, TaskMemorySupporting, TaskMemoryRelated}
}

// containsVocabularyValue reports whether values includes target.
func containsVocabularyValue[T comparable](values []T, target T) bool {
	for _, value := range values {
		if value == target {
			return true
		}
	}
	return false
}
