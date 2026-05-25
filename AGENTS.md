# AGENTS.md

## Architecture

### Project Terminology

`AA` is the accepted shortform for Agent Awesome in code comments, docs, branch names, and internal discussion.

### Workspace Components

`harness` is the main agent runtime. It loads agent, model, and tool configuration; builds the ADK runtime; and manages MCP/local toolsets, context APIs, credentials, console mode, and web runtime behavior.

`gateway` is the HTTP control plane and adapter layer. It proxies UI and Slack traffic to harness services, exposes gateway status and channels, bridges selected APIs, and can supervise local sibling services.

`memory` is the memory daemon and service boundary. It owns memory storage, retrieval, graph and task projections, validation, persistence, snapshots, and MCP transport for memory capabilities.

`workflow` is the durable orchestration daemon. It owns workflow definitions, run state, events, outputs, inbox handling, runtime execution, and workflow/MCP/HTTP transport. Its execution model is `state_machine`; definitions may use explicit transition states or task-style states, but they remain state-machine definitions.

`command` is the generic command execution boundary. It runs approved CLI commands through a daemon/MCP service with templates, requests, jobs, approvals, cancellation, timeout handling, and bounded output capture.

`provision` contains provisioning tooling. It manages deployment bundle generation, Cloudflare and platform configuration, local state, credentials/keyring access, and worker secrets.

`ui` is the Flutter desktop app. It owns application controllers, local service supervision UI, HTTP/MCP clients, domain models, shared shell components, command-panel screens, runtime profiles, and integration tests.

`deploy` contains deployment assets and scripts, including Cloudflare Worker/Container beta assets and Linux install tooling.

`docs` contains the Antora documentation component and UI assets for generated project docs.

`e2e` contains the release end-to-end test harness, including mock provider support and diagnostics under `build/e2e`.

`.github` contains GitHub workflow automation and release/CI definitions.

`.agents` and `.codex` contain local agent and Codex metadata. They are workspace support folders, not product runtime architecture.

`build`, module-local `build` folders, `.dart_tool`, `node_modules`, and `logs` contain generated dependencies, caches, diagnostics, local runtime state, or build outputs. Do not treat them as architecture precedents.

### Integration Boundaries

Workflow orchestration MUST remain generic. Do not add first-class workflow runtime support for individual external tools, coding agents, CLIs, hosted services, or vendor-specific assistants. AA invokes external capabilities through generic CLI, MCP, HTTP, or configured tool boundaries.

When an external tool has structured input or output, model that contract at the boundary with explicit schemas, arguments, environment policy, output capture, validation, and typed workflow data. Align to the tool's native interface rather than forcing the tool into an AA-specific abstraction.

Local CLI tool configuration SHOULD describe the CLI surface as one executable tool with documented global flags, subcommands, and subcommand-specific flags. Workflows MUST call deterministic `operations` declared under that executable instead of calling broad CLI surfaces directly. Each operation should define a narrow argv template, input schema, output contract, and safety metadata where relevant. Shared tool libraries SHOULD enable the tool input-schema gate so every command operation publishes structured arguments for agent and workflow tests. Do not model every subcommand/flag combination as a separate operation; expose only stable productized calls that workflows can run without AI.

Tool packages MUST keep their command/MCP surface metadata, deterministic operations, fixtures, mocks, and validations together as portable package metadata. Treat `validations` as GitHub-shareable test cases that can prove both direct agent tool calls and non-AI workflow node invocation through generic command, MCP, HTTP, or workflow boundaries. Do not create validation paths that bypass the same runtime boundary the agent or workflow would use in production.

Agent packages SHOULD keep prompt-level behavior validations beside agent instructions as portable package metadata. Treat agent `validations` as GitHub-shareable tests that can prove expected response behavior, tool selection, and workflow-facing contracts through mocked boundaries today and the same runtime boundary when live hosts are available. Live agent validation runners MUST use an injected agent runtime host instead of constructing a separate runtime path inside the validation package.

Shared agent package CI SHOULD require both at least one validation and at least one concrete assertion per validation. Shared tool package CI SHOULD require concrete assertions for every validation. Use the agent, tool, or library validation quality gates for this instead of allowing placeholder-only cases to pass as proof that a package is tested.

Tool-using agent package CI SHOULD enable the agent tool-call gate so each agent package has at least one validation that proves tool selection. Use `agents validate --require-tool-calls` for single-agent or agent-tree checks and `library validate --require-agent-tool-calls` for combined package libraries. Do not enable that gate for intentionally response-only agents unless the package is expected to exercise a command, MCP, HTTP, or workflow boundary.

