// This file validates shared validation assertion metadata.
package schema

import (
	"fmt"
	"regexp"
	"strings"
)

// validateValidationAssertionExpectation checks that an assertion can prove behavior.
func validateValidationAssertionExpectation(
	context string,
	id string,
	index int,
	assertion ValidationAssertion,
	assertionType string,
) error {
	switch assertionType {
	case "response-contains", "stdout-contains", "stderr-contains":
		return validateAssertionContains(context, id, index, assertion, assertionType)
	case "tool-call", "status":
		return validateAssertionNonEmptyEquals(context, id, index, assertion, assertionType)
	case "exit-code", "exit-code-not-equals", "exit-code-greater-than", "exit-code-less-than":
		return validateAssertionEquals(context, id, index, assertion, assertionType)
	case "json-path":
		return validateJSONPathAssertion(context, id, index, assertion)
	case "schema":
		return validateSchemaAssertion(context, id, index, assertion)
	default:
		return nil
	}
}

// validateAssertionContains checks text containment assertions.
func validateAssertionContains(
	context string,
	id string,
	index int,
	assertion ValidationAssertion,
	assertionType string,
) error {
	if strings.TrimSpace(assertion.Contains) == "" {
		return fmt.Errorf("%s %q assertion %d %s must set contains", context, id, index+1, assertionType)
	}
	return nil
}

// validateAssertionNonEmptyEquals checks required non-empty equality assertions.
func validateAssertionNonEmptyEquals(
	context string,
	id string,
	index int,
	assertion ValidationAssertion,
	assertionType string,
) error {
	if assertion.Equals == nil || strings.TrimSpace(fmt.Sprint(assertion.Equals)) == "" {
		return fmt.Errorf("%s %q assertion %d %s must set equals", context, id, index+1, assertionType)
	}
	return nil
}

// validateAssertionEquals checks required equality assertions.
func validateAssertionEquals(
	context string,
	id string,
	index int,
	assertion ValidationAssertion,
	assertionType string,
) error {
	if assertion.Equals == nil {
		return fmt.Errorf("%s %q assertion %d %s must set equals", context, id, index+1, assertionType)
	}
	return nil
}

// validateJSONPathAssertion checks path assertions have a path and expectation.
func validateJSONPathAssertion(
	context string,
	id string,
	index int,
	assertion ValidationAssertion,
) error {
	if strings.TrimSpace(assertion.Path) == "" {
		return fmt.Errorf("%s %q assertion %d json-path must set path", context, id, index+1)
	}
	if strings.TrimSpace(assertion.Contains) == "" &&
		strings.TrimSpace(assertion.Matches) == "" &&
		assertion.Equals == nil {
		return fmt.Errorf("%s %q assertion %d json-path must set contains, matches, or equals", context, id, index+1)
	}
	if strings.TrimSpace(assertion.Matches) != "" {
		if _, err := regexp.Compile(assertion.Matches); err != nil {
			return fmt.Errorf("%s %q assertion %d json-path matches is invalid: %w", context, id, index+1, err)
		}
	}
	return nil
}

// validateSchemaAssertion checks schema assertions carry an explicit schema.
func validateSchemaAssertion(
	context string,
	id string,
	index int,
	assertion ValidationAssertion,
) error {
	if len(assertion.Schema) == 0 {
		return fmt.Errorf("%s %q assertion %d schema must set schema", context, id, index+1)
	}
	return nil
}
