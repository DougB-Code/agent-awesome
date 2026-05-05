package query

import (
	"fmt"
	"strconv"
	"strings"

	graph "memory/internal/memory/graph/domain"
)

var unsupportedMutationKeywords = map[string]bool{
	"UPDATE": true,
	"UPSERT": true,
}

// Parse reads one graph query statement.
func Parse(input string) (Statement, error) {
	tokens, err := Lex(input)
	if err != nil {
		return Statement{}, err
	}
	parser := parser{tokens: tokens}
	return parser.statement()
}

// parser owns token cursor state for query parsing.
type parser struct {
	tokens []Token
	pos    int
}

// statement parses the supported read and mutation grammar.
func (p *parser) statement() (Statement, error) {
	if err := p.rejectUnsupportedMutationKeyword(); err != nil {
		return Statement{}, err
	}
	var stmt Statement
	var err error
	switch {
	case p.matchKeyword("FIND"):
		stmt, err = p.findStatement()
	case p.matchKeyword("MATCH"):
		stmt, err = p.matchStatement()
	case p.matchKeyword("INSERT"):
		stmt, err = p.insertStatement()
	case p.matchKeyword("SET"):
		stmt, err = p.setStatement()
	case p.matchKeyword("DELETE"):
		stmt, err = p.deleteStatement()
	default:
		return Statement{}, fmt.Errorf("expected FIND, MATCH, INSERT, SET, or DELETE")
	}
	if err != nil {
		return Statement{}, err
	}
	if !stmt.Mutating() {
		if err := p.trailingClauses(&stmt); err != nil {
			return Statement{}, err
		}
		if err := validateGroupedStatement(stmt); err != nil {
			return Statement{}, err
		}
	}
	if p.current().Type != TokenEOF {
		return Statement{}, fmt.Errorf("unexpected token %q", p.current().Value)
	}
	return stmt, nil
}

// findStatement parses the FIND node branch.
func (p *parser) findStatement() (Statement, error) {
	kindToken, err := p.expect(TokenIdentifier, "node kind")
	if err != nil {
		return Statement{}, err
	}
	kind := graph.NodeKind(strings.ToLower(kindToken.Value))
	if !graph.ValidNodeKind(kind) {
		return Statement{}, fmt.Errorf("invalid node kind %q", kindToken.Value)
	}
	return Statement{
		Mode:   StatementFind,
		Kind:   kind,
		Return: []string{"id", "title"},
		Order:  SortAscending,
		Limit:  20,
	}, nil
}

// matchStatement parses fixed or bounded MATCH edge traversal syntax.
func (p *parser) matchStatement() (Statement, error) {
	fromKind, err := p.nodeKind("from node kind")
	if err != nil {
		return Statement{}, err
	}
	if err := p.expectType(TokenDash, "-"); err != nil {
		return Statement{}, err
	}
	if err := p.expectType(TokenLeftBracket, "["); err != nil {
		return Statement{}, err
	}
	relationToken, err := p.expect(TokenIdentifier, "relation type")
	if err != nil {
		return Statement{}, err
	}
	relation := graph.RelationType(strings.ToLower(relationToken.Value))
	if !graph.ValidRelationType(relation) {
		return Statement{}, fmt.Errorf("invalid relation type %q", relationToken.Value)
	}
	minDepth, maxDepth, err := p.traversalDepth()
	if err != nil {
		return Statement{}, err
	}
	if err := p.expectType(TokenRightBracket, "]"); err != nil {
		return Statement{}, err
	}
	if err := p.expectType(TokenArrow, "->"); err != nil {
		return Statement{}, err
	}
	toKind, err := p.nodeKind("to node kind")
	if err != nil {
		return Statement{}, err
	}
	returnFields := []string{"from.id", "from.title", "edge.type", "to.id", "to.title"}
	if maxDepth > 1 {
		returnFields = []string{"from.id", "from.title", "path.depth", "to.id", "to.title"}
	}
	return Statement{
		Mode:     StatementMatch,
		FromKind: fromKind,
		Relation: relation,
		ToKind:   toKind,
		MinDepth: minDepth,
		MaxDepth: maxDepth,
		Return:   returnFields,
		Order:    SortAscending,
		Limit:    20,
	}, nil
}

