// This file defines and executes the AA Mapping Spec.
package mapping

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"

	"agentawesome/internal/services/workflow/envelope"
	workflowexpr "agentawesome/internal/services/workflow/expr"
	"agentawesome/internal/services/workflow/jsondata"
)

const (
	mappingAPIVersion = "aa.mapping/v1"
	mappingKind       = "Mapping"
)

var exprPathPattern = regexp.MustCompile(`(?:input|output)(?:\.[A-Za-z_][A-Za-z0-9_]*|\[['"][^'"]+['"]\]|\[[0-9]+\])+`)

// Spec is the authoritative declarative mapping artifact.
type Spec struct {
	APIVersion string           `json:"apiVersion,omitempty" yaml:"apiVersion,omitempty"`
	Kind       string           `json:"kind,omitempty" yaml:"kind,omitempty"`
	Name       string           `json:"name,omitempty" yaml:"name,omitempty"`
	Input      IOContract       `json:"input,omitempty" yaml:"input,omitempty"`
	Output     IOContract       `json:"output,omitempty" yaml:"output,omitempty"`
	Steps      []StepDefinition `json:"steps,omitempty" yaml:"steps,omitempty"`
	Validate   []ValidationRule `json:"validate,omitempty" yaml:"validate,omitempty"`
}

// IOContract stores mapping-side expected and produced facets.
type IOContract struct {
	Expects  ShapeContract `json:"expects,omitempty" yaml:"expects,omitempty"`
	Produces ShapeContract `json:"produces,omitempty" yaml:"produces,omitempty"`
}

// ShapeContract describes an envelope shape used by a mapping.
type ShapeContract struct {
	Kind   string   `json:"kind,omitempty" yaml:"kind,omitempty"`
	Facets []string `json:"facets,omitempty" yaml:"facets,omitempty"`
}

// StepDefinition stores one mutually exclusive mapping step.
type StepDefinition struct {
	Set       *SetStep       `json:"set,omitempty" yaml:"set,omitempty"`
	Default   *DefaultStep   `json:"default,omitempty" yaml:"default,omitempty"`
	Foreach   *ForeachStep   `json:"foreach,omitempty" yaml:"foreach,omitempty"`
	Aggregate *AggregateStep `json:"aggregate,omitempty" yaml:"aggregate,omitempty"`
	GroupBy   *GroupByStep   `json:"groupBy,omitempty" yaml:"groupBy,omitempty"`
}

// SetStep writes a value into the output body and facets.
type SetStep struct {
	Target string    `json:"target" yaml:"target"`
	When   *WhenRule `json:"when,omitempty" yaml:"when,omitempty"`
	Value  ValueSpec `json:"value" yaml:"value"`
}

// DefaultStep writes a fallback value when the target is empty.
type DefaultStep struct {
	Target string `json:"target" yaml:"target"`
	Value  any    `json:"value" yaml:"value"`
}

// ForeachStep maps every item from a source list into a target list.
type ForeachStep struct {
	Source string               `json:"source" yaml:"source"`
	As     string               `json:"as,omitempty" yaml:"as,omitempty"`
	Target string               `json:"target" yaml:"target"`
	Map    map[string]ValueSpec `json:"map" yaml:"map"`
}

// AggregateStep calculates a scalar from a list.
type AggregateStep struct {
	Source string `json:"source" yaml:"source"`
	Target string `json:"target" yaml:"target"`
	Op     string `json:"op" yaml:"op"`
	Expr   string `json:"expr,omitempty" yaml:"expr,omitempty"`
}

// GroupByStep groups list items by a deterministic key expression.
type GroupByStep struct {
	Source     string                   `json:"source" yaml:"source"`
	Key        ValueSpec                `json:"key" yaml:"key"`
	Target     string                   `json:"target" yaml:"target"`
	Aggregates map[string]AggregateStep `json:"aggregates,omitempty" yaml:"aggregates,omitempty"`
}

// ValueSpec describes how a mapping value is obtained.
type ValueSpec struct {
	Path    string       `json:"path,omitempty" yaml:"path,omitempty"`
	Expr    string       `json:"expr,omitempty" yaml:"expr,omitempty"`
	Extract *ExtractSpec `json:"extract,omitempty" yaml:"extract,omitempty"`
	Value   any          `json:"value,omitempty" yaml:"value,omitempty"`
}

