# Agent Awesome Today Screen Implementation Specification

## 1. Purpose

The Today screen is Agent Awesome's default home screen. It gives the user one executive summary page that answers:

- What deserves my attention now?
- What might I forget?
- What commitments need care?
- What is coming next?
- What can Agent Awesome handle?
- What is blocked, risky, or waiting?
- What does Agent Awesome not know well enough?

The screen must be useful from non-visual channels too. The canonical projection therefore lives in the memory MCP server, not in Flutter. Flutter renders the projection visually. Slack, chat, and other channels can ask for the same projection and receive a text summary.

## 2. Design patterns

Use these patterns explicitly:

- **Hexagonal Architecture / Ports and Adapters**: the memory projection engine is domain logic; MCP tools, Flutter, Slack, and harness context calls are adapters.
- **CQRS Read Model / Projection Pattern**: the Today screen is a read-only projection over graph memory, tasks, relations, external signals, and tool state.
- **Presenter Pattern**: Flutter widgets render server-provided semantic sections; they do not own ranking or classification logic.
- **Adapter Pattern**: UI, Slack, and chat convert the same `ExecutiveSummaryProjection` into different presentations.
- **Policy Object Pattern**: scoring and classification rules live in small focused policy components inside the memory server.

## 3. Current architecture anchors

The current deployed tool configuration already exposes graph memory and task MCP tools, including `query_context_graph`, `create_task`, `list_tasks`, `task_graph_projection`, task mutation tools, task-memory linking, and task relation traversal/mutation tools. The Today screen should extend this same MCP boundary instead of adding a parallel UI-only query path.

The current memory server already exposes `task_graph_projection` as a graph-backed task snapshot containing tasks, relations, nodes, edges, optional facets, and projection quality counters. That is the immediate source data for the first Today projection.

The current UI already has clients and controller wiring for ADK sessions, memory MCP calls, task MCP calls, task projection parsing, and screen command planning. The Today implementation should reuse that structure rather than introducing a separate state system.

The current gateway proxies `/api/context/*` to the harness context API and `/mcp` to the memory MCP endpoint. For the Today screen, prefer the harness context API because it lets the UI use the same configured MCP tool allow-list that the harness and agent use.

## 4. Non-goals for the first release

Do not implement these in the first Today release:

- Full 3D terrain map.
- Full memory constellation.
- Full life orbit graph.
- Vendor-specific calendar, email, bank, health, or Slack integrations.
- UI-side ranking engines that diverge from memory MCP projections.
- Claims based on unsupported data, such as sleep quality, unread email, bank balance, or location-aware errands.

The first release should be a reliable executive summary page. Dedicated projection pages can come later through links on the Today cards.

## 5. Product surface

The Today screen keeps the current Agent Awesome visual language shown in the app screenshots:

- Left navigation remains stable.
- Top command bar remains stable.
- The page title is `Today`.
- The subtitle is `Here is what matters now.`
- The layout uses calm, light, rounded panels instead of dark sci-fi mockups.

### 5.1 Page sections

The first release Today page has seven sections:

1. **Summary Metrics**
2. **Open Loop Radar**
3. **Today's Attention**
4. **Delegation & Agent**
5. **Horizon**
6. **Risk & Unblocks**
7. **Confidence & Coverage**

### 5.2 Layout

```text
Today
Here is what matters now.

[ Decisions ] [ Actions ] [ Relationships ] [ Agent can handle ] [ Picture quality ]

┌────────────────────┬───────────────────────────────┬──────────────────────┐
│ Open Loop Radar    │ Today's Attention              │ Delegation & Agent   │
│                    │                               │                      │
│ mini radar chart   │ Protect / Decide / Do / ...    │ Can do / Approval /  │
│ category counts    │ Why this? links                │ Running / Done       │
└────────────────────┴───────────────────────────────┴──────────────────────┘

┌───────────────────────────────┬────────────────────────────────────────────┐
│ Horizon                       │ Risk & Unblocks                            │
│ Now / Next / Today / Tomorrow │ chain + suggested next unblock             │
└───────────────────────────────┴────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────────────────┐
│ Confidence & Coverage                                                     │
│ Good coverage / Partial / Not connected / Source-backed promise           │
└────────────────────────────────────────────────────────────────────────────┘
```