Shared package-library CI MUST fail when an enabled required gate cannot find its package directory. Do not silently pass `--require-agent-validations`, `--require-agent-assertions`, agent tool-contract gates, tool assertion gates, or tool coverage gates against a library that skipped the corresponding `agents/` or `tools/` tree. Use an explicit empty directory flag only when a single-surface library intentionally disables that package type.

Shared combined agent/tool libraries SHOULD enable the agent tool-contract gate so agent validations that assert or capture tool calls must resolve to command or MCP tool-call ids declared by the packaged tool library. Captured agent tool-call arguments MUST satisfy the packaged operation input schema when one is declared. Do not treat an agent validation as proving tool use when it points at a tool id that the shared tool package does not expose or passes arguments outside the tool contract.

Agent tool-call assertions SHOULD use package contract ids such as `command:rg.search_text` or `mcp:memory.search_memory`. Validation runners may normalize captured command operation names and `command_execute` `template_id` arguments to those contract ids so tests prove the packaged surface instead of a provider-specific call id.

Validation assertions MUST contain concrete expectations. Contains-style assertions need non-empty `contains`, tool/status/exit assertions need `equals`, `json-path` assertions need a path plus `contains`, `matches`, or `equals`, and `schema` assertions need a non-empty schema. Empty assertion operands are not valid package tests. Agent `expected` shortcuts are limited to recognized keys such as `response_contains` and `tool_call`; tool `expected` shortcuts are limited to `status` and `exit_code`. Unsupported expected keys must fail instead of being counted as assertions.

Agent package UI surfaces SHOULD expose those validations as first-class package tests, not as raw YAML editing or hidden CI-only behavior. The app should let users author validation cases through typed controls, including expected tool-call ids and tool-call parameters, review configured validation cases, run all cases, rerun one case, and inspect prompt, response, tool-call, assertion, diagnostic, and workflow-facing evidence from the same runner output used by CLI and CI. Agent validation result summaries MUST preserve and display agent tool-call contract references across full runs and selected reruns so shared libraries can prove which packaged tool surfaces an agent has been tested to select.

Tool package UI surfaces SHOULD expose command, direct-agent-call, and workflow-node validations as one first-class Details/Validations experience. Authoring controls SHOULD scaffold the command/MCP boundary validation, direct agent-call validation, and workflow-node validation together for the next uncovered tool surface so shared package authors do not accidentally test only one invocation path. Validation result summaries MUST preserve and display target coverage, command-operation input-schema coverage, missing assertion gates, and agent-callable tool ids across full runs and selected reruns so users can tell whether a tool is safe for deterministic workflow invocation without opening raw YAML or CI logs.

Tool validation coverage MUST count only validations that carry concrete configured expectations. A validation that merely names a command operation, MCP tool, agent-call target, workflow node, or preset without an expected status, output assertion, JSON/schema assertion, or equivalent concrete check is a placeholder and MUST NOT satisfy package coverage.

Quality gates, planning reviews, post-implementation reviews, coding-standard checks, retries, approvals, and cleanup loops SHOULD be modeled as state-machine workflow steps using generic primitives. Do not hard-code those product workflows into the workflow engine.

Productized Git worktree, branch, commit, and pull-request operations MUST live behind a dedicated source-control boundary instead of ad hoc shell snippets. Use generic source-control primitives so workflows can compose Git operations without coupling orchestration to a specific agent or review process.

### Code Documentation

ALWAYS add concise code documentation for each file and function.
OPTIONALLY add concise code comments for nuanced statements that should be highlighted.

### Folder Structure

Root-adjacent packages wire systems together. Deeper packages contain narrower, more reusable logic and should not import their parent package.

Consolidate logically related code together. Use subfolders to adhere to the single responsibility principle.

```
security/
  auth/
    oauth/
    mtls/
```

### File Structure

ALWAYS maintain strict adherence to the single responsibility principle. Each function or data model MUST have a single responsibility, even if that responsibility is aggregation.

ALWAYS keep data models as dumb data stores, akin to Java POJOs.

NEVER mix UI logic with business logic. They are separate concerns that need to live in separate files.

NEVER create competing or duplicate implementations. Prioritize spending more time and tokens on understanding the codebase so you can better adhere to SOLID principles.

### Coding Practices

ALWAYS follow SOLID principles. Place particular emphasis on the Single Responsibility Principle.

NEVER add backwards compatibility or legacy support unless explicitly asked.

