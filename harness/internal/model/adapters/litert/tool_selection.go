// This file selects compact tool declarations for LiteRT prompts.
package litert

import (
	"fmt"
	"sort"
	"strings"
	"unicode"

	"agentawesome/internal/model/protocol"
	llmapi "google.golang.org/adk/model"
	"google.golang.org/genai"
)

const maxGemmaToolDeclarations = 6

var liteRTToolHints = map[string][]string{
	"remember":                       {"remember", "memory", "preference", "fact", "note", "store", "save", "recall later"},
	"save_memory_candidate":          {"memory source", "raw source", "source content", "advanced memory"},
	"search_memory":                  {"search memory", "recall", "what do you know", "find memory", "look up"},
	"search_sources":                 {"search sources", "source content", "find source"},
	"load_entity_page":               {"entity page", "profile page", "load page"},
	"load_timeline":                  {"timeline", "history", "chronology"},
	"refresh_compiled_page":          {"refresh page", "rebuild page", "refresh timeline"},
	"repair_memory_record":           {"repair memory", "fix memory", "correct memory"},
	"submit_memory_correction":       {"memory correction", "correction", "wrong memory"},
	"query_context_graph":            {"context graph", "graph query", "sql", "query graph"},
	"create_task":                    {"reminder", "remind", "todo", "to do", "task", "need to", "buy", "purchase", "pick up", "errand", "deadline", "due", "schedule", "add task", "make a reminder"},
	"get_task":                       {"get task", "task detail", "open task", "show task"},
	"list_tasks":                     {"list tasks", "show tasks", "what tasks", "tasks", "todos", "to dos"},
	"task_graph_projection":          {"task graph", "task projection", "task map"},
	"project_executive_summary":      {"what matters today", "what am i forgetting", "what should i work on", "what can you handle", "brief me", "needs my attention", "today summary"},
	"explain_executive_summary_item": {"why this", "why is", "explain today", "explain item"},
	"update_task":                    {"update task", "edit task", "change task", "reschedule"},
	"complete_task":                  {"complete task", "mark done", "done", "finished", "finish task"},
	"cancel_task":                    {"cancel task", "drop task", "abandon task"},
	"delete_task":                    {"delete task", "remove task"},
	"link_task_memory":               {"link task", "attach memory", "task context"},
	"list_task_relations":            {"task relations", "dependencies", "related tasks"},
	"traverse_task_relations":        {"traverse tasks", "dependency path", "blocked by"},
	"upsert_task_relation":           {"relate tasks", "add dependency", "link tasks"},
	"delete_task_relation":           {"remove dependency", "delete relation", "unlink tasks"},
	"local_exec":                     {"run command", "execute command", "git status", "shell"},
	"request_command":                {"request command", "run command", "shell command"},
}

var taskIntentPhrases = []string{
	"reminder",
	"remind",
	"todo",
	"to do",
	"task",
	"need to",
	"buy",
	"purchase",
	"pick up",
	"errand",
	"deadline",
	"due",
	"schedule",
}

var memoryIntentPhrases = []string{
	"remember",
	"memory",
	"preference",
	"favorite",
	"fact",
	"note",
	"store this",
	"save this",
}

type rankedDeclaration struct {
	index       int
	score       int
	declaration *genai.FunctionDeclaration
}

// gemmaFunctionDeclarationsForRequest returns a small prompt-safe tool catalog.
func gemmaFunctionDeclarationsForRequest(req *llmapi.LLMRequest) []*genai.FunctionDeclaration {
	declarations := protocol.FunctionDeclarations(req)
	if len(declarations) <= maxGemmaToolDeclarations {
		return declarations
	}
	query := requestToolSelectionText(req)
	required := requiredToolNamesFromHistory(req)
	return selectRelevantFunctionDeclarations(declarations, query, required)
}

// selectRelevantFunctionDeclarations ranks declarations by current turn intent.
func selectRelevantFunctionDeclarations(declarations []*genai.FunctionDeclaration, query string, required map[string]bool) []*genai.FunctionDeclaration {
	ranked := make([]rankedDeclaration, 0, len(declarations))
	for index, declaration := range declarations {
		if declaration == nil || strings.TrimSpace(declaration.Name) == "" {
			continue
		}
		score := scoreFunctionDeclaration(declaration, query)
		if required[declaration.Name] {
			score += 1000
		}
		if score <= 0 {
			continue
		}
		ranked = append(ranked, rankedDeclaration{index: index, score: score, declaration: declaration})
	}
	if len(ranked) == 0 {
		return nil
	}
	sort.SliceStable(ranked, func(i int, j int) bool {
		if ranked[i].score == ranked[j].score {
			return ranked[i].index < ranked[j].index
		}
		return ranked[i].score > ranked[j].score
	})
	limit := min(len(ranked), maxGemmaToolDeclarations)
	selected := make([]*genai.FunctionDeclaration, 0, limit)
	for _, item := range ranked[:limit] {
		selected = append(selected, item.declaration)
	}
	return selected
}