### 5.3 Links to dedicated projection pages

Every section has a link:

- Open Loop Radar -> `/open-loops`
- Today's Attention -> `/attention`
- Delegation & Agent -> `/delegation`
- Horizon -> `/timeline`
- Risk & Unblocks -> `/risks`
- Confidence & Coverage -> `/memory/coverage`
- Picture quality metric -> `/memory/coverage`

The links can route to existing screens initially. Dedicated projection pages are not required for the first release, but the link targets should be reserved now.

## 6. Canonical MCP projection

### 6.1 Add MCP tool: `project_executive_summary`

The memory MCP server owns the canonical Today projection.

#### Input schema

```json
{
  "scope": "user",
  "horizon": "today",
  "now": "2026-05-09T09:24:00Z",
  "max_items": 12,
  "include_evidence": true,
  "include_actions": true,
  "channel": "ui"
}
```

#### Input fields

| Field | Type | Required | Default | Description |
|---|---:|---:|---|---|
| `scope` | string | no | `user` | Memory ownership scope. Use existing scope values where possible. |
| `horizon` | string | no | `today` | `now`, `today`, `tomorrow`, `week`, or `all`. |
| `now` | RFC3339 string | no | server time | Deterministic testable clock override. |
| `max_items` | integer | no | `12` | Max visible items across primary sections. |
| `include_evidence` | boolean | no | `true` | Include concise evidence handles and reasons. |
| `include_actions` | boolean | no | `true` | Include user/tool action hints. |
| `channel` | string | no | `ui` | `ui`, `slack`, `chat`, or `api`; controls verbosity only, not semantics. |

#### Output schema

```json
{
  "schema_version": "agent-awesome/executive-summary/v1",
  "generated_at": "2026-05-09T09:24:00Z",
  "scope": {
    "kind": "user",
    "id": "doug",
    "label": "Doug"
  },
  "horizon": "today",
  "title": "Today",
  "subtitle": "Here is what matters now.",
  "narrative_summary": "You have 2 decisions, 3 actions, 1 relationship loop, and 4 items Agent Awesome can handle.",
  "metrics": [],
  "attention": {},
  "open_loops": {},
  "commitments": {},
  "time_horizon": {},
  "delegation": {},
  "risk_unblocks": {},
  "coverage": {},
  "quality": {},
  "links": []
}
```

### 6.2 Add MCP tool: `explain_executive_summary_item`

This powers every `Why this?` link.

#### Input schema

```json
{
  "item_id": "attention:task_123",
  "include_sources": true
}
```

#### Output schema

```json
{
  "item_id": "attention:task_123",
  "title": "Buy milk",
  "reason": "Small isolated task with no project or next-action relation; easy to forget.",
  "evidence": [
    {
      "kind": "task",
      "id": "task_123",
      "label": "Buy milk",
      "relationship": "source"
    }
  ],
  "confidence": 0.84,
  "limits": []
}
```

### 6.3 Future MCP detail tools

Do not add these unless the detail pages need server-side pagination or richer filters:

- `project_open_loops`
- `project_attention`
- `project_horizon`
- `project_delegation`
- `project_risk_unblocks`
- `project_memory_coverage`

For the initial release, `project_executive_summary` plus `explain_executive_summary_item` is enough.

## 7. Projection data model

### 7.1 Shared types

