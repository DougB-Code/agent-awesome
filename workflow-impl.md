## Core recommendation

Build AA around **deterministic orchestration with progressive contracts**, not “schema-free” orchestration.

The hard truth is that deterministic systems cannot safely compose arbitrary unknown tools with arbitrary unknown inputs and outputs. Unix pipes work because they standardize the **carrier**: byte streams. They do not guarantee semantic compatibility. The AA equivalent should be:

> Every node consumes and produces an AA envelope, while tools progressively expose enough machine-readable contract information for the engine to validate, map, preview, and adapt connections automatically.

That keeps the user experience pipe-like while preserving determinism and safety.

---

## Existing patterns worth borrowing

### 1. Stateless is suitable for orchestration, not data mapping

The Go `stateless` library supports hierarchical states, entry/exit events, guard clauses, introspection, external state storage, parameterized triggers, thread safety, and DOT graph export. That is a good fit for workflow control flow, especially if workflows model real user processes. ([Go Packages][1])

However, keep tool execution **outside guard clauses**. Stateless explicitly says guards should be side-effect free, and it has no rollback mechanism if an action error occurs after state change. ([Go Packages][1])

Use Stateless for:

* Current workflow state.
* Allowed transitions.
* Hierarchical process structure.
* Waiting states.
* Retry states.
* Human approval states.
* Error states.
* Runtime visualization.

Do **not** use Stateless as the place where data compatibility, schema discovery, mapping, transformation, or security policy lives.

---

### 2. MCP is a useful model, but not sufficient

MCP exposes tools with names, descriptions, `inputSchema`, optional `outputSchema`, structured/unstructured results, and security guidance. That is relevant because it shows what agent ecosystems are converging on: tools need metadata, even when an LLM is the caller. ([Model Context Protocol][2])

But AA should not blindly copy MCP because MCP is model-controlled by design. AA should instead use a similar tool manifest shape internally, while making the workflow engine deterministic.

MCP’s security guidance is directly applicable: validate tool inputs, enforce access controls, rate-limit invocations, sanitize outputs, prompt for sensitive operations, use timeouts, and log tool usage. ([Model Context Protocol][2])

---

### 3. JSON Schema is useful, but users should not author it

JSON Schema is designed to validate JSON instances, describe structure, provide UI hints, and assert what valid data must look like. ([json-schema.org][3]) Its annotation keywords such as `title`, `description`, `default`, and `examples` are useful for self-documenting schemas and form generation. ([json-schema.org][4])

But your users should not see “schemas” as an authoring requirement. The engine, tool registry, and visual builder should create or infer schemas behind the scenes.

The product rule should be:

> Users connect “email attachment” to “extract text from PDF.” AA internally validates `FileRef(application/pdf)` to `DocumentText`, but the user sees plain language.

---

## The key design move: separate carrier, contract, and mapping

You need three layers.

### Layer 1: Universal carrier

Every node should receive and return the same top-level type:

```go
Envelope -> Envelope
```

The envelope is your Unix pipe equivalent.

Recommended envelope shape:

```yaml
envelope:
  meta:
    workflowRunId: string
    nodeRunId: string
    correlationId: string
    causationId: string
    tenantId: string
    userId: string
    attempt: integer
    createdAt: timestamp
    securityContext: object
    provenance: array

  body:
    kind: object | array | text | table | file | files | binary | empty
    value: any

  facets:
    document.text: string
    email.subject: string
    customer.email: string
    invoice.total: number

  artifacts:
    - id: string
      mediaType: string
      name: string
      size: integer
      uri: string
      digest: string

  variables:
    user-visible runtime variables

  diagnostics:
    warnings, errors, validation results

  control:
    status: succeeded | failed | needs_input | cancelled
    suggestedTrigger: optional string
```

The important part is `facets`.

`body` carries the raw output.
`facets` carry normalized semantic fields.
`artifacts` carry files, binaries, images, spreadsheets, PDFs, etc.

