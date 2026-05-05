// This file renders command lines for human review.
package commandline

import "strings"

// ReviewedCommandLine renders a shell-like command line for review prompts and
// prefix approvals.
func ReviewedCommandLine(executable string, args []string) string {
	parts := make([]string, 0, 1+len(args))
	parts = append(parts, shellQuote(executable))
	for _, arg := range args {
		parts = append(parts, shellQuote(arg))
	}
	return strings.Join(parts, " ")
}

// shellQuote quotes a command-line token when it contains shell-sensitive
// characters.
func shellQuote(value string) string {
	if value == "" {
		return "''"
	}
	if strings.ContainsAny(value, " \t\n'\"\\$`|&;<>(){}[]!*?") {
		return "'" + strings.ReplaceAll(value, "'", `'\''`) + "'"
	}
	return value
}