```go
type ExecutiveSummaryProjection struct {
    SchemaVersion    string                   `json:"schema_version"`
    GeneratedAt      time.Time                `json:"generated_at"`
    Scope            ProjectionScope          `json:"scope"`
    Horizon          string                   `json:"horizon"`
    Title            string                   `json:"title"`
    Subtitle         string                   `json:"subtitle"`
    NarrativeSummary string                   `json:"narrative_summary"`
    Metrics          []SummaryMetric          `json:"metrics"`
    Attention        AttentionProjection      `json:"attention"`
    OpenLoops        OpenLoopProjection       `json:"open_loops"`
    Commitments      CommitmentProjection     `json:"commitments"`
    TimeHorizon      TimeHorizonProjection    `json:"time_horizon"`
    Delegation       DelegationProjection     `json:"delegation"`
    RiskUnblocks     RiskUnblockProjection    `json:"risk_unblocks"`
    Coverage         CoverageProjection       `json:"coverage"`
    Quality          ProjectionQualitySummary `json:"quality"`
    Links            []ProjectionLink         `json:"links"`
}
```

```go
type ExecutiveSummaryItem struct {
    ID              string                   `json:"id"`
    Kind            string                   `json:"kind"`
    Lane            string                   `json:"lane,omitempty"`
    Title           string                   `json:"title"`
    Subtitle        string                   `json:"subtitle,omitempty"`
    Reason          string                   `json:"reason"`
    Score           float64                  `json:"score,omitempty"`
    Confidence      float64                  `json:"confidence,omitempty"`
    Status          string                   `json:"status,omitempty"`
    Priority        string                   `json:"priority,omitempty"`
    TaskID          string                   `json:"task_id,omitempty"`
    Person          string                   `json:"person,omitempty"`
    Project         string                   `json:"project,omitempty"`
    DueAt           *time.Time               `json:"due_at,omitempty"`
    ScheduledAt     *time.Time               `json:"scheduled_at,omitempty"`
    FollowUpAt      *time.Time               `json:"follow_up_at,omitempty"`
    EstimateMinutes int                      `json:"estimate_minutes,omitempty"`
    Evidence        []ExecutiveSummaryEvidence `json:"evidence,omitempty"`
    PrimaryAction   *ExecutiveSummaryAction  `json:"primary_action,omitempty"`
    Actions         []ExecutiveSummaryAction `json:"actions,omitempty"`
    Links           []ProjectionLink         `json:"links,omitempty"`
}
```

### 7.2 Metric model

```json
{
  "id": "decisions",
  "label": "Decisions",
  "value": "2",
  "subtitle": "Require your input",
  "severity": "attention",
  "link": { "label": "View decisions", "route": "/attention?lane=decide" }
}
```

Required metrics:

1. `decisions`
2. `actions`
3. `relationships`
4. `agent_can_handle`
5. `picture_quality`

### 7.3 Attention lanes

| Lane | Meaning | Typical source rules |
|---|---|---|
| `protect` | Work/time that should not be casually displaced | scheduled soon, high value, high pressure, focus energy |
| `decide` | Requires human judgment or approval | high risk, low confidence, blocked by user decision, sensitive action |
| `do` | Small concrete action | low estimate, open, due soon, low ambiguity |
| `delegate` | Agent or another actor can handle it | high agent fit, low human effort, available safe tool path |
| `repair` | Trust/relationship loop | `person` or `follow_up_at`, overdue, promise/commitment source |
| `monitor` | Watch but do not act yet | waiting, blocked by someone else, future due date, no immediate action |

### 7.4 Open loop categories

Required categories:

- `orphan_tasks`
- `stale_promises`
- `waiting_on`
- `blocked`
- `metadata_gaps`
- `unscheduled_due_items`

Each category returns:

```json
{
  "id": "orphan_tasks",
  "label": "Orphan tasks",
  "count": 3,
  "severity": "warning",
  "top_items": [],
  "link": { "route": "/open-loops?category=orphan_tasks" }
}
```

### 7.5 Delegation statuses

Required buckets:

- `can_do_now`
- `needs_approval`
- `needs_context`
- `running`
- `done`
- `failed`

Do not infer tool availability unless it is available in the harness or memory tool registry. When no tool path is known, classify as `needs_context` or omit from delegation.

### 7.6 Coverage statuses

Required buckets:

- `good_coverage`
- `partial_coverage`
- `not_connected`
- `do_not_infer`

Coverage must be explicit. If there is no source-backed signal for calendar, email, health, location, banking, or Slack relationship recency, the projection must mark those domains as unknown rather than inventing facts.

## 8. Memory server implementation

### 8.1 Files to add

```text
memory/internal/memory/domain/executive_summary_types.go
memory/internal/memory/domain/executive_summary_validation.go
memory/internal/memory/service/executive_summary.go
memory/internal/memory/projection/executive_summary_engine.go
memory/internal/memory/projection/attention_policy.go
memory/internal/memory/projection/open_loop_policy.go
memory/internal/memory/projection/delegation_policy.go
memory/internal/memory/projection/coverage_policy.go
memory/internal/memory/projection/risk_unblock_policy.go
memory/internal/memory/projection/horizon_policy.go
```

### 8.2 Files to update

```text
memory/internal/memory/mcp/tools.go
memory/internal/memory/service/service.go
memory/internal/memory/graph/repository/task_projection.go
memory/internal/memory/domain/task_projection_types.go
memory/internal/memory/domain/types.go
```

### 8.3 Service flow

```text
ProjectExecutiveSummary(query)
  -> NormalizeExecutiveSummaryQuery(query)
  -> Load TaskGraphProjection(include_facets=true, active tasks first)
  -> Load recent/active memory evidence only when needed
  -> Build TaskIndex
  -> Build RelationIndex
  -> Build SignalIndex
  -> Compute AttentionProjection
  -> Compute OpenLoopProjection
  -> Compute CommitmentProjection
  -> Compute TimeHorizonProjection
  -> Compute DelegationProjection
  -> Compute RiskUnblockProjection
  -> Compute CoverageProjection
  -> Compose ExecutiveSummaryProjection
```

### 8.4 Projection rules

#### Attention score

Start with an explainable deterministic score:

```text
attention_score =
  pressure * 0.22
+ time_pressure * 0.18
+ risk * 0.16
+ value * 0.14
+ urgency * 0.12
+ relationship_cost * 0.08
+ forgetting_risk * 0.08
- safely_delegable * 0.06
```

When a numeric field is missing, use `0`, not a hallucinated default. Use explicit fallback explanations such as `No risk score recorded`.

#### Forgetting risk

```text
forgetting_risk increases when:
- task is open and has no due date
- task has no project/person/topic/facet
- task has no relation edges
- task estimate is small
- task was created from a remember/capture action
- task has not been updated recently
```

#### Relationship cost

```text
relationship_cost increases when:
- person is present
- follow_up_at is due or overdue
- task source indicates promise/commitment
- memory link relationship is originated_from or supporting
```

Do not score relationship health. Score only the visible obligation or commitment.

#### Delegation fit

```text
delegation candidate when:
- task is open or waiting
- task has high agent_fit or context/source indicates drafting/research/summarizing/planning
- task is not a sensitive financial, destructive, or external-send action
- available tool path exists or can be represented as a safe draft/prep action
```

#### Risk/unblock

```text
risk_unblock candidate when:
- status is blocked or waiting
- relation type is blocks / depends_on / enables
- downstream task has higher value, risk, or urgency
- blocker has small estimate or clear next action
```

### 8.5 External signals

Add a generic external signal model so future agent-created tools can anchor arbitrary integrations without first-class vendor support.

Recommended graph/memory shape:

```json
{
  "kind": "external_signal",
  "source_system": "fitbit",
  "source_type": "health_tracker",
  "signal_type": "sleep_duration",
  "subject": "user",
  "domain": "health",
  "observed_at": "2026-05-09T07:15:00Z",
  "valid_until": "2026-05-10T07:15:00Z",
  "value": 7.1,
  "unit": "hours",
  "confidence": 0.92,
  "sensitivity": "private",
  "evidence_id": "ev_123"
}
```