This lets an email tool produce an email-shaped payload while also exposing common fields such as:

```yaml
facets:
  email.subject: "Q2 invoice"
  email.sender: "vendor@example.com"
  document.text: "..."
  attachments.pdf: [...]
```

That is how you get pipe-like composition without requiring every downstream tool to understand every upstream tool’s native output.

---

### Layer 2: Tool contracts

Each tool should expose an AA-owned manifest. Users do not write this. Developers, reflection, examples, importers, or LLM-assisted design tooling create it.

```yaml
tool:
  id: aa.office.excel.read_table
  version: 1.2.0
  title: Read Excel Table
  description: Reads a table from an Excel workbook.

  input:
    accepts:
      - kind: file
        mediaTypes:
          - application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
    requiredFacets: []
    schema: optional-json-schema

  output:
    produces:
      - kind: table
    facets:
      - table.rows
      - table.columns
    schema: optional-json-schema
    examples:
      - name: Basic invoice table
        outputShape: ...

  effects:
    filesystem:
      read: true
      write: false
    network:
      allowed: false
    secrets:
      required: []

  runtime:
    timeoutMs: 30000
    maxInputBytes: 10485760
    idempotent: true
    retryable: true
```

The contract does not need to be perfect. It needs to be good enough for:

* Input validation.
* Output validation when possible.
* Compatibility checks.
* Auto-mapping.
* UI previews.
* Security policy.
* Workflow replay and diagnostics.

This is the difference between “users must create schemas” and “AA maintains contracts.”

---

### Layer 3: Edge adapters

Edges should not simply connect node A to node B. They should connect:

```text
source output port -> adapter -> target input port
```

The adapter may be invisible in the visual builder unless the user opens it.

For example:

```text
Get Email Attachments
  -> [adapter: select first PDF attachment]
Extract PDF Text
  -> [adapter: use document.text as prompt context]
Summarize Text
```

The user drags a line. AA inserts or confirms the adapter.

That is the deterministic version of Unix pipes.

---

## What should happen when nodes are not directly compatible?

Use a four-level compatibility model.

### Level 1: Direct pass-through

The source output satisfies the target input.

Example:

```text
FileRef(application/pdf) -> Extract PDF Text
```

No adapter needed.

---

### Level 2: Automatic adapter

The source output has a field or facet that satisfies the target input.

Example:

```text
EmailMessage.attachments[] -> Extract PDF Text
```

AA auto-inserts:

```yaml
adapter:
  operation: select
  source: "$.artifacts[mediaType == 'application/pdf'][0]"
  target: "$.body"
```

The user sees:

> Use the first PDF attachment.

---

### Level 3: User-confirmed adapter

There are multiple plausible mappings.

Example:

```text
CRM Contact -> Send Email
```

Possible recipient fields:

* `contact.email`
* `account.owner.email`
* `lastModifiedBy.email`

AA shows a plain-language choice:

> Which email address should the message be sent to?

The user chooses. AA persists the mapping.

---

### Level 4: Blocked edge

The connection is ambiguous, unsafe, or impossible.

Example:

```text
Untrusted web page text -> Execute shell command
```

AA should block it unless an administrator explicitly creates a policy-approved adapter.

This matters. “Just works” must not mean “silently guesses dangerous behavior.”

---

## Mapping language recommendation

You said you want a mapping specification that can handle:

* 1:1 mappings.
* Conditional logic.
* Calculated fields.
* Aggregations.
* Summary fields.
* Advanced user escape hatches via Starlark.

I would not use Starlark as the primary mapping authoring format. Use a **declarative AA Mapping Spec** as the source of truth, then either interpret it in Go or compile it to restricted Starlark.

### Recommended pattern

Use:

* **AA Mapping Spec** for visual/non-technical users.
* **CEL** for predicates and small expressions.
* **Starlark** as an advanced escape hatch.
* Optional generated Starlark for debugging, not as the authoritative workflow artifact.