// insertStatement parses INSERT NODE and INSERT EDGE mutation syntax.
func (p *parser) insertStatement() (Statement, error) {
	switch {
	case p.matchKeyword("NODE"):
		kind, err := p.nodeKind("node kind")
		if err != nil {
			return Statement{}, err
		}
		assignments, err := p.requiredSetAssignments()
		if err != nil {
			return Statement{}, err
		}
		stmt := Statement{
			Mode:   StatementInsertNode,
			Kind:   kind,
			Set:    assignments,
			Return: []string{"id", "kind", "title"},
		}
		if err := p.optionalReturn(&stmt); err != nil {
			return Statement{}, err
		}
		return stmt, nil
	case p.matchKeyword("EDGE"):
		from, err := p.nodeID("from node id")
		if err != nil {
			return Statement{}, err
		}
		if err := p.expectType(TokenDash, "-"); err != nil {
			return Statement{}, err
		}
		if err := p.expectType(TokenLeftBracket, "["); err != nil {
			return Statement{}, err
		}
		relationToken, err := p.expect(TokenIdentifier, "relation type")
		if err != nil {
			return Statement{}, err
		}
		relation := graph.RelationType(strings.ToLower(relationToken.Value))
		if !graph.ValidRelationType(relation) {
			return Statement{}, fmt.Errorf("invalid relation type %q", relationToken.Value)
		}
		if err := p.expectType(TokenRightBracket, "]"); err != nil {
			return Statement{}, err
		}
		if err := p.expectType(TokenArrow, "->"); err != nil {
			return Statement{}, err
		}
		to, err := p.nodeID("to node id")
		if err != nil {
			return Statement{}, err
		}
		assignments, err := p.optionalSetAssignments()
		if err != nil {
			return Statement{}, err
		}
		stmt := Statement{
			Mode:     StatementInsertEdge,
			FromID:   from,
			Relation: relation,
			ToID:     to,
			Set:      assignments,
			Return:   []string{"edge.id", "edge.type", "edge.from_id", "edge.to_id"},
		}
		if err := p.optionalReturn(&stmt); err != nil {
			return Statement{}, err
		}
		return stmt, nil
	default:
		return Statement{}, fmt.Errorf("expected NODE or EDGE after INSERT")
	}
}

// setStatement parses SET NODE and SET EDGE mutation syntax.
func (p *parser) setStatement() (Statement, error) {
	switch {
	case p.matchKeyword("NODE"):
		nodeID, err := p.nodeID("node id")
		if err != nil {
			return Statement{}, err
		}
		assignments, err := p.requiredSetAssignments()
		if err != nil {
			return Statement{}, err
		}
		stmt := Statement{
			Mode:   StatementSetNode,
			NodeID: nodeID,
			Set:    assignments,
			Return: []string{"id", "kind", "title"},
		}
		if err := p.optionalReturn(&stmt); err != nil {
			return Statement{}, err
		}
		return stmt, nil
	case p.matchKeyword("EDGE"):
		edgeID, err := p.edgeID("edge id")
		if err != nil {
			return Statement{}, err
		}
		assignments, err := p.requiredSetAssignments()
		if err != nil {
			return Statement{}, err
		}
		stmt := Statement{
			Mode:   StatementSetEdge,
			EdgeID: edgeID,
			Set:    assignments,
			Return: []string{"edge.id", "edge.type", "edge.status"},
		}
		if err := p.optionalReturn(&stmt); err != nil {
			return Statement{}, err
		}
		return stmt, nil
	default:
		return Statement{}, fmt.Errorf("expected NODE or EDGE after SET")
	}
}