If adding `external_signal` as a memory kind is too large for the first release, store these as `tool_output` records with `topics`, `entity_names`, and structured metadata. The coverage projection must only use them when they are source-backed and not expired.

## 9. Harness implementation

### 9.1 Tool configuration

Add the new tools to all memory MCP allow-lists:

```yaml
tools:
  allow:
    - project_executive_summary
    - explain_executive_summary_item
```

Update at least:

```text
deploy/cloudflare/config/tool.yaml
pilots/*/tool.yaml or runtime profile tool config
UI-generated graph-backed memory tool config allow-list
harness tests for tool validation
```

### 9.2 Context API

The harness context API should be able to call the new MCP tools through the configured memory MCP server. The existing context API pattern already resolves a tool by name against configured MCP servers and their allow-lists before invoking it.

Required behavior:

- `POST /api/context/tools/call` with `name=project_executive_summary` returns the tool's structured content.
- If the memory MCP server is not configured or the tool is not allow-listed, return a clear tool-not-exposed error.
- Do not ask the LLM to synthesize the Today projection from raw tasks.

### 9.3 Agent chat behavior

The agent should use `project_executive_summary` when the user asks:

- `what matters today?`
- `what am I forgetting?`
- `what should I work on?`
- `what can you handle?`
- `brief me`
- `what needs my attention?`

For chat responses, the harness should let ADK execute the MCP tool and then summarize the structured result. UI rendering of the Today page should not depend on the chat response.

### 9.4 Runtime policy cleanup

Long-term, task behavior and idempotency should move to ADK instructions and callbacks. For this Today feature, do not add new gateway-injected policy text. The projection is a memory MCP read tool and should not depend on prompt injection.

## 10. Gateway implementation

### 10.1 No new gateway brain logic

The gateway remains a transport, auth, readiness, and proxy layer.

Do not implement scoring, ranking, projection, or fallback summaries in the gateway.

### 10.2 Required behavior

- `/api/context/tools/call` remains the UI path for harness-owned context tool calls.
- `/mcp` remains available for raw memory MCP control-plane traffic where needed.
- Readiness failures should produce clear `503 dependency not ready` responses.
- Gateway status should surface whether harness and memory are connected.

## 11. Flutter UI implementation

### 11.1 Files to add

```text
lib/domain/executive_summary.dart
lib/clients/executive_summary_client.dart
lib/features/today/today_screen.dart
lib/features/today/today_controller.dart
lib/features/today/widgets/today_metric_strip.dart
lib/features/today/widgets/open_loop_radar_card.dart
lib/features/today/widgets/todays_attention_card.dart
lib/features/today/widgets/delegation_agent_card.dart
lib/features/today/widgets/horizon_strip_card.dart
lib/features/today/widgets/risk_unblocks_card.dart
lib/features/today/widgets/confidence_coverage_card.dart
lib/features/today/widgets/executive_summary_explanation_drawer.dart
```

### 11.2 Files to update

```text
lib/app/app_controller.dart
lib/app/app_config.dart
lib/clients/mcp_client.dart
lib/domain/models.dart
lib/main.dart or current app route registration file
lib/widgets/sidebar/navigation file
```

### 11.3 Client

`ExecutiveSummaryClient` should use the same `ToolRpcClient` abstraction as memory/task clients.

```dart
class ExecutiveSummaryClient {
  const ExecutiveSummaryClient({required ToolRpcClient rpc}) : _rpc = rpc;

  final ToolRpcClient _rpc;

  Future<ExecutiveSummaryProjection> projectExecutiveSummary({
    String horizon = 'today',
    DateTime? now,
    int maxItems = 12,
    String channel = 'ui',
  }) async {
    final content = await _rpc.callTool('project_executive_summary', {
      'horizon': horizon,
      if (now != null) 'now': now.toUtc().toIso8601String(),
      'max_items': maxItems,
      'include_evidence': true,
      'include_actions': true,
      'channel': channel,
    });
    return parseExecutiveSummaryProjection(content);
  }
}
```