ALWAYS write production-grade code. DO NOT write shims, stubs, or non-test mocks unless explicitly asked.

ALWAYS give security and bug fixes priority over other coding concerns. Your implementation is only complete once it is secure and bug free.

ALWAYS add concise documentation to each package. ALWAYS state the package's intended use cases and high-level examples to help users know when they are misusing the package if required.

NEVER use fake fallbacks, fake seed data, fake stubs, or the like, unless explicitly asked.

### UI Design

NEVER add informational cards, status blocks, helper banners, explanatory panels, or other passive UI chrome unless the element proves concrete user value. Every visible UI element MUST support a real user decision, action, error recovery, or primary workflow. Remove ornamental or merely reassuring messages such as successful refresh/status summaries instead of giving them screen space.

For forms that edit an existing object or configuration, save on edit with bounded debouncing and lightweight field feedback. Do not require a separate Save button, and do not wait until blur as the primary persistence trigger. Keep explicit action buttons only for creation, destructive actions, approvals, credential submission, or other flows where the user is intentionally committing a new side effect.

Keyboard flow MUST preserve user context. Pressing `Esc` exits the current section, mode, panel, or edit surface without forcing a save. Pressing `Enter` commits the current selection or edit, including any required save or flush. Both keys MUST return the user to the previous screen, section, view, mode, or canvas they came from, and MUST restore the prior scroll or canvas position when position is meaningful.

In command-panel screens, place CRUD controls in the same panel header row as the relevant quick-select controls. Collection-level actions such as create belong in the left command panel action row; selected-object actions such as duplicate or delete belong in the right detail panel action row, aligned with the detail quick-select controls. Nested selected-object collections may use a right item selector only when the active right mode owns that nested collection. Do not put create, duplicate, or delete controls inside individual edit cards when they operate on the selected screen object; cards should focus on editing the selected object itself.

Only show manual refresh controls for external resources that cannot reliably push or auto-refresh local app state. Local resources and locally owned services MUST refresh automatically; do not add refresh buttons for local collections, local drafts, or local configuration screens.

Users MUST NOT be asked to configure, edit, paste, or provide raw files, JSON, YAML, TOML, XML, environment files, or other machine-readable configuration text. User-facing setup and run inputs MUST be collected through product UI controls, generated forms, pickers, wizards, import/install actions, or typed fields that write the underlying file or payload for the user.

All command-panel forms MUST use the shared panel form field base classes and decoration primitives. Do not create one-off text fields, dropdowns, or date-field chrome for individual screens when the shared form components can express the field.

Command-panel navigation has four distinct levels. The top sidebar selects the app domain. The left pane quick access selects what the user is working with: supporting context, collections, objects, sources, palettes, references, versions, or search results. The right pane quick access selects what the user is doing: the primary work mode such as Details, Edit, Build, Review, Audit, Test, Map, Safety, History, or Profile. Right-side labeled tabs select sub-panels inside the active right mode only. Content-level controls are allowed only for domain-specific manipulation inside the current panel, such as graph zoom, axis selection, local filtering, or form-specific options.

Do not use the left pane for major work modes when those modes change the user's primary activity; use the right pane quick access for those choices. Do not duplicate the same content choice in both right quick access and right tabs. Do not use right-side labeled tabs as peers of right modes; tabs are always subordinate to the active right mode. Existing command-panel screens that conflict with this mental model are migration targets, not precedents for new UI.

Artifact metadata MUST be edited only in a right-side mode labeled `Details`. High-level artifact properties such as name, description, package identity, assignment, status metadata, and artifact-level configuration for tools, MCP packages, workflows, task graphs, models, profiles, and similar app objects belong in Details. Do not place those fields in Builder, Source, Commands, Servers, Steps, Settings, Overview, or other task-specific modes; those modes should edit the artifact body, child objects, execution behavior, source text, or operational surfaces only. Details MUST be the first right-side quick access mode whenever it is present. When renaming a managed package artifact, keep the display name and package folder path aligned through the product rename boundary.

The left pane is normally independent from the right pane. The only allowed dependency is a right workspace mode declaring a default companion left pane, such as Builder selecting a node palette. This dependency MUST be declared in the shared shell configuration, not hidden inside a section-specific widget.

App sections MUST instantiate the shared main content sub-shell instead of reimplementing two-column chrome, quick access rows, tab bars, filters, collapse controls, resize behavior, or pane headers. Section files should provide areas, modes, tabs, actions, and content only.

