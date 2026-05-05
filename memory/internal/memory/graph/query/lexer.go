package query

import (
	"fmt"
	"strings"
	"unicode"
)

// Lex tokenizes a graph query or mutation.
func Lex(input string) ([]Token, error) {
	lexer := lexer{input: []rune(input)}
	return lexer.tokens()
}

// lexer owns rune scanning state for query tokenization.
type lexer struct {
	input []rune
	pos   int
}

// tokens returns all tokens plus an EOF marker.
func (l *lexer) tokens() ([]Token, error) {
	tokens := []Token{}
	for {
		l.skipSpace()
		if l.done() {
			tokens = append(tokens, Token{Type: TokenEOF})
			return tokens, nil
		}
		ch := l.peek()
		switch {
		case ch == ',':
			l.pos++
			tokens = append(tokens, Token{Type: TokenComma, Value: ","})
		case ch == '=':
			l.pos++
			tokens = append(tokens, Token{Type: TokenEqual, Value: "="})
		case ch == '!' && l.nextIs('='):
			l.pos += 2
			tokens = append(tokens, Token{Type: TokenNotEqual, Value: "!="})
		case ch == '<' && l.nextIs('='):
			l.pos += 2
			tokens = append(tokens, Token{Type: TokenLessEqual, Value: "<="})
		case ch == '<' && l.nextIs('>'):
			l.pos += 2
			tokens = append(tokens, Token{Type: TokenNotEqual, Value: "<>"})
		case ch == '<':
			l.pos++
			tokens = append(tokens, Token{Type: TokenLess, Value: "<"})
		case ch == '>' && l.nextIs('='):
			l.pos += 2
			tokens = append(tokens, Token{Type: TokenGreaterEqual, Value: ">="})
		case ch == '>':
			l.pos++
			tokens = append(tokens, Token{Type: TokenGreater, Value: ">"})
		case ch == '.' && l.nextIs('.'):
			l.pos += 2
			tokens = append(tokens, Token{Type: TokenRange, Value: ".."})
		case ch == '[':
			l.pos++
			tokens = append(tokens, Token{Type: TokenLeftBracket, Value: "["})
		case ch == ']':
			l.pos++
			tokens = append(tokens, Token{Type: TokenRightBracket, Value: "]"})
		case ch == '-' && l.nextIs('>'):
			l.pos += 2
			tokens = append(tokens, Token{Type: TokenArrow, Value: "->"})
		case ch == '-':
			l.pos++
			tokens = append(tokens, Token{Type: TokenDash, Value: "-"})
		case ch == '*':
			l.pos++
			tokens = append(tokens, Token{Type: TokenStar, Value: "*"})
		case ch == '"':
			value, err := l.string()
			if err != nil {
				return nil, err
			}
			tokens = append(tokens, Token{Type: TokenString, Value: value})
		case unicode.IsDigit(ch):
			tokens = append(tokens, Token{Type: TokenNumber, Value: l.number()})
		case identifierRune(ch):
			tokens = append(tokens, Token{Type: TokenIdentifier, Value: l.identifier()})
		default:
			return nil, fmt.Errorf("unexpected query character %q", ch)
		}
	}
}

// skipSpace advances over whitespace.
func (l *lexer) skipSpace() {
	for !l.done() && unicode.IsSpace(l.peek()) {
		l.pos++
	}
}

// string reads a double-quoted string literal.
func (l *lexer) string() (string, error) {
	l.pos++
	var builder strings.Builder
	for !l.done() {
		ch := l.peek()
		l.pos++
		if ch == '"' {
			return builder.String(), nil
		}
		if ch == '\\' {
			if l.done() {
				return "", fmt.Errorf("unterminated string escape")
			}
			escaped := l.peek()
			l.pos++
			switch escaped {
			case '"', '\\':
				builder.WriteRune(escaped)
			case 'n':
				builder.WriteRune('\n')
			case 't':
				builder.WriteRune('\t')
			default:
				return "", fmt.Errorf("unsupported string escape \\%c", escaped)
			}
			continue
		}
		builder.WriteRune(ch)
	}
	return "", fmt.Errorf("unterminated string literal")
}

// number reads an unsigned integer or decimal literal.
func (l *lexer) number() string {
	start := l.pos
	for !l.done() && unicode.IsDigit(l.peek()) {
		l.pos++
	}
	if !l.done() && l.peek() == '.' && !l.nextIs('.') {
		l.pos++
		for !l.done() && unicode.IsDigit(l.peek()) {
			l.pos++
		}
	}
	return string(l.input[start:l.pos])
}

// identifier reads a keyword, field, or vocabulary identifier.
func (l *lexer) identifier() string {
	start := l.pos
	for !l.done() && identifierRune(l.peek()) {
		l.pos++
	}
	return string(l.input[start:l.pos])
}

// done reports whether scanning has reached the end.
func (l *lexer) done() bool {
	return l.pos >= len(l.input)
}

// peek returns the current rune.
func (l *lexer) peek() rune {
	return l.input[l.pos]
}

// nextIs reports whether the next rune after the current position matches.
func (l *lexer) nextIs(ch rune) bool {
	return l.pos+1 < len(l.input) && l.input[l.pos+1] == ch
}

// identifierRune reports whether a rune can appear in an identifier.
func identifierRune(ch rune) bool {
	return unicode.IsLetter(ch) || unicode.IsDigit(ch) || ch == '_' || ch == '-' || ch == '.'
}