Use `GatewayContextClient` when running through the gateway. This keeps the Today screen aligned with the harness MCP allow-list.

### 11.4 UI state

```dart
class TodayState {
  const TodayState({
    this.busy = false,
    this.error = '',
    this.projection = const ExecutiveSummaryProjection.empty(),
    this.selectedExplanationItemId = '',
  });

  final bool busy;
  final String error;
  final ExecutiveSummaryProjection projection;
  final String selectedExplanationItemId;
}
```

`TodayController` responsibilities:

- load projection on app start or when Today screen opens
- refresh after task mutations
- refresh after chat/tool events that mutate tasks or memory
- open explanation drawer
- route dedicated projection links
- never recompute scores client-side

### 11.5 Rendering rules

#### Summary Metrics

Render 5 metric cards:

- Decisions
- Actions
- Relationships
- Agent can handle
- Picture quality

Metric card click routes to the projection detail page.

#### Open Loop Radar

First release rendering:

- Use a simple radar/spider mini chart or compact count grid.
- Show category labels and counts.
- Show `View open loops` link.
- Do not show every task in this card.

#### Today's Attention

Render rows from `attention.items` grouped by lane order:

1. Protect
2. Decide
3. Do
4. Delegate
5. Repair
6. Monitor

Each row shows:

- lane icon
- lane label
- title
- short reason/subtitle
- optional time/estimate/status
- `Why this?` link
- chevron to dedicated detail

#### Delegation & Agent

Render buckets:

- Agent can do now
- Needs your approval
- Running
- Done
- Failed / Needs attention

Show up to three items per bucket and a `View all` link.

#### Horizon

Render fixed buckets:

- Now
- Next
- Today
- Tomorrow
- This Week

Each bucket shows count and the top item. Link to Timeline.

#### Risk & Unblocks

Render the top unblock chain as a horizontal sequence:

```text
Collect forecast inputs -> Review May budget -> Budget decision
```

Show suggested next unblock and a `Take action` button if the primary action is safe.

#### Confidence & Coverage

Render three columns:

- Good coverage
- Partial
- Not connected

Also show a privacy/source-backed promise:

```text
I only use information that is source-backed in memory.
I will not infer data I do not have.
```

### 11.6 Screen command integration

The global command bar placeholder already indicates screen-aware commands. Today should expose a compact screen snapshot to the screen command planner.

```dart
class TodayScreenSnapshot {
  final String scopeLabel;
  final List<ExecutiveSummaryItemSnapshot> visibleItems;
  final List<String> availableTools;
  final Map<String, dynamic> projectionQuality;
}
```

Supported commands:

- `show me the decisions`
- `why is buy milk here?`
- `take action on the unblock`
- `delegate everything safe`
- `mark buy milk done`
- `open open loops`

Destructive changes remain staged for review. Safe task completions can follow the same safety model already used by Backlog screen commands.

## 12. Data freshness and refresh strategy

### 12.1 Initial load

Load Today after local services are connected and the memory MCP tool is available.

### 12.2 Refresh triggers

Refresh the projection after:

- task create/update/complete/cancel/delete
- task relation mutation
- task-memory link mutation
- memory save/correction affecting task-related evidence
- chat tool event with function response for task or memory mutation
- manual refresh button
- app returns to foreground

### 12.3 Caching

Memory server may cache `project_executive_summary` for a short TTL:

- Default TTL: 15 seconds
- Bypass cache when `now` is supplied in tests
- Bypass cache after mutation events if invalidation is implemented

## 13. Accessibility and cognitive-load requirements

- Keep the page stable. Refresh content without reordering every card unnecessarily.
- Do not animate radar or horizon by default.
- Use text labels in addition to icons.
- Keep each item to one primary action.
- Put explanations behind `Why this?` links.
- Do not shame the user with giant overdue lists.
- Use `Picture quality` to communicate uncertainty without blaming the user.
- Allow reduced-density and high-density variants later, but do not split the data model.

## 14. Security, privacy, and trust