Command-panel UI MUST use the shared panel style system. Use shared panel components for surfaces, icon buttons, inline icon actions, badges, chips, empty states, selectable cards, section labels, form fields, and canvas controls whenever they exist. Do not create local visual dialects for the same interaction pattern.

File-selection UI MUST use the label `Files` and a folder icon consistently. This applies to every generic file-selection or file-catalog pane, including workflow/task file catalogs and any draft/config collection that is presented to the user as selectable files. When the collection is a first-class artifact catalog such as Tools or MCP Servers, keep the folder icon but label the pane with the artifact type. Do not relabel generic file selection as sources, references, documents, assets, attachments, drafts, configs, or evidence in navigation, tabs, tooltips, filters, empty states, or selectable controls unless the user explicitly asks for a distinct non-file concept.

Do not expose implementation ids, generated prefixes, storage keys, or transport details in ordinary user-facing labels, subtitles, cards, badges, or empty states. Internal ids such as `draft_*` may be used as selection keys, API parameters, logs, and explicit technical inspector values only when the user needs to copy or diagnose them.

Keep command-panel visuals quiet. Prefer flat bordered surfaces for repeated cards, inspector sections, event rows, source previews, and canvas frames. Reserve gradients for top-level shell chrome, selected states, or brand moments. Do not add routine content gradients to make ordinary cards feel special.

Tools and MCP Servers command-panel editors MUST NOT wrap their primary Details, Command, or Servers content in an outer bordered section card. Use unframed form sections there so the right pane owns the background; keep borders only on real fields, repeated rows, and item-level affordances.

Use consistent panel archetypes. Collection panels show selectable objects. Inspector panels summarize or edit the selected object. Form editors use shared form sections and fields. Dense editors use compact shared editor sections. Canvas panels use shared graph/map/timeline controls. Dashboard routes may use a separate dashboard style when they are outside the command-panel model.

Left-pane selector, menu, source, reference, and palette panels MUST render as pane-native lists. Do not wrap the list in an extra bordered/background card or alternate pane color. The pane owns the background and spacing; only individual selectable or draggable rows/cards should carry item-level affordance. Apply this consistently whether rows switch the right panel, insert content, pick an object, or act as drag-and-drop sources.

Selectable cards MUST use a shared card variant that matches their job: object card, entity card, config card, graph node card, or chat/session card. Selection is shown primarily through border and selected fill. Accent stripes are thin and reserved for object category, urgency, or risk; do not use the same accent treatment for multiple meanings in the same panel.

Avoid nested visual noise. Do not place bordered cards inside bordered cards unless the nested card is a repeated selectable row or a real contained collection. Prefer plain section spacing for dense subsections, and use bordered sections only when they clarify grouping or interaction.

Badges and chips MUST follow shared semantics. Use `PanelBadge` for metadata, status, type, sensitivity, and counts. Use shell quick filters for low-dimensional collection filters. Use content-level filter chips only for domain-specific manipulation inside the current panel. Use a distinct shared action-chip style for compact actions rather than reusing metadata badges.

Empty states MUST match intent. Use a plain filtered empty state for search misses, a neutral panel empty block for no-data states, an actionable empty state when the next action is obvious, and inline empty rows only inside dense editors. Do not turn empty states into explanatory or reassuring chrome.

Typography MUST follow panel roles. Pane labels use the shared uppercase section-label treatment. Dense command cards and inspector titles use compact bold text, normally `FontWeight.w800`; reserve heavier display treatment for brand, route dashboard, or first-screen hero contexts. Secondary metadata should be muted and compact.

Content-level icon actions MUST use shared panel inline action buttons. Header navigation and CRUD actions use shared shell/panel icon buttons. Native field suffix buttons and primary send/submit controls may keep their field-specific or primary-action styling when that behavior is clearer.

Entity inspectors SHOULD share one structure: top summary with title, subtitle, icon, and primary badges; then secondary sections for metadata, source/access, relationships, and activity. Technical values should be selectable when users may need to copy them.

Canvas, graph, map, and timeline workspaces SHOULD share a canvas-control kit for zoom, recenter/fit, selected-node actions, overlay placement, and fixed-size node cards. Canvas-specific controls belong inside the canvas surface, not in shell chrome.

## Build and Test

Codegen files needed for the project are allowed to be generated in the project source tree. All other files related to binary builds, inspection, verification, etc. must be located in the project's `build` folder.

Work summaries can be provided in the chat window, or in `build/ai`.

## Collaboration

ALWAYS scope changes to one task, such as adding a new LLM provider, fixing a bug, or changing the persistence layer. Remind the user to restructure their requests when they ask for broad, sweeping changes.