// ExtractSpec extracts a regex capture group from text.
type ExtractSpec struct {
	From    string `json:"from" yaml:"from"`
	Pattern string `json:"pattern" yaml:"pattern"`
	Group   int    `json:"group,omitempty" yaml:"group,omitempty"`
	Cast    string `json:"cast,omitempty" yaml:"cast,omitempty"`
}

// WhenRule controls conditional step execution.
type WhenRule struct {
	Expr string `json:"expr,omitempty" yaml:"expr,omitempty"`
	Path string `json:"path,omitempty" yaml:"path,omitempty"`
}

// ValidationRule checks a post-mapping output invariant.
type ValidationRule struct {
	Expr    string `json:"expr" yaml:"expr"`
	Message string `json:"message" yaml:"message"`
}

// PreviewResult reports a mapping preview with static and runtime diagnostics.
type PreviewResult struct {
	Output        envelope.Envelope     `json:"output"`
	Diagnostics   []envelope.Diagnostic `json:"diagnostics,omitempty"`
	RequiredPaths []string              `json:"required_paths,omitempty"`
	ProducedPaths []string              `json:"produced_paths,omitempty"`
}

// Validate checks one mapping spec for static authoring errors.
func Validate(spec Spec) []envelope.Diagnostic {
	var diagnostics []envelope.Diagnostic
	if strings.TrimSpace(spec.APIVersion) != "" && strings.TrimSpace(spec.APIVersion) != mappingAPIVersion {
		diagnostics = append(diagnostics, mappingDiagnostic("error", "mapping_api_version", "apiVersion", "mapping apiVersion must be "+mappingAPIVersion))
	}
	if strings.TrimSpace(spec.Kind) != "" && strings.TrimSpace(spec.Kind) != mappingKind {
		diagnostics = append(diagnostics, mappingDiagnostic("error", "mapping_kind", "kind", "mapping kind must be "+mappingKind))
	}
	if len(spec.Steps) == 0 {
		diagnostics = append(diagnostics, mappingDiagnostic("error", "mapping_steps_required", "steps", "mapping must declare at least one step"))
	}
	for index, step := range spec.Steps {
		diagnostics = append(diagnostics, validateStep(index, step)...)
	}
	for index, rule := range spec.Validate {
		path := fmt.Sprintf("validate.%d", index)
		if strings.TrimSpace(rule.Expr) == "" {
			diagnostics = append(diagnostics, mappingDiagnostic("error", "mapping_validation_expr_required", path+".expr", "validation expression is required"))
		}
	}
	return diagnostics
}

// RequiredPaths returns input paths and facets referenced by a mapping.
func RequiredPaths(spec Spec) []string {
	paths := orderedSet{}
	for _, facet := range spec.Input.Expects.Facets {
		paths.add("input.facets." + strings.TrimSpace(facet))
	}
	if strings.TrimSpace(spec.Input.Expects.Kind) != "" {
		paths.add("input.body.kind")
	}
	for _, step := range spec.Steps {
		collectStepRequiredPaths(step, &paths)
	}
	for _, rule := range spec.Validate {
		collectExprInputPaths(rule.Expr, &paths)
	}
	return paths.values
}

// ProducedPaths returns output targets written by a mapping.
func ProducedPaths(spec Spec) []string {
	paths := orderedSet{}
	for _, facet := range spec.Output.Produces.Facets {
		paths.add("output.facets." + strings.TrimSpace(facet))
	}
	if strings.TrimSpace(spec.Output.Produces.Kind) != "" {
		paths.add("output.body.kind")
	}
	for _, step := range spec.Steps {
		collectStepProducedPaths(step, &paths)
	}
	return paths.values
}

// Preview validates and executes a mapping against sample input data.
func Preview(spec Spec, input envelope.Envelope) PreviewResult {
	diagnostics := Validate(spec)
	output, runtimeDiagnostics := Apply(spec, input)
	diagnostics = append(diagnostics, runtimeDiagnostics...)
	return PreviewResult{
		Output:        output,
		Diagnostics:   diagnostics,
		RequiredPaths: RequiredPaths(spec),
		ProducedPaths: ProducedPaths(spec),
	}
}