- Projection responses must not include restricted evidence unless explicitly requested and authorized.
- Coverage must identify unknown integrations rather than inventing data.
- External signals must include source system, observed time, validity window, confidence, and sensitivity.
- Financial actions, external sends, destructive task changes, and sensitive memory writes remain approval-gated.
- The UI should display tool outcomes, not raw model/tool markup.

## 15. Testing strategy

### 15.1 Memory server tests

Add tests for:

- `project_executive_summary` returns all required sections.
- empty graph returns an empty but useful projection.
- open tasks produce attention items.
- no-project/no-person/no-relation task appears as an open loop.
- person/follow-up task appears in commitments/repair.
- blocked/dependency relation appears in risk/unblocks.
- high agent-fit safe task appears in delegation `can_do_now`.
- unsafe or financial task appears in `needs_approval`.
- missing external integrations appear in coverage `not_connected`.
- `explain_executive_summary_item` returns evidence and limits.

### 15.2 Harness tests

Add tests for:

- new MCP tools are visible through `/api/context/tools/list` when allow-listed.
- `/api/context/tools/call` invokes `project_executive_summary`.
- tool-not-allow-listed returns a clear error.
- ADK chat can call `project_executive_summary` for `brief me`.

### 15.3 Gateway tests

Add tests for:

- context tool calls proxy with auth headers.
- memory readiness failure returns `503`.
- no projection logic exists in gateway handlers.

### 15.4 Flutter parser/model tests

Add tests for:

- `parseExecutiveSummaryProjection` handles the full v1 fixture.
- missing optional sections produce empty defaults.
- invalid item lanes are ignored or mapped to `monitor`.
- coverage statuses parse correctly.
- action links parse correctly.

### 15.5 Flutter widget tests

Add tests for:

- Today screen renders all seven sections.
- metric cards route to expected detail pages.
- `Why this?` opens explanation drawer.
- loading and error states render cleanly.
- empty projection shows a useful empty state.
- refresh after completing a task reloads the projection.

### 15.6 Golden tests

Add light-theme golden tests for:

- normal populated Today screen
- empty Today screen
- degraded memory coverage
- narrow layout

## 16. Implementation order

1. Add memory domain types for `ExecutiveSummaryProjection`.
2. Add memory projection engine with deterministic policies.
3. Add MCP tools: `project_executive_summary`, `explain_executive_summary_item`.
4. Add memory server tests and JSON fixtures.
5. Add harness/tool allow-list entries and context API tests.
6. Add Flutter parser/domain model tests.
7. Add `ExecutiveSummaryClient`.
8. Add Today controller/state.
9. Build Today widgets using current app visual style.
10. Wire sidebar `Today` route to the new screen.
11. Add screen command snapshot support.
12. Add widget/golden tests.
13. Add docs page describing the Today projection contract.

## 17. Acceptance criteria

The implementation is complete when:

- The Today page loads from `project_executive_summary`.
- The UI does not compute ranking, lanes, open-loop categories, or coverage status itself.
- Slack/chat can ask for the same summary through the agent and receive a useful text answer.
- Every surfaced item has a reason and can be explained.
- Unsupported data sources are shown as unknown, not inferred.
- Task mutations refresh Today.
- The gateway contains no Today-specific scoring logic.
- The harness exposes the projection through the same MCP tool path used by the agent.
- Tests cover memory projection, harness tool exposure, gateway proxying, UI parsing, and widget rendering.

## 18. First fixture shape

Use this fixture as the first parser and widget test contract.