// deleteStatement parses lifecycle-delete mutation syntax.
func (p *parser) deleteStatement() (Statement, error) {
	switch {
	case p.matchKeyword("NODE"):
		nodeID, err := p.nodeID("node id")
		if err != nil {
			return Statement{}, err
		}
		stmt := Statement{Mode: StatementDeleteNode, NodeID: nodeID, Return: []string{"id", "lifecycle_status"}}
		if err := p.optionalReturn(&stmt); err != nil {
			return Statement{}, err
		}
		return stmt, nil
	case p.matchKeyword("EDGE"):
		edgeID, err := p.edgeID("edge id")
		if err != nil {
			return Statement{}, err
		}
		stmt := Statement{Mode: StatementDeleteEdge, EdgeID: edgeID, Return: []string{"edge.id", "edge.lifecycle_status"}}
		if err := p.optionalReturn(&stmt); err != nil {
			return Statement{}, err
		}
		return stmt, nil
	default:
		return Statement{}, fmt.Errorf("expected NODE or EDGE after DELETE")
	}
}

// optionalReturn parses an optional RETURN clause for mutations.
func (p *parser) optionalReturn(stmt *Statement) error {
	if !p.matchKeyword("RETURN") {
		return nil
	}
	fields, err := p.fieldList()
	if err != nil {
		return err
	}
	stmt.Return = fields
	return nil
}

// requiredSetAssignments parses a required SET assignment list.
func (p *parser) requiredSetAssignments() ([]Assignment, error) {
	if err := p.expectKeyword("SET"); err != nil {
		return nil, err
	}
	return p.assignments()
}

// optionalSetAssignments parses an optional SET assignment list.
func (p *parser) optionalSetAssignments() ([]Assignment, error) {
	if !p.matchKeyword("SET") {
		return nil, nil
	}
	return p.assignments()
}

// assignments parses comma-separated mutation assignments.
func (p *parser) assignments() ([]Assignment, error) {
	assignments := []Assignment{}
	for {
		field, err := p.expect(TokenIdentifier, "assignment field")
		if err != nil {
			return nil, err
		}
		if err := p.expectType(TokenEqual, "="); err != nil {
			return nil, err
		}
		value, err := p.literal()
		if err != nil {
			return nil, err
		}
		assignments = append(assignments, Assignment{Field: normalizeField(field.Value), Value: value})
		if p.current().Type != TokenComma {
			break
		}
		p.pos++
	}
	return assignments, nil
}

// literal parses one mutation value literal.
func (p *parser) literal() (Literal, error) {
	token := p.current()
	switch token.Type {
	case TokenString, TokenNumber, TokenIdentifier:
		p.pos++
		return Literal{Value: token.Value, Token: token.Type}, nil
	default:
		return Literal{}, fmt.Errorf("expected assignment value, got %q", token.Value)
	}
}

// nodeID parses a graph node id literal.
func (p *parser) nodeID(label string) (graph.NodeID, error) {
	token, err := p.expect(TokenIdentifier, label)
	if err != nil {
		return "", err
	}
	return graph.NodeID(token.Value), nil
}

// edgeID parses a graph edge id literal.
func (p *parser) edgeID(label string) (graph.EdgeID, error) {
	token, err := p.expect(TokenIdentifier, label)
	if err != nil {
		return "", err
	}
	return graph.EdgeID(token.Value), nil
}