// validateStep checks that one mapping step is deterministic and complete.
func validateStep(index int, step StepDefinition) []envelope.Diagnostic {
	path := fmt.Sprintf("steps.%d", index)
	ops := 0
	if step.Set != nil {
		ops++
	}
	if step.Default != nil {
		ops++
	}
	if step.Foreach != nil {
		ops++
	}
	if step.Aggregate != nil {
		ops++
	}
	if step.GroupBy != nil {
		ops++
	}
	if ops != 1 {
		return []envelope.Diagnostic{mappingDiagnostic("error", "mapping_step_operation", path, "mapping step must declare exactly one operation")}
	}
	var diagnostics []envelope.Diagnostic
	if step.Set != nil {
		diagnostics = append(diagnostics, validateTarget(path+".set.target", step.Set.Target)...)
		diagnostics = append(diagnostics, validateWhen(path+".set.when", step.Set.When)...)
		diagnostics = append(diagnostics, validateValueSpec(path+".set.value", step.Set.Value)...)
	}
	if step.Default != nil {
		diagnostics = append(diagnostics, validateTarget(path+".default.target", step.Default.Target)...)
	}
	if step.Foreach != nil {
		diagnostics = append(diagnostics, validateSource(path+".foreach.source", step.Foreach.Source)...)
		diagnostics = append(diagnostics, validateTarget(path+".foreach.target", step.Foreach.Target)...)
		if len(step.Foreach.Map) == 0 {
			diagnostics = append(diagnostics, mappingDiagnostic("error", "mapping_foreach_map_required", path+".foreach.map", "foreach map must declare output fields"))
		}
		for name, value := range step.Foreach.Map {
			diagnostics = append(diagnostics, validateValueSpec(path+".foreach.map."+name, value)...)
		}
	}
	if step.Aggregate != nil {
		diagnostics = append(diagnostics, validateAggregate(path+".aggregate", *step.Aggregate)...)
	}
	if step.GroupBy != nil {
		diagnostics = append(diagnostics, validateSource(path+".groupBy.source", step.GroupBy.Source)...)
		diagnostics = append(diagnostics, validateTarget(path+".groupBy.target", step.GroupBy.Target)...)
		diagnostics = append(diagnostics, validateValueSpec(path+".groupBy.key", step.GroupBy.Key)...)
		if len(step.GroupBy.Aggregates) == 0 {
			diagnostics = append(diagnostics, mappingDiagnostic("error", "mapping_group_aggregates_required", path+".groupBy.aggregates", "groupBy must declare aggregates"))
		}
		for name, aggregate := range step.GroupBy.Aggregates {
			diagnostics = append(diagnostics, validateAggregate(path+".groupBy.aggregates."+name, aggregate)...)
		}
	}
	return diagnostics
}

// validateAggregate checks aggregate target, source, and operation.
func validateAggregate(path string, step AggregateStep) []envelope.Diagnostic {
	var diagnostics []envelope.Diagnostic
	diagnostics = append(diagnostics, validateSource(path+".source", step.Source)...)
	diagnostics = append(diagnostics, validateTarget(path+".target", step.Target)...)
	switch strings.ToLower(strings.TrimSpace(step.Op)) {
	case "count", "sum":
	default:
		diagnostics = append(diagnostics, mappingDiagnostic("error", "mapping_aggregate_op", path+".op", "aggregate op must be count or sum"))
	}
	return diagnostics
}

// validateSource checks a mapping source path.
func validateSource(path string, value string) []envelope.Diagnostic {
	if strings.TrimSpace(value) == "" {
		return []envelope.Diagnostic{mappingDiagnostic("error", "mapping_source_required", path, "source path is required")}
	}
	return nil
}

// validateTarget checks a mapping target path.
func validateTarget(path string, value string) []envelope.Diagnostic {
	if strings.TrimSpace(value) == "" {
		return []envelope.Diagnostic{mappingDiagnostic("error", "mapping_target_required", path, "target path is required")}
	}
	return nil
}