```json
{
  "schema_version": "agent-awesome/executive-summary/v1",
  "generated_at": "2026-05-09T09:24:00Z",
  "horizon": "today",
  "title": "Today",
  "subtitle": "Here is what matters now.",
  "narrative_summary": "You have 2 decisions, 3 actions, 1 relationship loop, and 4 items Agent Awesome can handle.",
  "metrics": [
    { "id": "decisions", "label": "Decisions", "value": "2", "subtitle": "Require your input", "severity": "attention", "link": { "route": "/attention?lane=decide" } },
    { "id": "actions", "label": "Actions", "value": "3", "subtitle": "Need your attention", "severity": "normal", "link": { "route": "/attention?lane=do" } },
    { "id": "relationships", "label": "Relationships", "value": "1", "subtitle": "Needs your care", "severity": "warning", "link": { "route": "/attention?lane=repair" } },
    { "id": "agent_can_handle", "label": "Agent can handle", "value": "4", "subtitle": "Ready to act", "severity": "good", "link": { "route": "/delegation" } },
    { "id": "picture_quality", "label": "Picture quality", "value": "Good", "subtitle": "Strong overall", "severity": "good", "link": { "route": "/memory/coverage" } }
  ],
  "open_loops": {
    "categories": [
      { "id": "orphan_tasks", "label": "Orphan tasks", "count": 3 },
      { "id": "stale_promises", "label": "Stale promises", "count": 2 },
      { "id": "waiting_on", "label": "Waiting on", "count": 5 },
      { "id": "blocked", "label": "Blocked", "count": 2 },
      { "id": "metadata_gaps", "label": "Metadata gaps", "count": 4 }
    ]
  },
  "attention": {
    "items": [
      { "id": "attention:protect:q3", "lane": "protect", "kind": "task", "title": "Deep work block for Q3 forecast", "reason": "High value, high risk, focus required", "estimate_minutes": 90 },
      { "id": "attention:decide:vendor", "lane": "decide", "kind": "task", "title": "Approve or defer vendor payment prep", "reason": "Financial decision needs your approval" },
      { "id": "attention:do:milk", "lane": "do", "kind": "task", "title": "Buy milk", "reason": "Small isolated task, easy to forget" },
      { "id": "attention:delegate:jordan", "lane": "delegate", "kind": "task", "title": "Draft Jordan follow-up", "reason": "Low human effort; Agent Awesome can draft" },
      { "id": "attention:repair:sarah", "lane": "repair", "kind": "task", "title": "Reply to Sarah", "reason": "Promise made; relationship follow-up" },
      { "id": "attention:monitor:budget", "lane": "monitor", "kind": "task", "title": "Budget review waiting on Alex", "reason": "No action needed; keep on radar" }
    ]
  },
  "delegation": {
    "buckets": [
      { "id": "can_do_now", "label": "Agent can do now", "count": 4, "items": [] },
      { "id": "needs_approval", "label": "Needs your approval", "count": 2, "items": [] },
      { "id": "running", "label": "Running", "count": 3, "items": [] },
      { "id": "done", "label": "Done", "count": 5, "items": [] }
    ]
  },
  "time_horizon": {
    "buckets": [
      { "id": "now", "label": "Now", "count": 5, "summary": "2 decisions, 3 actions" },
      { "id": "next", "label": "Next", "count": 3, "summary": "1 priority, 2 actions" },
      { "id": "today", "label": "Today", "count": 6, "summary": "High focus" },
      { "id": "tomorrow", "label": "Tomorrow", "count": 3, "summary": "Medium focus" },
      { "id": "this_week", "label": "This Week", "count": 8, "summary": "Plan ahead" }
    ]
  },
  "risk_unblocks": {
    "chains": [
      {
        "id": "risk:budget",
        "nodes": [
          { "title": "Collect forecast inputs", "subtitle": "Waiting on Alex" },
          { "title": "Review May budget", "subtitle": "Needs your input" },
          { "title": "Budget decision", "subtitle": "Blocked" }
        ],
        "suggested_action": { "label": "Nudge Alex for forecast inputs", "safety": "safe" }
      }
    ]
  },
  "coverage": {
    "good": ["Tasks & projects", "Task relations", "Commitments", "People & contacts"],
    "partial": ["Some missing due dates", "Some missing next actions", "Some missing projects"],
    "not_connected": ["Calendar", "Email", "Health / Sleep", "Banking / Bills"],
    "promise": "I only use information that is source-backed in memory."
  }
}
```
