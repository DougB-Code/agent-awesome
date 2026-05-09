## Files / areas to plan around first

* `harness/internal/runtime/config.go`
* `harness/internal/model/adapters/litert/litert.go`
* `harness/internal/agent/...` or new `harness/internal/runtime/callbacks/...`
* `gateway/internal/policy/runtime.go`
* `gateway/internal/gateway/server.go`
* `gateway/internal/slack/agent.go`
* `gateway/internal/config/config.go`
* `lib/app/app_config.dart`
* `lib/clients/assistant_client.dart`
* `lib/app/config_files.dart`
* `pilots/personal-assistant/agent.yaml`
* `deploy/cloudflare/config/agent.yaml`
* `deploy/cloudflare/config/tool.yaml`
* `test/...` and `harness/internal/.../*_test.go`

## Correction: canonical naming

Use:

* **Display/product name:** `Agent Awesome`
* **Machine-safe agent/app id:** `agent_awesome`
* **Policy prefix:** `AGENT_AWESOME_*`
* **Task idempotency prefix:** `agent_awesome:<session_id>:<normalized_task_title>`

Do **not** keep `personal_pilot`, `agent_gateway`, or `Aurora` as hidden aliases unless you explicitly decide to preserve old persisted data. The current repo is already partially aligned: Cloudflare config identifies the assistant as Agent Awesome, and the gateway policy prefix is `[[AGENT_AWESOME_RUNTIME_POLICY:`. But other areas still default to `personal_pilot`, and some UI names still use Aurora naming.   

## Target architecture

Use **Hexagonal Architecture / Ports and Adapters** as the high-level pattern:

```text
Flutter UI / Slack
  -> Agent Awesome Gateway
  -> ADK-compatible harness runner
  -> Google ADK llmagent
  -> model adapter
       - Gemini/native model: structured tool calls
       - LiteRT/Gemma: text protocol -> structured genai.FunctionCall
  -> ADK tool loop
  -> MCP memory/task toolset
  -> memory/task persistence
```

The key rule: **only ADK executes tools**. LiteRT parsing should only convert local-model markup into ADK/GenAI structured function-call parts. The UI and gateway should never execute a task from raw assistant text. ADK events are explicitly designed to carry text, tool-call requests, tool results, state changes, and control signals as event content/actions, so Agent Awesome should consume that event stream instead of inventing another chat/tool protocol. ([Google GitHub][1])

---

# Long-term implementation steps

## 1. Lock down the Agent Awesome identity boundary

**Goal:** eliminate split identity before moving more logic into ADK.

### Steps

1. Change all default ADK app names from `personal_pilot` to `agent_awesome`.
2. Update local pilot config:

   * `pilots/personal-assistant/agent.yaml`
   * likely rename folder to `pilots/agent-awesome/` if you want holistic naming.
3. Update gateway defaults:

   * `AGENTAWESOME_APP_NAME` fallback should become `agent_awesome`.
   * generated health/session URLs should use `agent_awesome`.
4. Update Flutter defaults:

   * `agentAppName` fallback should become `agent_awesome`.
   * test fixtures should stop asserting `personal_pilot`.
5. Update idempotency key generation everywhere:

   * from `personal_pilot:*` or `agent_gateway:*`
   * to `agent_awesome:<session_id>:<slug>`
6. Rename UI-facing Aurora classes, labels, tests, and config helpers to Agent Awesome equivalents.

### Acceptance criteria

* `grep -R "personal_pilot\|agent_gateway\|Aurora" .` returns only intentional migration notes or old-data migration tests.
* New chat sessions are created under ADK app id `agent_awesome`.
* New task idempotency keys start with `agent_awesome:`.

### Pushback

A hard rename can orphan old session/task associations, because existing UI tests and task fixtures show `personal_pilot` idempotency keys.  Do not solve that with silent compatibility aliases. Better options:

| Option                      | Pros                                               | Cons                                               |
| --------------------------- | -------------------------------------------------- | -------------------------------------------------- |
| Hard rename only            | Cleanest architecture; no duplicate identity logic | Old sessions/tasks may not associate automatically |
| Explicit one-time migration | Preserves history while keeping one canonical name | Requires careful operator script and rollback plan |