CEL is a strong fit for embedded conditions and simple calculations because it is designed to be fast, portable, safe, non-Turing-complete, and limited to data provided by the host application. ([Common Expression Language][5])

Starlark is still valuable because it is deterministic and hermetic when embedded correctly, and its design principles include deterministic evaluation, hermetic execution, parallel evaluation, simplicity, and tooling friendliness. ([GitHub][6])

But Starlark is code. For non-technical users, the visual mapping spec should be primary.

---

## Why not simply adopt an existing mapper?

### JSONata

JSONata is probably the closest general-purpose JSON mapping language. It supports transformation, conditionals, grouping, aggregation, functions, and result construction. ([docs.jsonata.org][7])

Pros:

* Strong JSON transformation capability.
* Good support for calculated fields.
* Good support for grouping and aggregation.
* Familiar to developers who have used JSON mapping tools.

Cons:

* It becomes a Turing-complete functional language once programming constructs are used. ([docs.jsonata.org][7])
* That makes static analysis, visual editing, resource prediction, and non-technical UX harder.
* Go ecosystem support is not as canonical as JavaScript support.

Verdict:

> Good inspiration. Possibly useful as an advanced expression option. Not ideal as the core non-technical mapping spec.

---

### Jolt

Jolt is a JSON-to-JSON transformation library that chains transforms such as `shift`, `default`, `remove`, `sort`, and `cardinality`. It intentionally focuses on structure rather than value manipulation. ([GitHub][8])

Pros:

* Declarative.
* Good for reshaping JSON.
* Mapping spec is data, not code.

Cons:

* Java-centric.
* Weak for calculated fields, rich conditionals, and aggregations.
* Its own docs say custom code is needed for data manipulation. ([GitHub][8])

Verdict:

> Good model for structural remapping, but too limited for your full requirements.

---

### DataSonnet

DataSonnet is an open-source data transformation tool built around Jsonnet concepts and focused on transformation tooling and conventions. ([datasonnet.github.io][9])

Pros:

* Purpose-built for data transformation.
* More expressive than Jolt.

Cons:

* More developer-oriented.
* Less ideal for a visual builder as the primary representation.
* Not Go-native in the same way CEL and Starlark can be.

Verdict:

> Worth studying, but I would not make it AA’s core mapping substrate.

---

### jq / JMESPath

jq is powerful and pipe-inspired; jq programs are filters that take input and produce output, and filters can be composed with pipes. ([jqlang.org][10])

JMESPath is a JSON query language with structured data in and structured data out, and its grammar includes pipe expressions. ([jmespath.org][11])

Pros:

* Great inspiration for composability.
* Useful mental model.
* JMESPath can be useful for selectors.

Cons:

* jq is too developer-heavy for office users.
* JMESPath is better for extraction than full mapping.
* Neither solves the full visual UX, contract, security, and workflow problem.

Verdict:

> Use their ideas, not their UX.

---

## Proposed AA Mapping Spec

Make the mapping spec declarative, versioned, previewable, and statically analyzable.

Example:

```yaml
apiVersion: aa.mapping/v1
kind: Mapping
name: invoice-email-to-approval-request

input:
  expects:
    kind: object
    facets:
      - email.subject
      - email.sender
      - document.text

output:
  produces:
    kind: object
    facets:
      - approval.title
      - approval.requester
      - approval.amount
      - approval.summary

steps:
  - set:
      target: approval.title
      value:
        expr: "'Approve invoice: ' + input.facets['email.subject']"

  - set:
      target: approval.requester
      value:
        path: input.facets.email.sender

  - set:
      target: approval.amount
      value:
        extract:
          from: input.facets.document.text
          pattern: "(?i)total[: ]+\\$?([0-9,.]+)"
          group: 1
          cast: decimal

  - set:
      target: approval.summary
      when:
        expr: "size(input.facets['document.text']) > 0"
      value:
        expr: "substring(input.facets['document.text'], 0, 500)"

  - default:
      target: approval.amount
      value: 0

validate:
  - expr: "output.approval.title != ''"
    message: "Approval title is required."

  - expr: "output.approval.amount >= 0"
    message: "Approval amount cannot be negative."
```