// traversalDepth parses optional variable-length traversal depth.
func (p *parser) traversalDepth() (int, int, error) {
	if !p.matchType(TokenStar) {
		return 1, 1, nil
	}
	minDepth := 1
	maxDepth := 6
	if p.current().Type == TokenNumber {
		token, err := p.expect(TokenNumber, "minimum traversal depth")
		if err != nil {
			return 0, 0, err
		}
		parsed, err := strconv.Atoi(token.Value)
		if err != nil {
			return 0, 0, fmt.Errorf("invalid traversal depth %q", token.Value)
		}
		minDepth = parsed
		maxDepth = parsed
	}
	if p.matchType(TokenRange) {
		token, err := p.expect(TokenNumber, "maximum traversal depth")
		if err != nil {
			return 0, 0, err
		}
		parsed, err := strconv.Atoi(token.Value)
		if err != nil {
			return 0, 0, fmt.Errorf("invalid traversal depth %q", token.Value)
		}
		maxDepth = parsed
	}
	if minDepth <= 0 || maxDepth < minDepth || maxDepth > 12 {
		return 0, 0, fmt.Errorf("traversal depth must be between 1 and 12")
	}
	return minDepth, maxDepth, nil
}

// trailingClauses parses shared WHERE, GROUP BY, RETURN, ORDER BY, and LIMIT clauses.
func (p *parser) trailingClauses(stmt *Statement) error {
	if p.matchKeyword("WHERE") {
		where, err := p.conditions()
		if err != nil {
			return err
		}
		stmt.Where = where
	}
	if p.matchKeyword("GROUP") {
		if err := p.expectKeyword("BY"); err != nil {
			return err
		}
		field, err := p.expect(TokenIdentifier, "group field")
		if err != nil {
			return err
		}
		stmt.GroupBy = normalizeField(field.Value)
		stmt.Return = []string{stmt.GroupBy, "count"}
	}
	if p.matchKeyword("RETURN") {
		fields, err := p.fieldList()
		if err != nil {
			return err
		}
		stmt.Return = fields
	}
	if p.matchKeyword("ORDER") {
		if err := p.expectKeyword("BY"); err != nil {
			return err
		}
		field, err := p.expect(TokenIdentifier, "order field")
		if err != nil {
			return err
		}
		stmt.OrderBy = normalizeField(field.Value)
		if p.matchKeyword("DESC") {
			stmt.Order = SortDescending
		} else {
			_ = p.matchKeyword("ASC")
			stmt.Order = SortAscending
		}
	}
	if p.matchKeyword("LIMIT") {
		limit, err := p.expect(TokenNumber, "limit")
		if err != nil {
			return err
		}
		value, err := strconv.Atoi(limit.Value)
		if err != nil {
			return fmt.Errorf("invalid limit %q", limit.Value)
		}
		if value <= 0 || value > 100 {
			return fmt.Errorf("limit must be between 1 and 100")
		}
		stmt.Limit = value
	}
	return nil
}

// validateGroupedStatement enforces the first aggregate grammar slice.
func validateGroupedStatement(stmt Statement) error {
	if stmt.GroupBy == "" {
		return nil
	}
	if stmt.GroupBy == "count" {
		return fmt.Errorf("GROUP BY count is ambiguous with the count aggregate")
	}
	for _, field := range stmt.Return {
		if field != stmt.GroupBy && field != "count" {
			return fmt.Errorf("GROUP BY queries can only RETURN %s and count", stmt.GroupBy)
		}
	}
	if stmt.OrderBy != "" && stmt.OrderBy != stmt.GroupBy && stmt.OrderBy != "count" {
		return fmt.Errorf("GROUP BY queries can only ORDER BY %s or count", stmt.GroupBy)
	}
	return nil
}

// nodeKind parses and validates a graph node kind token.
func (p *parser) nodeKind(label string) (graph.NodeKind, error) {
	token, err := p.expect(TokenIdentifier, label)
	if err != nil {
		return "", err
	}
	kind := graph.NodeKind(strings.ToLower(token.Value))
	if !graph.ValidNodeKind(kind) {
		return "", fmt.Errorf("invalid node kind %q", token.Value)
	}
	return kind, nil
}