// validateWhen checks an optional conditional rule.
func validateWhen(path string, rule *WhenRule) []envelope.Diagnostic {
	if rule == nil {
		return nil
	}
	if strings.TrimSpace(rule.Expr) == "" && strings.TrimSpace(rule.Path) == "" {
		return []envelope.Diagnostic{mappingDiagnostic("error", "mapping_when_required", path, "when must declare expr or path")}
	}
	return nil
}

// validateValueSpec checks a value source declaration.
func validateValueSpec(path string, spec ValueSpec) []envelope.Diagnostic {
	var diagnostics []envelope.Diagnostic
	if strings.TrimSpace(spec.Path) != "" && strings.TrimSpace(spec.Expr) != "" {
		diagnostics = append(diagnostics, mappingDiagnostic("error", "mapping_value_ambiguous", path, "value must not declare both path and expr"))
	}
	if spec.Extract != nil {
		if strings.TrimSpace(spec.Path) != "" || strings.TrimSpace(spec.Expr) != "" {
			diagnostics = append(diagnostics, mappingDiagnostic("error", "mapping_value_ambiguous", path, "extract must be the only dynamic value source"))
		}
		if strings.TrimSpace(spec.Extract.From) == "" {
			diagnostics = append(diagnostics, mappingDiagnostic("error", "mapping_extract_source_required", path+".extract.from", "extract source is required"))
		}
		if strings.TrimSpace(spec.Extract.Pattern) == "" {
			diagnostics = append(diagnostics, mappingDiagnostic("error", "mapping_extract_pattern_required", path+".extract.pattern", "extract pattern is required"))
		} else if _, err := regexp.Compile(spec.Extract.Pattern); err != nil {
			diagnostics = append(diagnostics, mappingDiagnostic("error", "mapping_extract_pattern", path+".extract.pattern", err.Error()))
		}
	}
	return diagnostics
}

// collectStepRequiredPaths appends input dependencies from one mapping step.
func collectStepRequiredPaths(step StepDefinition, paths *orderedSet) {
	if step.Set != nil {
		if step.Set.When != nil {
			paths.add(normalizePath(step.Set.When.Path))
			collectExprInputPaths(step.Set.When.Expr, paths)
		}
		collectValueSpecRequiredPaths(step.Set.Value, paths)
	}
	if step.Foreach != nil {
		paths.add(normalizePath(step.Foreach.Source))
		for _, value := range step.Foreach.Map {
			collectValueSpecRequiredPaths(value, paths)
		}
	}
	if step.Aggregate != nil {
		paths.add(normalizePath(step.Aggregate.Source))
		collectExprInputPaths(step.Aggregate.Expr, paths)
	}
	if step.GroupBy != nil {
		paths.add(normalizePath(step.GroupBy.Source))
		collectValueSpecRequiredPaths(step.GroupBy.Key, paths)
		for _, aggregate := range step.GroupBy.Aggregates {
			paths.add(normalizePath(aggregate.Source))
			collectExprInputPaths(aggregate.Expr, paths)
		}
	}
}

// collectValueSpecRequiredPaths appends input dependencies from a value spec.
func collectValueSpecRequiredPaths(spec ValueSpec, paths *orderedSet) {
	paths.add(normalizePath(spec.Path))
	collectExprInputPaths(spec.Expr, paths)
	if spec.Extract != nil {
		paths.add(normalizePath(spec.Extract.From))
	}
}

// collectExprInputPaths appends input paths referenced by an expression.
func collectExprInputPaths(expr string, paths *orderedSet) {
	for _, match := range exprPathPattern.FindAllString(strings.TrimSpace(expr), -1) {
		normalized := normalizePath(match)
		if strings.HasPrefix(normalized, "input.") {
			paths.add(normalized)
		}
	}
}

// collectStepProducedPaths appends output paths written by one mapping step.
func collectStepProducedPaths(step StepDefinition, paths *orderedSet) {
	if step.Set != nil {
		paths.add(normalizeOutputTarget(step.Set.Target))
	}
	if step.Default != nil {
		paths.add(normalizeOutputTarget(step.Default.Target))
	}
	if step.Foreach != nil {
		paths.add(normalizeOutputTarget(step.Foreach.Target))
	}
	if step.Aggregate != nil {
		paths.add(normalizeOutputTarget(step.Aggregate.Target))
	}
	if step.GroupBy != nil {
		paths.add(normalizeOutputTarget(step.GroupBy.Target))
	}
}