For arrays and aggregation:

```yaml
apiVersion: aa.mapping/v1
kind: Mapping
name: invoice-lines-to-summary

steps:
  - foreach:
      source: input.body.lines
      as: line
      target: output.lines
      map:
        description:
          expr: "line.description"
        quantity:
          expr: "line.qty"
        unitPrice:
          expr: "line.price"
        lineTotal:
          expr: "line.qty * line.price"

  - aggregate:
      source: output.lines
      target: output.total
      op: sum
      expr: "item.lineTotal"

  - groupBy:
      source: output.lines
      key:
        expr: "item.category"
      target: output.byCategory
      aggregates:
        count:
          op: count
        total:
          op: sum
          expr: "item.lineTotal"
```

This gives you the user experience of a visual mapper while preserving deterministic execution.

---

## Mapping spec execution: interpret in Go first

I would make the AA Mapping Spec authoritative and execute it with a Go interpreter.

Why:

* Easier to validate statically.
* Easier to preview in the UI.
* Easier to show “this field maps to that field.”
* Easier to restrict dangerous operations.
* Easier to calculate required input fields.
* Easier to test with sample data.
* Easier to generate human-readable explanations.
* Easier to compile later if needed.

Then optionally support:

```text
AA Mapping Spec -> generated Starlark
```

But treat generated Starlark as an implementation artifact, not the persisted workflow source of truth.

Advanced users can still write a Starlark mapping node, but that should be explicitly marked as advanced and less visually editable.

---

## Workflow file format

Because AA owns the persisted format, make it declarative and versioned.

```yaml
apiVersion: aa.workflow/v1
kind: Workflow
metadata:
  id: approve-invoice
  name: Approve Invoice from Email
  version: 3

nodes:
  - id: watch_email
    type: tool
    tool: aa.mail.watch
    config:
      folder: Inbox
      filter: "has:attachment"

  - id: extract_pdf_text
    type: tool
    tool: aa.documents.extract_pdf_text

  - id: create_approval
    type: tool
    tool: aa.approvals.create_request

edges:
  - from:
      node: watch_email
      port: attachments
    to:
      node: extract_pdf_text
      port: pdf
    adapter:
      kind: auto
      strategy: first_matching_artifact
      mediaType: application/pdf

  - from:
      node: extract_pdf_text
      port: document
    to:
      node: create_approval
      port: request
    adapter:
      kind: mapping
      mappingRef: invoice-email-to-approval-request

transitions:
  - from: watch_email
    on: succeeded
    to: extract_pdf_text

  - from: extract_pdf_text
    on: succeeded
    to: create_approval

  - from: any
    on: failed
    to: error
```

Separate **graph edges** from **state transitions** if needed, but keep the user-facing model simple. Internally, an edge can carry data while a transition carries control.

---

## How the state machine should be structured

Use Stateless as a host for workflow control.

Recommended transition model:

```text
Workflow
  Draft
  Ready
  Running
    Node.Waiting
    Node.Executing
    Node.Completed
    Node.Failed
    Node.WaitingForUser
  Completed
  Failed
  Cancelled
```

Each workflow node becomes either:

* A state.
* A hierarchical substate.
* A reusable state fragment.

Tool execution flow:

```text
Enter Node.Executing
  -> validate input envelope
  -> apply inbound adapter
  -> invoke tool
  -> validate output envelope
  -> apply outbound normalization
  -> persist result
  -> fire Succeeded / Failed / NeedsInput / TimedOut
```

Do not pass arbitrary tool payloads through Stateless trigger parameters. Stateless supports parameterized triggers, but mismatched trigger arguments can panic. ([Go Packages][1])