// scoreFunctionDeclaration estimates whether a tool belongs in the Gemma prompt.
func scoreFunctionDeclaration(declaration *genai.FunctionDeclaration, query string) int {
	query = strings.ToLower(strings.TrimSpace(query))
	if query == "" {
		return 0
	}
	name := strings.ToLower(strings.TrimSpace(declaration.Name))
	score := 0
	if strings.Contains(query, name) {
		score += 60
	}
	score += scoreHintMatches(name, query)
	score += scoreTermMatches(query, toolSelectionText(declaration))
	if hasPhrase(query, taskIntentPhrases) {
		if name == "create_task" {
			score += 100
		}
		if name == "remember" {
			score -= 25
		}
	}
	if hasPhrase(query, memoryIntentPhrases) && !hasPhrase(query, taskIntentPhrases) && name == "remember" {
		score += 80
	}
	return score
}

// scoreHintMatches gives curated tool hints more weight than generic words.
func scoreHintMatches(name string, query string) int {
	score := 0
	for _, hint := range liteRTToolHints[name] {
		hint = strings.ToLower(strings.TrimSpace(hint))
		if hint == "" || !strings.Contains(query, hint) {
			continue
		}
		if strings.Contains(hint, " ") {
			score += 40
		} else {
			score += 20
		}
	}
	return score
}

// scoreTermMatches lightly scores natural overlap with a declaration.
func scoreTermMatches(query string, declarationText string) int {
	queryTerms := normalizedTerms(query)
	if len(queryTerms) == 0 {
		return 0
	}
	toolTerms := normalizedTerms(declarationText)
	score := 0
	for term := range queryTerms {
		if len(term) < 3 {
			continue
		}
		if toolTerms[term] {
			score++
		}
	}
	return score
}

// requestToolSelectionText extracts user-visible text for tool relevance.
func requestToolSelectionText(req *llmapi.LLMRequest) string {
	if req == nil {
		return ""
	}
	var buffer strings.Builder
	for _, content := range req.Contents {
		if content == nil || (content.Role != "" && content.Role != genai.RoleUser) {
			continue
		}
		for _, part := range content.Parts {
			if part != nil && strings.TrimSpace(part.Text) != "" {
				buffer.WriteString(part.Text)
				buffer.WriteString("\n")
			}
		}
	}
	return buffer.String()
}

// requiredToolNamesFromHistory preserves declarations for active tool loops.
func requiredToolNamesFromHistory(req *llmapi.LLMRequest) map[string]bool {
	required := map[string]bool{}
	if req == nil {
		return required
	}
	for _, content := range req.Contents {
		if content == nil {
			continue
		}
		for _, part := range content.Parts {
			if part == nil {
				continue
			}
			if part.FunctionCall != nil && strings.TrimSpace(part.FunctionCall.Name) != "" {
				required[part.FunctionCall.Name] = true
			}
			if part.FunctionResponse != nil && strings.TrimSpace(part.FunctionResponse.Name) != "" {
				required[part.FunctionResponse.Name] = true
			}
		}
	}
	return required
}

// toolSelectionText flattens a declaration into words for relevance scoring.
func toolSelectionText(declaration *genai.FunctionDeclaration) string {
	if declaration == nil {
		return ""
	}
	var buffer strings.Builder
	buffer.WriteString(strings.ReplaceAll(declaration.Name, "_", " "))
	buffer.WriteString(" ")
	buffer.WriteString(declaration.Description)
	buffer.WriteString(" ")
	appendSchemaTerms(&buffer, protocol.DeclarationParameters(declaration))
	return buffer.String()
}

// appendSchemaTerms adds schema keys and enum values to relevance text.
func appendSchemaTerms(buffer *strings.Builder, value any) {
	switch typed := value.(type) {
	case *genai.Schema:
		buffer.WriteString(fmt.Sprint(typed.Type))
		buffer.WriteString(" ")
		buffer.WriteString(typed.Description)
		buffer.WriteString(" ")
		for key, property := range typed.Properties {
			buffer.WriteString(key)
			buffer.WriteString(" ")
			appendSchemaTerms(buffer, property)
		}
		for _, item := range typed.Enum {
			buffer.WriteString(item)
			buffer.WriteString(" ")
		}
	case map[string]any:
		for key, item := range typed {
			buffer.WriteString(key)
			buffer.WriteString(" ")
			appendSchemaTerms(buffer, item)
		}
	case map[string]string:
		for key, item := range typed {
			buffer.WriteString(key)
			buffer.WriteString(" ")
			buffer.WriteString(item)
			buffer.WriteString(" ")
		}
	case []any:
		for _, item := range typed {
			appendSchemaTerms(buffer, item)
		}
	case []string:
		for _, item := range typed {
			buffer.WriteString(item)
			buffer.WriteString(" ")
		}
	case string:
		buffer.WriteString(typed)
		buffer.WriteString(" ")
	}
}

// normalizedTerms splits text into lowercase word tokens.
func normalizedTerms(text string) map[string]bool {
	terms := map[string]bool{}
	for _, term := range strings.FieldsFunc(strings.ToLower(text), func(value rune) bool {
		return !unicode.IsLetter(value) && !unicode.IsDigit(value)
	}) {
		term = strings.TrimSpace(term)
		if term != "" {
			terms[term] = true
		}
	}
	return terms
}

// hasPhrase reports whether query contains any phrase in a curated hint set.
func hasPhrase(query string, phrases []string) bool {
	for _, phrase := range phrases {
		if strings.Contains(query, phrase) {
			return true
		}
	}
	return false
}