// normalizeOutputTarget returns the canonical output path for a mapping target.
func normalizeOutputTarget(target string) string {
	trimmed := strings.TrimSpace(target)
	if trimmed == "" {
		return ""
	}
	if strings.HasPrefix(trimmed, "output.") {
		return trimmed
	}
	return "output.body.value." + trimmed
}

// normalizePath returns a static dotted path for dependency reporting.
func normalizePath(path string) string {
	trimmed := strings.TrimSpace(path)
	if trimmed == "" {
		return ""
	}
	trimmed = strings.ReplaceAll(trimmed, `["`, ".")
	trimmed = strings.ReplaceAll(trimmed, `['`, ".")
	trimmed = strings.ReplaceAll(trimmed, `"]`, "")
	trimmed = strings.ReplaceAll(trimmed, `']`, "")
	trimmed = strings.ReplaceAll(trimmed, "[", ".")
	trimmed = strings.ReplaceAll(trimmed, "]", "")
	return strings.Trim(trimmed, ".")
}

// mappingDiagnostic builds a mapping diagnostic.
func mappingDiagnostic(severity string, code string, path string, message string) envelope.Diagnostic {
	return envelope.Diagnostic{
		Severity: severity,
		Code:     code,
		Path:     path,
		Message:  message,
	}
}

// orderedSet stores unique paths while preserving first-seen order.
type orderedSet struct {
	values []string
	seen   map[string]struct{}
}

// add records one non-empty value once.
func (s *orderedSet) add(value string) {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return
	}
	if s.seen == nil {
		s.seen = map[string]struct{}{}
	}
	if _, ok := s.seen[trimmed]; ok {
		return
	}
	s.seen[trimmed] = struct{}{}
	s.values = append(s.values, trimmed)
}

// Apply executes a mapping spec against one input envelope.
func Apply(spec Spec, input envelope.Envelope) (envelope.Envelope, []envelope.Diagnostic) {
	input.Normalize()
	output := envelope.New(input.Meta.WorkflowRunID, "", input.Meta.Attempt, map[string]any{})
	output.Control.Status = input.Control.Status
	output.Meta.CausationID = input.Meta.NodeRunID
	ctx := newEvalContext(input, output, nil)
	var diagnostics []envelope.Diagnostic
	for _, step := range spec.Steps {
		if err := applyStep(step, ctx); err != nil {
			diagnostics = append(diagnostics, envelope.Diagnostic{Severity: "error", Code: "mapping_step_failed", Message: err.Error()})
		}
	}
	for _, rule := range spec.Validate {
		ok, err := evalBool(rule.Expr, ctx)
		if err != nil {
			diagnostics = append(diagnostics, envelope.Diagnostic{Severity: "error", Code: "mapping_validation_error", Message: err.Error()})
			continue
		}
		if !ok {
			message := strings.TrimSpace(rule.Message)
			if message == "" {
				message = "mapping validation failed"
			}
			diagnostics = append(diagnostics, envelope.Diagnostic{Severity: "error", Code: "mapping_validation_failed", Message: message})
		}
	}
	result := *ctx.output
	result.Diagnostics = append(result.Diagnostics, diagnostics...)
	result.Normalize()
	return result, diagnostics
}

// applyStep dispatches one mapping step to its implementation.
func applyStep(step StepDefinition, ctx *evalContext) error {
	switch {
	case step.Set != nil:
		return applySet(*step.Set, ctx)
	case step.Default != nil:
		return applyDefault(*step.Default, ctx)
	case step.Foreach != nil:
		return applyForeach(*step.Foreach, ctx)
	case step.Aggregate != nil:
		return applyAggregate(*step.Aggregate, ctx)
	case step.GroupBy != nil:
		return applyGroupBy(*step.GroupBy, ctx)
	default:
		return fmt.Errorf("mapping step must declare one operation")
	}
}

// applySet writes one calculated value.
func applySet(step SetStep, ctx *evalContext) error {
	if step.When != nil {
		ok, err := evalWhen(*step.When, ctx)
		if err != nil || !ok {
			return err
		}
	}
	value, err := evalValue(step.Value, ctx)
	if err != nil {
		return err
	}
	setTarget(ctx.output, step.Target, value)
	return nil
}