Instead, persist the current envelope in the workflow runtime context and fire small typed triggers:

```go
Succeeded
Failed
TimedOut
NeedsInput
Approved
Rejected
Cancelled
```

Use guards only to inspect already-produced envelope facts.

---

## Guard conditions and branching

Stateless guard clauses must be mutually exclusive within a state. ([Go Packages][1]) That matters for visual workflows.

Bad:

```text
On success:
  if amount > 1000 -> manager approval
  if vendor is new -> compliance approval
```

Both can be true.

Better:

```text
Decision node: choose approval route
  rule 1: amount > 1000 && vendor.isNew -> compliance_and_manager
  rule 2: amount > 1000 -> manager
  rule 3: vendor.isNew -> compliance
  default -> auto_approve
```

In other words:

> Do not compile ambiguous visual branches directly into Stateless guarded transitions. Compile them into explicit Decision nodes with ordered rules, exclusivity checks, and a default path.

Use CEL for decision predicates.

---

## Tool onboarding without making users write schemas

You need a tool onboarding pipeline.

### 1. Go reflection

For AA-authored tools, generate initial contracts from Go structs.

```go
type SendEmailInput struct {
    To      string   `json:"to" aa:"facet=email.recipient,required"`
    Subject string   `json:"subject" aa:"facet=email.subject"`
    Body    string   `json:"body" aa:"facet=email.body"`
    Attachments []FileRef `json:"attachments"`
}
```

Generate:

* JSON Schema.
* UI labels.
* Required fields.
* Semantic facets.
* Examples.
* Input/output ports.

Users never touch this.

---

### 2. Example-based inference

When a tool has no formal output schema, run it with sample inputs and infer a partial shape.

Example observed output:

```json
{
  "customer": {
    "name": "Acme Inc.",
    "email": "billing@acme.test"
  },
  "total": 1200.55
}
```

Infer:

```yaml
observedShape:
  customer.name: string
  customer.email: string,email-like
  total: number
facets:
  customer.name: probable
  customer.email: high-confidence
  invoice.total: probable
```

Do not treat this as proof. Treat it as an observed contract with confidence.

---

### 3. LLM-assisted design-time manifest creation

Use LLMs outside the deterministic runtime to propose:

* Tool descriptions.
* Input/output contracts.
* Example mappings.
* Facet labels.
* User-facing explanations.

Then validate and persist the result.

The LLM should not be deciding runtime control flow unless it is explicitly inside an LLM node.

---

### 4. Runtime shape learning

Record output shapes during real runs.

If a tool consistently emits the same structure, AA can suggest a stronger contract:

> “This tool has produced `invoice.total` in 97% of runs. Add it as an output facet?”

This is powerful, but should be versioned and reviewable.

---

## Security architecture

Your “local in-process Go package” constraint is reasonable for AA-authored tools, but it is not a hard security boundary.

If a tool package is imported into the same Go process, that code can potentially access the same process privileges unless you restrict it through architecture, code review, build rules, or separate execution. For untrusted third-party tools, in-process execution is not secure enough. You would eventually need process isolation, WASM/WASI, containers, or another sandbox.

For AA-authored tools, use **capability injection**.

Instead of giving tools ambient access to everything, give them a constrained context:

```go
type ToolContext struct {
    Files   FileService
    HTTP    HTTPService
    Secrets SecretService
    Audit   AuditService
    Clock   Clock
    Logger  Logger
}
```

Each tool manifest declares required capabilities:

```yaml
effects:
  filesystem:
    read:
      - user_selected_files
    write:
      - workflow_workspace
  network:
    allowedHosts:
      - graph.microsoft.com
  secrets:
    required:
      - microsoft_graph_token
  userConfirmation:
    requiredFor:
      - send_email
      - delete_file
```

Security rules:

* Validate every tool input.
* Validate every structured output.
* Put deadlines on every tool call.
* Limit envelope size.
* Limit artifact size.
* Redact secrets in logs.
* Track provenance for every field.
* Treat external text as untrusted.
* Sanitize outputs before passing them to LLM nodes.
* Require approval for destructive or exfiltrating actions.
* Make network permissions explicit.
* Store audit logs for every tool invocation.

---

## Determinism: important correction

Your workflow engine can be deterministic, but your workflow results may not be.

Reasons:

* Remote APIs change.
* Files change.
* Time changes.
* LLM nodes are nondeterministic unless tightly constrained.
* User approvals are external inputs.
* Network failures happen.

The better phrase is:

> AA should provide deterministic orchestration, deterministic mapping, deterministic validation, and deterministic transition selection, while treating tools as effectful operations with recorded inputs and outputs.

For replayability:

* Persist every input envelope.
* Persist every output envelope.
* Persist selected transition.
* Persist tool version.
* Persist mapping version.
* Persist policy decision.
* Persist timestamps and external request IDs.
* Redact or tokenize sensitive values.

Then AA can replay the orchestration deterministically using recorded tool results.

---

## UX model for non-technical users

The visual builder should hide schemas and show business concepts.

### When connecting nodes

User action:

```text
Drag: Email trigger -> Extract PDF text
```

AA response:

```text
Connected using: first PDF attachment
```

Advanced details hidden:

```yaml
source: artifacts[mediaType == application/pdf][0]
target: body.file
```

---

### When there are multiple possible mappings

Show choices, not schemas:

```text
Which file should be processed?

1. First PDF attachment
2. All PDF attachments
3. The largest attachment
4. Attachment named like "invoice"
```

The selected option becomes a deterministic adapter.

---

### When required input is missing

Show:

```text
“Send Email” needs a recipient.

Choose one:
- Customer email from CRM result
- Sender of original email
- Type a fixed email address
- Ask user during workflow run
```

Internally, those become:

* Field mapping.
* Constant.
* Runtime input node.
* Human-in-the-loop state.

---

## Architecture components

Use these components as separate packages.

```text
aa-workflow-runtime
  Runs workflows, manages state, persistence, retries, and audit.

aa-state-machine
  Compiles workflow definitions into Stateless configuration.

aa-envelope
  Defines Envelope, ArtifactRef, Facet, Diagnostic, Provenance.

aa-tools
  Tool interface, tool registry, manifests, capability declarations.

aa-contracts
  Input/output contracts, schema inference, semantic facets.

aa-mapping
  AA Mapping Spec parser, validator, interpreter, CEL integration.

aa-adapters
  Auto-generated and reusable adapters between tool ports.

aa-policy
  Capability checks, approval rules, data exfiltration checks.

aa-builder-model
  Visual-builder-safe workflow representation.

aa-workflow-schema
  JSON Schema or CUE definitions for AA workflow files.
```

Design patterns:

* **Adapter Pattern**: edge adapters convert one node’s output to another node’s input.
* **Command Pattern**: each tool invocation is a command with input, output, effects, and audit.
* **Strategy Pattern**: mapping strategies can be direct, inferred, user-selected, or scripted.
* **Chain of Responsibility**: compatibility engine tries direct match, semantic match, inferred mapping, reusable adapter, then user prompt.
* **Saga Pattern**: long-running workflows with compensating actions for effectful tools.
* **Facade Pattern**: visual builder talks to a simplified workflow authoring API, not the runtime internals.

---

## The compatibility engine

When the user draws an edge, run this pipeline:

```text
1. Carrier compatibility
   Does kind/media type match?
   Example: PDF file -> PDF extractor.

2. Shape compatibility
   Does JSON Schema / observed shape satisfy target requirements?

3. Semantic compatibility
   Do facets match?
   Example: customer.email -> email.recipient.

4. Example compatibility
   Given sample output, can AA find the required target fields?

5. Reusable adapter lookup
   Has AA seen this source/target pair before?

6. Mapping synthesis
   Generate deterministic mapping spec.

7. User confirmation
   Ask only when needed, in business language.

8. Block
   If unsafe or impossible.
```