Recommended: **hard rename code + explicit one-time data migration**, not ongoing compatibility shims.

---

## 2. Move stable behavior from runtime prompt injection into ADK agent configuration

**Goal:** stop hiding operating policy inside user text.

Right now, the gateway injects runtime policy into `newMessage.parts[].text`, including task behavior and session-specific idempotency instructions. That is better than UI-side injection, but it still pollutes the user-message channel. 

### Steps

1. Move stable identity and task behavior into `agent.yaml` / ADK `llmagent.Config.Instruction`.
2. Use `InstructionProvider` only for truly dynamic instruction content.
3. Remove UI-owned runtime policy injection entirely.
4. Convert `gateway/internal/policy/runtime.go` from default-on behavior to either:

   * deleted, once ADK instruction/callbacks cover the behavior; or
   * disabled by default and reserved only for emergency operator override.
5. Add a regression test proving user input sent to harness is raw user text, not prefixed policy text.

ADK Go supports `Instruction`, `GlobalInstruction`, and `InstructionProvider` on `llmagent.Config`, which is the right place for agent behavior that should apply across turns. ([Go Packages][2])

### Acceptance criteria

* User says: `remember to buy milk`.
* Harness receives the user text as plain user text.
* ADK agent still decides to call `create_task`.
* No `[[AGENT_AWESOME_RUNTIME_POLICY:` text appears in session history.

---

## 3. Add ADK tool callbacks for task invariants

**Goal:** enforce Agent Awesome business rules outside the model.

Use the **Callback Chain pattern** here.

The model should decide **whether** to call `create_task`; Agent Awesome code should enforce **how** that call is normalized. ADK Go exposes `BeforeToolCallback`, and its docs explicitly say a callback can modify tool args in place and return `(nil, nil)` so the tool still runs. ([Go Packages][2])

### New package

Recommended location:

```text
harness/internal/runtime/callbacks/
```

or, if the harness has an agent-composition package:

```text
harness/internal/agent/callbacks/
```

### Callback responsibilities

Create a `TaskPolicyCallback` or `AgentAwesomeTaskCallbacks` component with one responsibility: normalize task-tool calls.

For `create_task`:

* Require or derive `title`.
* Normalize empty `description`.
* Fill `idempotency_key` if missing.
* Use prefix: `agent_awesome:<session_id>:<slug>`.
* Never ask the model to invent idempotency keys.
* Never return a fake tool result unless the call is invalid and must be blocked.

For `update_task`, `complete_task`, `cancel_task`, `delete_task`:

* Validate required identifiers.
* Optionally normalize lifecycle fields.
* Do not auto-fill ambiguous task IDs.

### Important design detail

Do not store idempotency rules in LiteRT parsing. The LiteRT adapter should only produce a valid `FunctionCall`. Idempotency is an Agent Awesome domain invariant, so it belongs in ADK tool callbacks.

### Acceptance criteria

* A model call with only `{title: "Buy milk"}` becomes a tool call with:

  * `title: "Buy milk"`
  * `idempotency_key: "agent_awesome:<session_id>:buy_milk"`
* A repeated `remember to buy milk` request does not duplicate the task.
* The same behavior works for LiteRT/Gemma and cloud models.

---

## 4. Keep MCP tools as the ADK tool boundary

**Goal:** let Google ADK own tool exposure, confirmation, and tool execution flow.

Your tool config already exposes memory/task MCP tools, including `create_task`, `get_task`, `list_tasks`, `update_task`, `complete_task`, and related graph tools.  ADK Go’s `mcptoolset.New` creates an MCP `Toolset`, connects to the MCP server, retrieves MCP tools as ADK tools, and passes them to the LLM through `llmagent.Config.Toolsets`. ([Go Packages][3])

### Steps

1. Keep task/memory tools behind MCP.
2. Use ADK `Toolsets`, not app-side tool dispatch.
3. Use `tool.FilterToolset` / `AllowedToolsPredicate` to expose only approved tools.
4. Keep task tools auto-approved if that remains your desired behavior.
5. Keep sensitive memory mutation tools confirmation-gated.
6. Use ADK confirmation support for HITL flows instead of custom UI-only approval logic where possible.