// applyDefault writes a fallback when a target has no value.
func applyDefault(step DefaultStep, ctx *evalContext) error {
	if current, ok := targetValue(ctx.output, step.Target); ok && !isEmpty(current) {
		return nil
	}
	setTarget(ctx.output, step.Target, step.Value)
	return nil
}

// applyForeach maps list items into a target list.
func applyForeach(step ForeachStep, ctx *evalContext) error {
	value, ok := resolvePath(step.Source, ctx)
	if !ok {
		return fmt.Errorf("foreach source %q was not found", step.Source)
	}
	items, ok := value.([]any)
	if !ok {
		return fmt.Errorf("foreach source %q must be an array", step.Source)
	}
	alias := strings.TrimSpace(step.As)
	if alias == "" {
		alias = "item"
	}
	results := make([]any, 0, len(items))
	for _, item := range items {
		itemCtx := ctx.withLocal(alias, item)
		row := map[string]any{}
		for name, valueSpec := range step.Map {
			value, err := evalValue(valueSpec, itemCtx)
			if err != nil {
				return err
			}
			row[name] = value
		}
		results = append(results, row)
	}
	setTarget(ctx.output, step.Target, results)
	return nil
}

// applyAggregate calculates one aggregate result.
func applyAggregate(step AggregateStep, ctx *evalContext) error {
	result, err := aggregate(step, ctx)
	if err != nil {
		return err
	}
	setTarget(ctx.output, step.Target, result)
	return nil
}

// applyGroupBy creates grouped aggregate records.
func applyGroupBy(step GroupByStep, ctx *evalContext) error {
	value, ok := resolvePath(step.Source, ctx)
	if !ok {
		return fmt.Errorf("groupBy source %q was not found", step.Source)
	}
	items, ok := value.([]any)
	if !ok {
		return fmt.Errorf("groupBy source %q must be an array", step.Source)
	}
	groups := map[string][]any{}
	for _, item := range items {
		keyValue, err := evalValue(step.Key, ctx.withLocal("item", item))
		if err != nil {
			return err
		}
		groups[fmt.Sprint(keyValue)] = append(groups[fmt.Sprint(keyValue)], item)
	}
	out := map[string]any{}
	for key, groupItems := range groups {
		groupCtx := ctx.withLocal("items", groupItems)
		groupRecord := map[string]any{}
		for name, aggregateStep := range step.Aggregates {
			aggregateStep.Source = "items"
			value, err := aggregate(aggregateStep, groupCtx)
			if err != nil {
				return err
			}
			groupRecord[name] = value
		}
		out[key] = groupRecord
	}
	setTarget(ctx.output, step.Target, out)
	return nil
}

// aggregate calculates count or sum over a list.
func aggregate(step AggregateStep, ctx *evalContext) (any, error) {
	value, ok := resolvePath(step.Source, ctx)
	if !ok {
		return nil, fmt.Errorf("aggregate source %q was not found", step.Source)
	}
	items, ok := value.([]any)
	if !ok {
		return nil, fmt.Errorf("aggregate source %q must be an array", step.Source)
	}
	switch strings.ToLower(strings.TrimSpace(step.Op)) {
	case "count":
		return len(items), nil
	case "sum":
		var total float64
		for _, item := range items {
			itemCtx := ctx.withLocal("item", item)
			var value any = item
			var err error
			if strings.TrimSpace(step.Expr) != "" {
				value, err = evalExpr(step.Expr, itemCtx)
				if err != nil {
					return nil, err
				}
			}
			number, ok := numeric(value)
			if !ok {
				return nil, fmt.Errorf("aggregate sum expression returned non-number %v", value)
			}
			total += number
		}
		return total, nil
	default:
		return nil, fmt.Errorf("aggregate op %q is unsupported", step.Op)
	}
}

// evalValue resolves a mapping value specification.
func evalValue(spec ValueSpec, ctx *evalContext) (any, error) {
	switch {
	case strings.TrimSpace(spec.Path) != "":
		if value, ok := resolvePath(spec.Path, ctx); ok {
			return value, nil
		}
		return nil, fmt.Errorf("path %q was not found", spec.Path)
	case strings.TrimSpace(spec.Expr) != "":
		return evalExpr(spec.Expr, ctx)
	case spec.Extract != nil:
		return evalExtract(*spec.Extract, ctx)
	default:
		return spec.Value, nil
	}
}

