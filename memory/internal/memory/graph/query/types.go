package query

import (
	"errors"
	"fmt"
	"strings"

	graph "memory/internal/memory/graph/domain"
)

// Request asks the graph query executor to evaluate one query or mutation.
type Request struct {
	Actor                string
	Query                string
	SourceNodeID         string
	Firewall             graph.Firewall
	IncludeGlobal        bool
	AllowedSensitivities []graph.Sensitivity
}

// Result stores rows returned by a graph query or mutation.
type Result struct {
	Columns []string
	Rows    []Row
	Paths   []Path
	Limit   int
	Query   string
}

// Row stores one graph query row.
type Row map[string]any

// Path stores graph path metadata associated with one result row.
type Path struct {
	RowIndex int
	Depth    int
	NodeIDs  []string
	EdgeIDs  []string
}

// StatementMode describes which graph grammar branch was parsed.
type StatementMode string

const (
	// StatementFind scans graph nodes of one kind.
	StatementFind StatementMode = "find"
	// StatementMatch scans fixed or bounded graph edge patterns.
	StatementMatch StatementMode = "match"
	// StatementInsertNode creates or upserts one graph node.
	StatementInsertNode StatementMode = "insert_node"
	// StatementInsertEdge creates or upserts one graph edge.
	StatementInsertEdge StatementMode = "insert_edge"
	// StatementSetNode updates node metadata or properties.
	StatementSetNode StatementMode = "set_node"
	// StatementSetEdge updates edge metadata or properties.
	StatementSetEdge StatementMode = "set_edge"
	// StatementDeleteNode lifecycle-deletes one graph node.
	StatementDeleteNode StatementMode = "delete_node"
	// StatementDeleteEdge lifecycle-deletes one graph edge.
	StatementDeleteEdge StatementMode = "delete_edge"
)

// Statement stores one parsed graph query or mutation.
type Statement struct {
	Mode     StatementMode
	Kind     graph.NodeKind
	FromKind graph.NodeKind
	Relation graph.RelationType
	ToKind   graph.NodeKind
	MinDepth int
	MaxDepth int
	NodeID   graph.NodeID
	EdgeID   graph.EdgeID
	FromID   graph.NodeID
	ToID     graph.NodeID
	Where    []Condition
	Set      []Assignment
	GroupBy  string
	Return   []string
	OrderBy  string
	Order    SortOrder
	Limit    int
}

// Mutating reports whether a statement writes graph state.
func (s Statement) Mutating() bool {
	switch s.Mode {
	case StatementInsertNode, StatementInsertEdge, StatementSetNode, StatementSetEdge, StatementDeleteNode, StatementDeleteEdge:
		return true
	default:
		return false
	}
}

// Condition stores one equality predicate against node metadata or properties.
type Condition struct {
	Field    string
	Operator ConditionOperator
	Value    string
}

// ConditionOperator compares a resolved field value with a literal.
type ConditionOperator string

const (
	// OperatorEqual requires exact equality.
	OperatorEqual ConditionOperator = "="
	// OperatorNotEqual requires values to differ.
	OperatorNotEqual ConditionOperator = "!="
	// OperatorLessThan requires the field to be lower than the literal.
	OperatorLessThan ConditionOperator = "<"
	// OperatorLessOrEqual requires the field to be lower than or equal to the literal.
	OperatorLessOrEqual ConditionOperator = "<="
	// OperatorGreaterThan requires the field to be greater than the literal.
	OperatorGreaterThan ConditionOperator = ">"
	// OperatorGreaterOrEqual requires the field to be greater than or equal to the literal.
	OperatorGreaterOrEqual ConditionOperator = ">="
)

// Assignment stores one mutation field assignment.
type Assignment struct {
	Field string
	Value Literal
}

// Literal stores one parsed literal with enough token context for typed writes.
type Literal struct {
	Value string
	Token TokenType
}

// SortOrder controls row ordering.
type SortOrder string

const (
	// SortAscending orders rows from low to high.
	SortAscending SortOrder = "ASC"
	// SortDescending orders rows from high to low.
	SortDescending SortOrder = "DESC"
)

// TokenType classifies one lexical token.
type TokenType string

const (
	// TokenEOF marks the end of input.
	TokenEOF TokenType = "eof"
	// TokenIdentifier stores field names, keywords, and vocabulary keys.
	TokenIdentifier TokenType = "identifier"
	// TokenString stores a quoted string literal.
	TokenString TokenType = "string"
	// TokenNumber stores an integer number literal.
	TokenNumber TokenType = "number"
	// TokenComma stores a comma separator.
	TokenComma TokenType = "comma"
	// TokenEqual stores an equality operator.
	TokenEqual TokenType = "equal"
	// TokenNotEqual stores an inequality operator.
	TokenNotEqual TokenType = "not_equal"
	// TokenLess stores a less-than comparison operator.
	TokenLess TokenType = "less"
	// TokenLessEqual stores a less-than-or-equal comparison operator.
	TokenLessEqual TokenType = "less_equal"
	// TokenGreater stores a greater-than comparison operator.
	TokenGreater TokenType = "greater"
	// TokenGreaterEqual stores a greater-than-or-equal comparison operator.
	TokenGreaterEqual TokenType = "greater_equal"
	// TokenLeftBracket stores an edge pattern opening bracket.
	TokenLeftBracket TokenType = "left_bracket"
	// TokenRightBracket stores an edge pattern closing bracket.
	TokenRightBracket TokenType = "right_bracket"
	// TokenDash stores a pattern dash.
	TokenDash TokenType = "dash"
	// TokenArrow stores a directed pattern arrow.
	TokenArrow TokenType = "arrow"
	// TokenStar stores a variable-length traversal marker.
	TokenStar TokenType = "star"
	// TokenRange stores a traversal range separator.
	TokenRange TokenType = "range"
)

// Token stores one lexer output item.
type Token struct {
	Type  TokenType
	Value string
}

// normalizeRequest validates shared graph query request metadata.
func normalizeRequest(req Request) (Request, error) {
	req.Actor = defaultString(req.Actor, "agent")
	req.Query = strings.TrimSpace(req.Query)
	req.SourceNodeID = strings.TrimSpace(req.SourceNodeID)
	if req.Query == "" {
		return req, errors.New("query is required")
	}
	if req.Firewall == "" {
		req.Firewall = graph.FirewallUser
	}
	if !graph.ValidFirewall(req.Firewall) {
		return req, fmt.Errorf("invalid firewall %q", req.Firewall)
	}
	if len(req.AllowedSensitivities) == 0 {
		req.AllowedSensitivities = []graph.Sensitivity{graph.SensitivityPublic, graph.SensitivityInternal, graph.SensitivityPrivate}
	}
	for _, sensitivity := range req.AllowedSensitivities {
		if !graph.ValidSensitivity(sensitivity) {
			return req, fmt.Errorf("invalid sensitivity %q", sensitivity)
		}
	}
	return req, nil
}

// defaultString returns fallback when value is blank after trimming.
func defaultString(value string, fallback string) string {
	if trimmed := strings.TrimSpace(value); trimmed != "" {
		return trimmed
	}
	return fallback
}