ADK’s tool package supports predicates for dynamic tool exposure and confirmation providers for Human-in-the-Loop approval; note that the docs mark confirmation provider support as experimental, so keep that isolated behind a small Agent Awesome adapter. ([Go Packages][4])

### Acceptance criteria

* Gateway/UI never maintain their own tool registry for chat execution.
* The tool allow-list lives in runtime/tool config.
* ADK emits function-call and function-response events for tool activity.
* Confirmation tools render through the same event path as normal tool calls.

---

## 5. Treat LiteRT/Gemma as a compatibility adapter only

**Goal:** local Gemma should behave like a structured-function-calling model from ADK’s point of view.

Use the **Adapter pattern** here.

ADK’s model interface returns `LLMResponse`, whose `Content` is a `genai.Content`; tool calls must be represented as structured content parts, not raw assistant text. ([Go Packages][5]) The immediate fix makes the adapter parse Gemma’s nested tool-call markup. Long term, the adapter needs a stricter contract.

### Steps

1. Keep all Gemma text-protocol parsing inside `harness/internal/model/adapters/litert`.
2. Convert recognized tool markup into `genai.Part.FunctionCall`.
3. Convert malformed tool markup into a non-user-visible model error or safe assistant text.
4. Never execute tools from LiteRT adapter code.
5. Add golden tests for:

   * normal text
   * standard tool call
   * nested Gemma wrapper call
   * malformed tool markup
   * mixed text + tool markup
   * repeated tool-call retries
6. Add a small fuzz test for `decodeLooseObject` / tool markup parsing.

### Acceptance criteria

* Raw `<|tool_call>` never reaches UI, Slack, or stored assistant-visible transcript.
* ADK sees a real `FunctionCall`.
* The same downstream ADK tool loop runs for LiteRT and non-LiteRT models.

---

## 6. Make event rendering ADK-native in UI and Slack

**Goal:** display ADK events, not provider artifacts.

ADK docs describe events as the standard communication format between UI, runner, agents, LLMs, and tools, with function-call and function-response detection based on content parts. ([Google GitHub][1])

### Steps

1. In Flutter, parse assistant events by part type:

   * `text` -> chat message text
   * `functionCall` -> tool activity
   * `functionResponse` -> tool result activity
   * confirmation request -> confirmation UI
2. In Slack, mirror the same parsing rules.
3. Never display raw local-model control markup.
4. Do not infer successful task creation from assistant prose.
5. Prefer rendering task success from `functionResponse`, then let the final assistant text summarize it.

### Acceptance criteria

* Tool calls show as quiet activity or structured status, not raw model text.
* Final answer says something like: `Done - added Buy milk.`
* If the tool fails, the UI shows the tool failure clearly and the assistant does not pretend it succeeded.

---

## 7. Remove duplicate policy injection paths

**Goal:** one owner for runtime behavior.

Current direction should be:

```text
ADK agent config + ADK callbacks = behavior
gateway = auth/channel/proxy/service readiness
UI = display/input/local service control
```

### Steps

1. Remove UI-side runtime policy injection.
2. Remove or disable gateway `run_sse` body transformation once ADK instruction/callbacks are active.
3. Keep gateway readiness/auth/CORS/proxy behavior.
4. Add a test that passes a `run_sse` request through the gateway and asserts no policy prefix is inserted.
5. Add a test that direct harness calls and gateway-routed calls produce equivalent ADK events.

### Acceptance criteria

* No double-injected instructions.
* No hidden policy text in user messages.
* Gateway remains transport-safe but not agent-brain logic.

---

## 8. Add end-to-end chat/tool contract tests

**Goal:** prove the entire system is stable, not just the parser.

### Required tests

1. **LiteRT parser contract**

   * Input: Gemma nested wrapper call.
   * Expected: one structured `FunctionCall` named `create_task`.

2. **ADK tool loop contract**

   * Stub model emits `create_task`.
   * ADK executes MCP tool once.
   * Final event contains function response.