// evalExtract applies a regex extraction value.
func evalExtract(spec ExtractSpec, ctx *evalContext) (any, error) {
	source, ok := resolvePath(spec.From, ctx)
	if !ok {
		return nil, fmt.Errorf("extract source %q was not found", spec.From)
	}
	re, err := regexp.Compile(spec.Pattern)
	if err != nil {
		return nil, fmt.Errorf("extract pattern: %w", err)
	}
	matches := re.FindStringSubmatch(fmt.Sprint(source))
	if len(matches) == 0 {
		return nil, nil
	}
	group := spec.Group
	if group <= 0 {
		group = 1
	}
	if group >= len(matches) {
		return nil, fmt.Errorf("extract group %d missing", group)
	}
	return cast(matches[group], spec.Cast)
}

// evalWhen evaluates one conditional rule.
func evalWhen(rule WhenRule, ctx *evalContext) (bool, error) {
	if strings.TrimSpace(rule.Expr) != "" {
		return evalBool(rule.Expr, ctx)
	}
	if strings.TrimSpace(rule.Path) != "" {
		value, ok := resolvePath(rule.Path, ctx)
		return ok && !isEmpty(value), nil
	}
	return true, nil
}

// evalBool evaluates a CEL boolean expression.
func evalBool(expr string, ctx *evalContext) (bool, error) {
	value, err := evalExpr(expr, ctx)
	if err != nil {
		return false, err
	}
	boolValue, ok := value.(bool)
	if ok {
		return boolValue, nil
	}
	return workflowexpr.Truthy(value), nil
}

// evalExpr evaluates a deterministic CEL expression.
func evalExpr(expr string, ctx *evalContext) (any, error) {
	return evalCELExpr(expr, ctx)
}

// evalCELExpr evaluates an expression with CEL and JSON-like variables.
func evalCELExpr(expression string, ctx *evalContext) (any, error) {
	return workflowexpr.Evaluate(expression, workflowexpr.VariablesFromEnvelopes(ctx.input, *ctx.output, ctx.locals))
}

// resolvePath resolves a dotted path from input, output, or locals.
func resolvePath(path string, ctx *evalContext) (any, bool) {
	trimmed := strings.TrimSpace(path)
	if trimmed == "" {
		return nil, false
	}
	if value, ok := ctx.locals[trimmed]; ok {
		return value, true
	}
	switch {
	case strings.HasPrefix(trimmed, "input.facets."):
		key := strings.TrimPrefix(trimmed, "input.facets.")
		return facetOrPath(ctx.input.Facets, key)
	case strings.HasPrefix(trimmed, "output.facets."):
		key := strings.TrimPrefix(trimmed, "output.facets.")
		return facetOrPath(ctx.output.Facets, key)
	case strings.HasPrefix(trimmed, "input.body."):
		return dotted(ctx.input.Body, strings.TrimPrefix(trimmed, "input.body."))
	case strings.HasPrefix(trimmed, "output.body."):
		return dotted(ctx.output.Body, strings.TrimPrefix(trimmed, "output.body."))
	case strings.HasPrefix(trimmed, "input."):
		return dotted(ctx.input.ToMap(), strings.TrimPrefix(trimmed, "input."))
	case strings.HasPrefix(trimmed, "output."):
		return dotted(ctx.output.ToMap(), strings.TrimPrefix(trimmed, "output."))
	default:
		first, rest, _ := strings.Cut(trimmed, ".")
		if local, ok := ctx.locals[first]; ok {
			if rest == "" {
				return local, true
			}
			return dotted(local, rest)
		}
		return dotted(ctx.output.Body.Value, trimmed)
	}
}

// setTarget writes a value to a target body path and facet alias.
func setTarget(output *envelope.Envelope, target string, value any) {
	if output == nil || strings.TrimSpace(target) == "" {
		return
	}
	trimmed := strings.TrimSpace(target)
	output.SetFacet(trimmed, value)
	if strings.HasPrefix(trimmed, "output.facets.") {
		output.SetFacet(strings.TrimPrefix(trimmed, "output.facets."), value)
		return
	}
	path := strings.TrimPrefix(trimmed, "output.body.value.")
	path = strings.TrimPrefix(path, "output.")
	setDottedBody(output, path, value)
}