// conditions parses comparison predicates joined by AND.
func (p *parser) conditions() ([]Condition, error) {
	conditions := []Condition{}
	for {
		field, err := p.expect(TokenIdentifier, "where field")
		if err != nil {
			return nil, err
		}
		operator, err := p.conditionOperator()
		if err != nil {
			return nil, err
		}
		value, err := p.value()
		if err != nil {
			return nil, err
		}
		conditions = append(conditions, Condition{Field: normalizeField(field.Value), Operator: operator, Value: value})
		if !p.matchKeyword("AND") {
			break
		}
	}
	return conditions, nil
}

// conditionOperator parses one supported WHERE comparison operator.
func (p *parser) conditionOperator() (ConditionOperator, error) {
	token := p.current()
	switch token.Type {
	case TokenEqual:
		p.pos++
		return OperatorEqual, nil
	case TokenNotEqual:
		p.pos++
		return OperatorNotEqual, nil
	case TokenLess:
		p.pos++
		return OperatorLessThan, nil
	case TokenLessEqual:
		p.pos++
		return OperatorLessOrEqual, nil
	case TokenGreater:
		p.pos++
		return OperatorGreaterThan, nil
	case TokenGreaterEqual:
		p.pos++
		return OperatorGreaterOrEqual, nil
	default:
		return "", fmt.Errorf("expected comparison operator, got %q", token.Value)
	}
}

// fieldList parses comma-separated return fields.
func (p *parser) fieldList() ([]string, error) {
	fields := []string{}
	for {
		field, err := p.expect(TokenIdentifier, "return field")
		if err != nil {
			return nil, err
		}
		fields = append(fields, normalizeField(field.Value))
		if p.current().Type != TokenComma {
			break
		}
		p.pos++
	}
	return fields, nil
}

// value parses a quoted or bare literal value.
func (p *parser) value() (string, error) {
	token := p.current()
	switch token.Type {
	case TokenString, TokenNumber, TokenIdentifier:
		p.pos++
		return token.Value, nil
	default:
		return "", fmt.Errorf("expected value, got %q", token.Value)
	}
}

// rejectUnsupportedMutationKeyword rejects mutation statements that are not in the mutation grammar.
func (p *parser) rejectUnsupportedMutationKeyword() error {
	token := p.current()
	if token.Type != TokenIdentifier {
		return nil
	}
	if unsupportedMutationKeywords[strings.ToUpper(token.Value)] {
		return fmt.Errorf("graph query mutation %s is not supported", strings.ToUpper(token.Value))
	}
	return nil
}

// expectKeyword consumes one required keyword.
func (p *parser) expectKeyword(keyword string) error {
	if !p.matchKeyword(keyword) {
		return fmt.Errorf("expected %s", keyword)
	}
	return nil
}

// matchKeyword consumes a keyword if present.
func (p *parser) matchKeyword(keyword string) bool {
	token := p.current()
	if token.Type != TokenIdentifier {
		return false
	}
	if strings.EqualFold(token.Value, keyword) {
		p.pos++
		return true
	}
	return false
}

// matchType consumes a token type if present.
func (p *parser) matchType(tokenType TokenType) bool {
	if p.current().Type != tokenType {
		return false
	}
	p.pos++
	return true
}

// expect consumes one token of a given type.
func (p *parser) expect(tokenType TokenType, label string) (Token, error) {
	token := p.current()
	if token.Type != tokenType {
		return Token{}, fmt.Errorf("expected %s", label)
	}
	p.pos++
	return token, nil
}

// expectType consumes one token of a given type.
func (p *parser) expectType(tokenType TokenType, label string) error {
	_, err := p.expect(tokenType, label)
	return err
}

// current returns the current token or EOF.
func (p *parser) current() Token {
	if p.pos >= len(p.tokens) {
		return Token{Type: TokenEOF}
	}
	return p.tokens[p.pos]
}

// normalizeField returns a canonical field name.
func normalizeField(field string) string {
	return strings.ToLower(strings.TrimSpace(field))
}