3. **Idempotency contract**

   * Same session + same title twice.
   * Expected: one task, one stable idempotency key.

4. **Gateway parity contract**

   * Direct harness call and gateway call both create the same task shape.
   * No policy prefix is present in stored user text.

5. **UI rendering contract**

   * Function call is displayed as activity.
   * Function response is displayed as result.
   * Raw `<|tool_call>` text is suppressed.

6. **Slack rendering contract**

   * Same as UI, but through Slack adapter.

7. **Malformed local-model output contract**

   * Malformed tool markup never becomes visible chat text.
   * No tool is executed from malformed text.

### Acceptance criteria

This user input should pass in local LiteRT mode and cloud-model mode:

```text
remember to buy milk
```

Expected result:

```text
- create_task called once
- title: Buy milk
- idempotency_key starts with agent_awesome:<session_id>:
- no raw tool markup shown
- final assistant message confirms the task
```

---

## 9. Add observability around the ADK boundary

**Goal:** debug tool-call failures without dumping private content.

### Metrics / logs

Add structured logs for:

* model adapter response type: `text`, `function_call`, `malformed_tool_markup`
* ADK function call emitted
* ADK tool execution started
* ADK tool execution completed
* ADK tool execution failed
* duplicate task prevented by idempotency
* confirmation requested / approved / rejected

Keep payloads redacted by default. The project guidance emphasizes production-grade behavior, preserving structured-output contracts, and logging major workflow milestones without dumping excessive detail. 

### Acceptance criteria

A failed “remember to buy milk” run should make it obvious whether the problem was:

* model failed to call tool
* LiteRT adapter failed to parse
* ADK did not execute tool
* MCP tool failed
* UI failed to render

---

## 10. Document the final architecture

**Goal:** make the design enforceable.

### Add docs

Recommended new docs:

```text
docs/modules/development/pages/chat-architecture.adoc
docs/modules/development/pages/tool-calling-contract.adoc
docs/modules/development/pages/litert-adapter-contract.adoc
docs/modules/development/pages/task-idempotency.adoc
```

### Include these rules

* Agent Awesome is the canonical product name.
* Machine id is `agent_awesome`.
* ADK owns the tool loop.
* LiteRT adapter converts local text protocol to structured ADK content.
* Memory/task persistence remains MCP-backed.
* UI and Slack render ADK events only.
* Runtime policy must not be injected into user-visible text.
* Idempotency is enforced by callback/domain logic, not prompt compliance.

---

# Implementation order I recommend

1. **Canonical rename:** `personal_pilot` / `agent_gateway` / `Aurora` -> Agent Awesome equivalents.
2. **Add ADK task callbacks:** start with `create_task` idempotency.
3. **Move task policy into ADK instruction/config.**
4. **Disable gateway text-policy injection.**
5. **Keep LiteRT parser as adapter-only and expand golden tests.**
6. **Unify UI + Slack event rendering around ADK function parts.**
7. **Add end-to-end chat/tool tests.**
8. **Add observability.**
9. **Document the architecture.**
10. **Run explicit old-data migration only if preserving old sessions/tasks matters.**

The most important architectural move is step 2: **make Agent Awesome invariants callbacks/domain logic, not model instructions.** A 2B local model can decide to call a tool, but it should not be trusted to reliably produce stable idempotency keys, schema edge cases, or product-level naming conventions.

[1]: https://google.github.io/adk-docs/events/ "Events - Agent Development Kit (ADK)"
[2]: https://pkg.go.dev/google.golang.org/adk/agent/llmagent "llmagent package - google.golang.org/adk/agent/llmagent - Go Packages"
[3]: https://pkg.go.dev/google.golang.org/adk/tool/mcptoolset "mcptoolset package - google.golang.org/adk/tool/mcptoolset - Go Packages"
[4]: https://pkg.go.dev/google.golang.org/adk/tool "tool package - google.golang.org/adk/tool - Go Packages"
[5]: https://pkg.go.dev/google.golang.org/adk/model "model package - google.golang.org/adk/model - Go Packages"