The result should be one of:

```yaml
compatibility:
  status: direct | adapted | needs_user_choice | blocked
  confidence: high | medium | low
  adapterRef: optional
  explanation: "Using the first PDF attachment."
  risks:
    - "Multiple PDF attachments may exist."
```

---

## LLM nodes

LLMs can exist as node types, but constrain their interface.

Bad LLM node:

```text
Prompt: Decide what to do next.
Output: free text.
```

Good LLM node:

```yaml
node:
  type: llm
  outputSchema:
    type: object
    required:
      - status
      - result
    properties:
      status:
        enum:
          - succeeded
          - failed
          - needs_review
      result:
        type: object
      confidence:
        type: number
```

Then the state machine transitions deterministically:

```text
status == succeeded -> next
status == failed -> error
status == needs_review -> human review
```

The LLM has autonomy inside the node, but the workflow only sees a validated structured result.

---

## Minimum viable product path

### Phase 1: Deterministic envelope and tool manifests

Build:

* Envelope.
* Tool interface.
* Tool registry.
* Basic manifests.
* Input/output validation.
* Stateless runtime wrapper.
* Simple visual graph persistence.

Support only:

* Direct pass-through.
* Manual field selection.
* Basic mapping.

---

### Phase 2: AA Mapping Spec

Build:

* Mapping spec parser.
* Go interpreter.
* CEL expressions.
* Preview engine.
* Mapping validation.
* Required-field detection.
* Golden tests for mappings.

Support:

* `set`
* `default`
* `when`
* `foreach`
* `aggregate`
* `groupBy`
* `validate`

---

### Phase 3: Auto-adapters

Build:

* Compatibility engine.
* Semantic facets.
* Example-based shape inference.
* Adapter registry.
* User-confirmed mapping choices.

This is where the product starts to feel pipe-like.

---

### Phase 4: Design-time LLM assistant

Use LLMs to create:

* Suggested mappings.
* Tool descriptions.
* Manifest drafts.
* Facet suggestions.
* Workflow explanations.

Persist only deterministic artifacts.

---

### Phase 5: Policy and marketplace readiness

Build:

* Capability declarations.
* Permission checks.
* Approval gates.
* Data-loss prevention checks.
* Tool signing.
* Tool versioning.
* Strong sandbox story for non-AA tools.

---

## Final design principle

Do not try to make deterministic workflows “schema-free.”

Make them:

> schema-hidden, schema-assisted, progressively typed, adapter-driven, and previewable.

That is the path to matching the low barrier of LLM harnesses without giving up robustness, auditability, or security.

[1]: https://pkg.go.dev/github.com/qmuntal/stateless "stateless package - github.com/qmuntal/stateless - Go Packages"
[2]: https://modelcontextprotocol.io/specification/2025-06-18/server/tools "Tools - Model Context Protocol"
[3]: https://json-schema.org/draft/2020-12/json-schema-validation "JSON Schema Validation: A Vocabulary for Structural Validation of JSON"
[4]: https://json-schema.org/understanding-json-schema/reference/annotations "JSON Schema - Annotations"
[5]: https://cel.dev/ "CEL  |  Common Expression Language"
[6]: https://github.com/bazelbuild/starlark "GitHub - bazelbuild/starlark: Starlark Language · GitHub"
[7]: https://docs.jsonata.org/programming "Programming constructs · JSONata"
[8]: https://github.com/bazaarvoice/jolt "GitHub - bazaarvoice/jolt: JSON to JSON transformation library written in Java. · GitHub"
[9]: https://datasonnet.github.io/datasonnet-mapper/datasonnet/latest/index.html "DataSonnet :: DataSonnet Mapper Documentation"
[10]: https://jqlang.org/manual/ "jq 1.8 Manual"
[11]: https://jmespath.org/specification.html "JMESPath Specification — JMESPath"