// targetValue reads a mapped output target.
func targetValue(output *envelope.Envelope, target string) (any, bool) {
	if output == nil {
		return nil, false
	}
	if value, ok := output.Facets[strings.TrimSpace(target)]; ok {
		return value, true
	}
	return dotted(output.Body.Value, strings.TrimPrefix(strings.TrimPrefix(target, "output."), "body.value."))
}

// setDottedBody writes a value into the output body object.
func setDottedBody(output *envelope.Envelope, path string, value any) {
	object, _ := output.Body.Value.(map[string]any)
	if object == nil {
		object = map[string]any{}
	}
	parts := strings.Split(strings.TrimSpace(path), ".")
	current := object
	for index, part := range parts {
		if part == "" {
			continue
		}
		if index == len(parts)-1 {
			current[part] = value
			continue
		}
		child, _ := current[part].(map[string]any)
		if child == nil {
			child = map[string]any{}
			current[part] = child
		}
		current = child
	}
	output.Body.Value = object
	output.Body.Kind = envelope.BodyKindObject
}

// facetOrPath resolves exact facet names before treating dots as nesting.
func facetOrPath(values map[string]any, path string) (any, bool) {
	if value, ok := values[strings.TrimSpace(path)]; ok {
		return value, true
	}
	return dotted(values, path)
}

// dotted resolves a dotted path through maps, structs encoded as maps, and arrays.
func dotted(value any, path string) (any, bool) {
	if body, ok := value.(envelope.Body); ok {
		value = map[string]any{"kind": body.Kind, "value": body.Value}
	}
	return jsondata.Dotted(value, path)
}

// cast converts extracted strings to deterministic scalar values.
func cast(value string, kind string) (any, error) {
	switch strings.ToLower(strings.TrimSpace(kind)) {
	case "", "string":
		return value, nil
	case "number", "decimal", "float":
		normalized := strings.ReplaceAll(value, ",", "")
		number, err := strconv.ParseFloat(normalized, 64)
		if err != nil {
			return nil, err
		}
		return number, nil
	case "integer", "int":
		normalized := strings.ReplaceAll(value, ",", "")
		number, err := strconv.Atoi(normalized)
		if err != nil {
			return nil, err
		}
		return number, nil
	default:
		return nil, fmt.Errorf("cast %q is unsupported", kind)
	}
}

// numeric converts common numeric values to float64.
func numeric(value any) (float64, bool) {
	switch typed := value.(type) {
	case float64:
		return typed, true
	case float32:
		return float64(typed), true
	case int:
		return float64(typed), true
	case int64:
		return float64(typed), true
	case int32:
		return float64(typed), true
	case string:
		number, err := strconv.ParseFloat(strings.ReplaceAll(typed, ",", ""), 64)
		return number, err == nil
	default:
		return 0, false
	}
}

// isEmpty reports whether a value should trigger defaulting.
func isEmpty(value any) bool {
	switch typed := value.(type) {
	case nil:
		return true
	case string:
		return strings.TrimSpace(typed) == ""
	case []any:
		return len(typed) == 0
	case map[string]any:
		return len(typed) == 0
	default:
		return false
	}
}

// newEvalContext creates a mapping evaluation context.
func newEvalContext(input envelope.Envelope, output envelope.Envelope, locals map[string]any) *evalContext {
	if locals == nil {
		locals = map[string]any{}
	}
	return &evalContext{input: input, output: &output, locals: locals}
}

// withLocal returns a child context with one local binding.
func (c *evalContext) withLocal(name string, value any) *evalContext {
	locals := map[string]any{}
	for key, item := range c.locals {
		locals[key] = item
	}
	locals[strings.TrimSpace(name)] = value
	return &evalContext{input: c.input, output: c.output, locals: locals}
}

// evalContext stores input, output, and local mapping bindings.
type evalContext struct {
	input  envelope.Envelope
	output *envelope.Envelope
	locals map[string]any
}
