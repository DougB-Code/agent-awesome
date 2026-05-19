# Command Design Audit

## Scope

This audit covers the current Agent Awesome UI shell as implemented in the Flutter codebase. It inventories each top-level menu section, each left command-panel area, each right detail panel or mode, and the one section that has a second-level labeled tab menu.

The terms below are used consistently:

- **Menu section**: top-level sidebar item.
- **Left panel area**: the selectable command area in the left pane of `CommandPanelSubShell`.
- **Right panel mode**: the icon-mode selector in the right pane.
- **Tab menu**: labeled text tabs inside a selected right panel mode.
- **Item selector**: a right-pane quick selector used for selected profiles or memory domains.

## Shared Shell Baseline

Most workspaces use the reusable command-panel shell:

- A bordered two-pane frame with a resizable split.
- A left pane header with title, quick-access icon areas, optional actions, shell-owned fuzzy search, and optional quick filters.
- A right pane header with title, icon detail modes, optional selected-item dropdown, optional CRUD actions, optional detail search, and optional labeled tabs.
- Shared surfaces are 8px-radius bordered panels with either `PanelSurfaceStyle.primary` for pane backgrounds or `PanelSurfaceStyle.card` / `PanelSectionBlock.gradient` for content blocks.
- Empty states generally use `PanelEmptyBlock`, which is itself a bordered card-like block.

Forms in Settings and tool configuration generally use:

- `FormPanel`: scrollable form body with 24px padding and separated sections.
- `FormSectionCard`: a titled `PanelSectionBlock.gradient`.
- Shared input decoration, autosave feedback, dropdowns, and read-only fields.

Not every section uses the command shell. Today and Today Attention are route-level dashboard/detail surfaces rather than command-panel surfaces.

## Global Menu Inventory

| Menu group | Menu sections |
|---|---|
| Home & Chat | Today, Chat, Backlog |
| Automations | Operations, Workflows, Tasks, Agents, MCP Servers, Tools |
| Knowledge | Memory, Files, People |
| System | Settings |

## Section Inventory

| Menu section | Left panel areas | Right panel modes | Tab menu |
|---|---|---|---|
| Today | Dashboard content | None | None |
| Today Attention route | Attention queue | Attention details | Filter chips: All, Clarify, Schedule, Review |
| Chat | Conversation | Memory, Tasks, Files, People, Runtime | None |
| Backlog | Queue, Stream, WBS, Constellation, Capture | Queue: Inspector, Memory, AI review when available. Stream: Inspector, Memory. WBS: WBS, Inspector. Constellation: Graph, Inspector. Capture: Capture, Memory. | None |
| Operations | Operations | Overview, History, Safety | None |
| Workflows | Workflows | Overview, Steps, Map, Safety | None |
| Tasks | Tasks, Nodes | Builder, Overview, Safety | None |
| Agents | Agent Profiles | Profile | Overview, Instructions, Permissions, Used In |
| MCP Servers | MCP Servers | Selected MCP server config editor | None |
| Tools | Tools | Selected local tool config editor | None |
| Memory | Search, Review, Safety, Map, Capture | Overview, Source, Relations, Metadata, Corrections, Pages | None |
| Files | Files | Details, Source, Access | Left quick filters: All files, Documents, Sheets, Images, Other |
| People | Contacts | Profile, Contexts, Activity, Sources, Page | Left quick filters: All contacts, Active, Sources, Multi-context, Task owners |
| Settings | Settings | App, Profiles, Models, Memory | Right item selectors for Profiles and Memory |

## Today

### Dashboard

Purpose: give a daily operational summary of projected work, attention needs, delegation, and schedule.

Content:

- Open Loop Radar.
- Today's Attention.
- Delegation & Agent.
- Schedule.
- Optional error banner above the primary cards.

Styling:

- Uses `TodaySectionCard`, not `CommandPanelSubShell`.
- Cards are bordered, 8px radius, surface gradient, uppercase compact titles, optional route link in the card header.
- Primary cards are arranged in a responsive row on wide screens and a stacked column on narrow screens.
- No shell search, no left/right split, no tab bar.

### Attention Route

Purpose: expand the Today attention summary into an explainable triage surface.

Content:

- Header with breadcrumb-style title, subtitle, refresh, and explanation action.
- Filter chip row: All, Clarify, Schedule, Review.
- Left attention item list.
- Right attention details panel on wide screens; stacked under list on narrow screens.

Styling:

- Route-level custom layout, not command shell.
- Uses bordered attention cards, score blocks, tags, and a details panel.
- Has local filter chips rather than shell-owned quick filters.
- Search is absent; filtering is categorical.

## Chat

### Left Panel: Conversation

Purpose: read and continue the selected chat session.

Content:

- Chat timeline.
- Message composer.
- Chat session picker in the command panel header.
- Shell fuzzy search filters messages by author/text.

Styling:

- Uses `CommandPanelSubShell`.
- Left area tabs are hidden in the auxiliary compact chat panel, visible in the main Chat workspace only as a single Conversation area.
- Conversation rows use chat-specific row components rather than generic cards.

### Right Panel: Memory

Purpose: show memory records used by the selected chat.

Content:

- Up to 12 memory context tiles.
- Empty state when no memory is attached.

Styling:

- Right detail mode icon tab.
- Uses titled context sections and small context tiles.
- No right-side detail search.

### Right Panel: Tasks

Purpose: show tasks linked to the selected chat.

Content:

- Up to 12 task context tiles.
- Empty state when no tasks are linked.

Styling:

- Same context-panel treatment as Memory.
- No tab menu.

### Right Panel: Files

Purpose: show file/source context attached to the selected chat.

Content:

- File memory records.
- Source items not already represented by file records.
- Empty state when no files are attached.

Styling:

- Context tiles inside a scrollable right pane.
- No right-side search.

### Right Panel: People

Purpose: show people/contact context related to the selected chat.

Content:

- Person/contact context tiles.
- Empty state when none are linked.

Styling:

- Same right-pane context style as the other chat detail modes.

### Right Panel: Runtime

Purpose: summarize the runtime/profile/model context for the chat.

Content:

- Runtime/profile status and related configuration values.

Styling:

- Uses compact right-pane blocks.
- No search or nested tabs.

## Backlog

### Left Panel: Queue

Purpose: manage operational backlog items.

Content:

- Shell search.
- Task filter strip.
- Task queue tiles with status, priority, dates, topics, and row actions such as schedule, snooze, and complete.

Styling:

- Command shell left pane.
- Queue items are repeated bordered cards with selection/focus states.
- The filter strip is content-level, not a labeled shell tab.

Right modes:

- Inspector: selected task editor/details.
- Memory: selected task memory links.
- AI review: screen-command review queue, only when changes are available.

### Left Panel: Stream

Purpose: visualize tasks as stream/axis projections.

Content:

- Stream projection canvas.
- Axis selectors and stream filter controls.
- Focus controls inside the visualization.

Styling:

- Command shell area with shell search available but the visualization also has domain-specific controls.
- Uses canvas-like full content rather than a list of cards.
- Empty state uses `PanelEmptyBlock`.

Right modes:

- Inspector.
- Memory.

### Left Panel: WBS

Purpose: view work-breakdown structure across tasks.

Content:

- Work package/tree projection.
- Work package content cards.

Styling:

- Uses command shell area.
- WBS visual content uses `PanelSectionBlock`-style bordered sections.

Right modes:

- WBS: metrics and work package summary cards.
- Inspector: selected task editor/details.

### Left Panel: Constellation

Purpose: visualize task relationships and contextual graph structure.

Content:

- Graph query field.
- Saved query menu.
- Clear/collapse controls.
- Pan/zoom graph canvas.
- Zoom/recenter controls.
- Optional query result rows and summary.

Styling:

- Command shell area, but with local graph-specific toolbar controls inside the content.
- Main graph is framed in `PanelSectionBlock`.
- Uses icon badge buttons and compact query field styling.

Right modes:

- Graph: constellation metrics and selected task summary.
- Inspector: selected task or selected edge inspector.

### Left Panel: Capture

Purpose: create a backlog item from quick context.

Content:

- Task form with title, description, status, priority, due/scheduled dates, topics, and optional selected-memory link.
- Create Backlog Item action.
- Nearby Backlog suggestions.

Styling:

- Uses `PanelSectionBlock` form sections.
- Form controls are task-specific, not Settings form primitives.
- Nearby tasks reuse queue tile cards.

Right modes:

- Capture: context summary for task counts and selected memory.
- Memory: selected task memory links.

## Operations

### Left Panel: Operations

Purpose: observe published automations, runs, and pending inbox items.

Content:

- Inbox section.
- Published automations section.
- Runs section.
- Header refresh action.
- Shell search over runs and definitions.

Styling:

- Command shell with one left area.
- Content uses stacked titled `PanelSectionBlock` cards.
- Tiles are bordered card rows within sections.

Right modes:

- Overview: counts for published definitions, drafts, inbox items, recent runs, and selected run.
- History: selected automation event list.
- Safety: action risk list.

Styling of right modes:

- Overview uses simple detail rows.
- History uses event tiles.
- Safety uses a titled `Action Risk` panel with action tiles.
- No second-level tab menu.

## Workflows

### Left Panel: Workflows

Purpose: author long-lived state-machine workflow drafts.

Content:

- Drafts section.
- Templates section.
- Header action for creating a workflow draft.
- Shell search.

Styling:

- Command shell with one left area.
- Titled `PanelSectionBlock` sections.
- Draft/template rows are bordered tiles.

Right modes:

- Overview: draft metadata plus Add Action section.
- Steps: workflow steps list and selected step details.
- Map: state map visualization.
- Safety: validation diagnostics.

Styling of right modes:

- Overview and Safety use stacked section cards.
- Steps uses plain section blocks for dense step editing.
- Map uses a state-map panel with card-like state nodes.
- No labeled tab menu.

## Tasks

### Left Panel: Tasks

Purpose: select and manage task DAG drafts.

Content:

- DAG draft list.
- Header action for creating a task DAG.
- Shell search.

Styling:

- Command shell with a relatively narrow left split.
- Drafts render as selectable automation tiles.

### Left Panel: Nodes

Purpose: provide a palette of DAG node/action types.

Content:

- Action/node palette for `agent.run`, `tool.call`, and `dag.run`-style nodes.
- Searchable through the shell query.

Styling:

- Shared shell left area.
- Palette items are card-like action tiles.
- No independent pane header.

Right modes:

- Builder: visual DAG editor with node graph and selected node controls.
- Overview: DAG metadata and selected-step form surface.
- Safety: validation diagnostics.

Styling of right modes:

- Builder uses a visual graph workspace and compact node cards.
- Overview uses form-like editing sections.
- Safety uses diagnostics in bordered sections.
- No labeled tab menu.

## Agents

### Left Panel: Agent Profiles

Purpose: select and manage reusable automation agent profiles.

Content:

- Agent profile list.
- Header action for creating an agent profile.
- Shell search.

Styling:

- Command shell with one left area.
- Profile rows are automation tiles/cards.

Right mode:

- Profile.

Tab menu inside Profile:

- Overview.
- Instructions.
- Permissions.
- Used In.

Styling:

- This is the only active right-pane labeled tab menu found in the command shell.
- Overview uses an `Agent Profile` section.
- Instructions uses an `Instructions` section.
- Permissions uses a `Permissions` section.
- Used In uses a `Used In` section listing workflow/task usage or an `Unused` empty block.

## MCP Servers

### Left Panel: MCP Servers

Purpose: select and manage tool configuration files for MCP server toolsets.

Content:

- Tool config file list filtered to the MCP server surface.
- Header actions: add, duplicate, delete config.
- Shell search with MCP-specific hint.

Styling:

- Uses `CommandPanelSubShell`.
- Config files are shown as bordered `PanelSurface.card` tiles with selected state.
- No left quick filters.

### Right Panel: Selected MCP Server Config Editor

Purpose: edit the MCP server tool config content.

Content:

- MCP toolsets card.
- Tool YAML preview.
- Empty/missing config state when needed.

Styling:

- Uses `FormPanel` and `FormSectionCard`.
- No right detail modes or labeled tabs.
- No independent shell controls inside the editor.

## Tools

### Left Panel: Tools

Purpose: select and manage local/OS tool configuration files.

Content:

- Tool config file list filtered to the local tool surface.
- Header actions: add, duplicate, delete config.
- Shell search with tool-specific hint.

Styling:

- Same command shell structure as MCP Servers.
- Config tiles use bordered card surfaces with selected state.

### Right Panel: Selected Local Tool Config Editor

Purpose: edit local command/tool configuration.

Content:

- Local exec card.
- Tool YAML preview.
- Empty/missing config state when needed.

Styling:

- Uses `FormPanel` and `FormSectionCard`.
- Local command rows use settings/tool field styling.
- No right modes or labeled tabs.

## Memory

### Left Panel: Search

Purpose: browse and retrieve memory records.

Content:

- Memory records filtered by shell query and memory filter state.
- Memory filter controls for firewall, sensitivity, global inclusion, and service search.
- Result cards/tiles.

Styling:

- Command shell left area with shell search.
- Content also includes memory-specific filter controls.
- Records are presented as card-like rows.

### Left Panel: Review

Purpose: inspect records that need review or stewardship.

Content:

- Review candidate records.
- Empty state when no records need review.

Styling:

- Uses `PanelSectionBlock` and card rows.

### Left Panel: Safety

Purpose: show memory safety events and policy-related history.

Content:

- Safety event list.
- Empty state when no memory safety events exist.

Styling:

- Titled section blocks and event cards.

### Left Panel: Map

Purpose: show graph-like relationships and memory distribution.

Content:

- Memory relationship/record map sections.
- Summary blocks and relationship groupings.

Styling:

- Uses stacked `PanelSectionBlock` cards.

### Left Panel: Capture

Purpose: create memory records from user-entered content.

Content:

- Capture form.
- Duplicate/nearby record hints.
- Capture result/status messaging.

Styling:

- Uses `PanelSectionBlock` form sections.
- Form controls are memory-specific rather than Settings form primitives.

Right modes:

- Overview: selected memory summary and evidence/status/topic sections.
- Source: source/evidence details.
- Relations: linked memory and task relationships.
- Metadata: editable metadata fields.
- Corrections: correction/supersession tools.
- Pages: compiled page/entity/timeline view.

Styling of right modes:

- The memory right pane uses shell-owned detail search.
- Overview, Source, Relations, Corrections, and Pages primarily use `PanelSectionBlock` cards.
- Metadata uses a plain section treatment for dense editing.
- Empty states use `PanelEmptyBlock`.

## Files

### Left Panel: Files

Purpose: browse indexed file-like memory records.

Content:

- File list.
- Header add-file action.
- Shell fuzzy search.
- Shell-owned quick filters: All files, Documents, Sheets, Images, Other.

Styling:

- File rows are custom bordered cards with 8px radius, card gradient, selected border, icon box, metadata badges, and a vertical accent stripe.
- Empty state can show an add-file action.

Right modes:

- Details: primary file summary and send-to-chat action.
- Source: source path/system/id/checksum style information.
- Access: firewall/sensitivity/trust/status access information.

Styling of right modes:

- Uses `PanelSectionBlock.gradient` inspector blocks.
- Details are shown in label/value rows.
- No second-level tabs.

## People

### Left Panel: Contacts

Purpose: browse contacts derived from memory records and task ownership.

Content:

- Contact list.
- Header add-contact action.
- Shell fuzzy search.
- Shell-owned quick filters: All contacts, Active, Sources, Multi-context, Task owners.

Styling:

- Contact rows mirror file cards: bordered 8px card, gradient, selected border, vertical accent stripe, icon box, metadata badges.
- Empty state can show an add-contact action.

Right modes:

- Profile: contact summary and editable/add-note affordances.
- Contexts: memory/task context slices.
- Activity: related tasks and recent activity.
- Sources: source memory records.
- Page: compiled contact page preview.

Styling of right modes:

- Uses gradient inspector blocks for profile and rows.
- Context cards use `PanelSectionBlock`/card treatments.
- Empty states use `PanelEmptyBlock`.
- No second-level tabs.

## Settings

### Left Panel: Settings

Purpose: select a settings category.

Content:

- App.
- Profiles.
- Models.
- Memory.
- Shell fuzzy search.

Styling:

- Settings categories render as `PanelSurface.card` tiles with icon, title, and detail text.
- Selected category uses the shared selected gradient/border.

### Right Panel: App

Purpose: edit app-owned configuration that is intentionally outside runtime profiles.

Content:

- Chat defaults.
- Default profile selector.
- Application models.
- Chat title summary toggle.
- Summary model selector.
- Memory firewall textarea.

Styling:

- Uses `FormPanel` and `FormSectionCard`.
- Uses shared settings fields, toggles, dropdowns, autosave feedback.
- Right-pane shell search filters the App content.

### Right Panel: Profiles

Purpose: edit the selected runtime profile.

Content:

- Right item selector lists runtime profile files.
- Header actions: add, duplicate, delete profile.
- Details section with profile name and JSON source.
- Assignments section with model, agent, and tool config dropdowns.

Styling:

- Selection and CRUD live in the shared right header.
- Content is `FormPanel`/`FormSectionCard`.
- Right-pane shell search filters selected profile content.

### Right Panel: Models

Purpose: edit model configuration and provider/model definitions.

Content:

- Model config path and assignment action.
- Add provider action.
- Provider action sections for default/duplicate/delete.
- Provider cards with adapter, credential, URL, models, default model.
- Provider YAML preview.

Styling:

- Uses `FormPanel` and `FormSectionCard`.
- Provider editor uses card-style sections and shared settings fields.
- Right-pane shell search filters providers.

### Right Panel: Memory

Purpose: edit graph-backed memory domain runtime settings.

Content:

- Right item selector lists memory domains.
- Header actions: add/delete memory domain.
- Effective access block.
- Memory domain form fields for label, domain id, endpoint, health URL, paths, package, arguments, and related runtime/access controls.

Styling:

- Selection and CRUD live in the shared right header.
- Uses `FormPanel`/`FormSectionCard` and shared settings field styling.
- Right-pane shell search filters selected memory-domain content.

## Auxiliary Assistant Chat Split

Purpose: provide assistant chat beside most non-Chat workspaces.

Content:

- Compact Conversation panel only.
- Chat session picker.
- Message timeline and composer.

Styling:

- Uses top-level `SplitPanelShell`, with the active workspace on the left and compact chat command panel on the right.
- The compact chat panel hides the right detail pane and area tabs.

## Cross-Panel Design Consistency Findings

1. Most major workspaces now use `CommandPanelSubShell`, which creates strong consistency for pane borders, search placement, collapse controls, right-mode buttons, and header actions.

2. Today is intentionally different. It is a dashboard route, not a command-panel workspace. Its card styling is compatible with the app palette, but it does not have shell search or left/right panel affordances.

3. Backlog has the widest variation. Queue is list/card based, Stream is canvas based, WBS is tree/section based, Constellation has an in-content graph toolbar and query field, and Capture is form based. This is domain-appropriate, but it is the least visually uniform section.

4. Automations is mostly consistent. Operations, Workflows, Tasks, and Agents share the focused command panel. Agents is the only place with a right-side labeled tab menu, which makes it stand out but matches the configured shell hierarchy.

5. Files and People are strongly paired. Both use a single left collection area, shell-owned quick filters, selected cards with accent stripes, and right inspector modes.

6. Settings is now shell-compliant. Category selection is in the left shell area; Profiles and Memory selection/CRUD live in the right shell header; section content is form-only.

7. Search behavior varies by intent. Shell search is present across command-panel left areas. Right-side search appears in Memory and Settings detail surfaces. Today has no search. Chat right modes do not have right-side search.

8. Card treatment is mostly consistent: repeated selectable items use bordered 8px cards; inspector/form sections use `PanelSectionBlock.gradient` or `FormSectionCard`; dense editors sometimes use plain sections to reduce visual weight.

9. Local domain controls still exist where they express domain logic rather than shell navigation: Backlog Queue filter strip, Stream axis/filter controls, Constellation graph query/zoom controls, Memory filter controls, Today Attention filters. These should remain content controls unless promoted into shared shell concepts.

## Style Audit

This section audits visual style rather than shell compliance. The shell model is now aligned; the remaining inconsistencies are mostly about surface treatment, density, empty states, selectable cards, form fields, badges, and when panels use custom controls instead of shared primitives.

### Shared Style Baseline

The strongest shared style primitives are:

- `CommandPanelSubShell`: establishes pane borders, header padding, uppercase pane labels, quick-access icon buttons, shell search, optional filters, detail modes, item selectors, and collapse buttons.
- `PanelIconButton`: 36x36 icon-only control, 8px radius, bordered, muted icon, selected gradient/border, disabled opacity.
- `PanelSurface`: 8px bordered surface with `primary` and `card` styles.
- `PanelSectionBlock` / `PanelSectionBlock.gradient`: general bordered content sections.
- `FormPanel` / `FormSectionCard`: settings-style form layout with 24px body padding and 18px card padding.
- `PanelBadge`: common metadata/status chip.
- `PanelEmptyBlock` and `PanelEmptyState`: two different empty-state treatments.

The main style risk is not the lack of primitives; it is that multiple panels still solve the same visual problem with local variants.

## Panel-by-Panel Style Findings

### Today Dashboard

Purpose: dashboard summary, not a command workspace.

Style:

- Uses `TodaySectionCard` instead of command-panel chrome.
- Bordered 8px cards, gradient backgrounds, uppercase card titles, compact dashboard density.
- Uses custom dashboard chips, route links, and timeline buckets.

Inconsistencies:

- Outer padding and card rhythm are larger than command panels, which is acceptable for a dashboard but should be named as a distinct `dashboard` style.
- Today uses several custom pill/chip styles rather than `PanelBadge`.
- Empty/error styling is route-specific rather than shared with command-panel empty/error states.

### Today Attention Route

Purpose: focused triage route for attention items.

Style:

- Custom route shell with left item list and right details.
- Attention item cards use 8px radius, gradient selected state, accent stripe, status tags, and filter chips.
- Details panel uses bordered blocks and compact label/value content.

Inconsistencies:

- Filter chips are local and visually different from command-panel quick filters.
- The selected-card treatment resembles Files/People/Backlog but is implemented separately.
- Uses route-level header/action styling rather than command shell header styling.

### Chat

Purpose: conversation plus contextual right modes.

Style:

- Main Chat uses command shell; auxiliary chat uses compact shell with detail pane hidden.
- Chat session tiles use `PanelSurface.card`.
- Conversation timeline uses chat bubbles/rows rather than card sections.
- Composer has a wide layout and a compact right-panel layout.
- Context modes use simple scroll lists and small context tiles.

Inconsistencies:

- Chat timeline intentionally diverges from card-based panels, but context tiles should have a named shared style.
- The chat composer is its own control family; it needs explicit sizing rules for full-width and narrow right-panel use.
- Chat right modes generally do not expose right search, while Memory/Settings detail panels do. This is acceptable, but the rule should be explicit: only searchable detail surfaces get detail search.

### Backlog

Purpose: operational task management, visual task analysis, and capture.

Style:

- Queue uses selectable task cards with accent stripe, metadata badges, and compact action chips.
- Stream and Constellation use canvas/graph surfaces with local toolbars and zoom/focus controls.
- WBS uses tree/card structures inside bordered sections.
- Capture uses form-like sections plus nearby task cards.
- Right modes use inspector cards, memory-link panels, review cards, graph details, and tabbed subviews where the active mode owns subviews.

Inconsistencies:

- Queue cards, Stream task cards, Constellation cards, and WBS nodes are visually related but not governed by one card taxonomy.
- Some form controls in Capture and Inspector are task-specific rather than shared command-panel form fields.
- Canvas controls use local visual treatments; this is domain-appropriate but should become a shared `canvas toolbar` variant.
- Empty states alternate between `PanelEmptyBlock`, plain centered copy, and section-contained empty blocks.
- Backlog has the greatest density variation: Queue is dense cards, Stream is expansive canvas, Capture is form-like. This is acceptable only if the style guide names these as separate panel archetypes.

### Operations

Purpose: observe automation inbox, published automations, and run history.

Style:

- Single left command area with stacked automation sections.
- Rows/cards use bordered tiles, badges, and compact metadata.
- Right modes use simple section blocks for Overview, History, and Safety.

Inconsistencies:

- Overview uses detail rows and metric summaries that are quieter than the card-heavy left side.
- History and Safety event rows should share one event-card style with Memory Safety and People Activity.
- Empty states are `PanelEmptyBlock`, consistent but visually heavier than filtered `PanelEmptyState`.

### Workflows

Purpose: author workflow drafts and inspect steps/map/safety.

Style:

- Left side uses automation list tiles inside sections.
- Overview/Safety use stacked section blocks.
- Steps uses plainer, denser section blocks for editing.
- Map uses state cards with badges.

Inconsistencies:

- Steps editing has a different density and section treatment than Settings forms, despite both being editable configuration surfaces.
- Template and draft cards are visually close to task/agent cards but not formally shared.
- Map state cards resemble graph/node cards but use separate styling.

### Tasks

Purpose: build task DAGs and manage DAG drafts/nodes.

Style:

- Left areas use draft cards and node-palette cards.
- Builder is a full graph workspace with node cards and inline node toolbars.
- Overview and Safety use section blocks.

Inconsistencies:

- DAG node cards have a distinct visual language from Backlog graph cards and Workflows map cards.
- Node toolbars use compact local icon rows; these should share the same canvas-toolbar rule as Backlog visualizations.
- Palette cards and draft cards should use a named selectable-card variant.

### Agents

Purpose: select agent profiles and edit profile subviews.

Style:

- Left side uses profile cards/automation tiles.
- Right side has one Profile mode with labeled tabs: Overview, Instructions, Permissions, Used In.
- Tab panels use section blocks and badges.

Inconsistencies:

- Agents is currently the clearest labeled-tab example; Backlog also uses mode-owned tabs in some visual/capture modes. The style guide should define tab styling as a shared right-mode subview control, not an Agents-only pattern.
- Instructions and Permissions editing should align with Settings form density when they are true configuration forms.

### MCP Servers

Purpose: select MCP server tool config files and edit selected config.

Style:

- Left config files use bordered card tiles with selected state.
- Right editor uses `FormPanel` / `FormSectionCard`.
- YAML/source preview uses monospace form section.

Inconsistencies:

- Config-file cards should be a named variant shared by Settings Models, MCP Servers, and Tools.
- Source/YAML preview styling should be standardized across Settings, MCP Servers, Tools, and profile source views.

### Tools

Purpose: select local tool config files and edit local command definitions.

Style:

- Mirrors MCP Servers.
- Right editor uses settings form sections, local exec cards, tool rows, and YAML preview.

Inconsistencies:

- Tool command rows have a local settings style that should be part of the shared form/editor system.
- Empty states are sometimes inside form cards and sometimes standalone.

### Memory

Purpose: browse, review, map, capture, and inspect graph-backed memory.

Style:

- Left Search uses record cards with accent stripe, badges, and memory-specific filters.
- Review, Safety, Map use stacked sections and event cards.
- Capture uses form-like sections.
- Right modes use section blocks for Overview, Source, Relations, Corrections, Pages, and a denser plain editor style for Metadata.

Inconsistencies:

- Memory record cards overlap visually with Backlog, Files, and People cards but have their own local implementation.
- Memory filters are local controls, while Files/People use shell quick filters. This is acceptable when filters are multi-dimensional, but the visual treatment should still align.
- Metadata editing uses a different plain treatment than Settings forms; the style guide should define `dense editor` versus `form editor`.
- Memory Safety event cards should align with Operations History and People Activity event cards.
- Capture form controls should use shared command-panel form fields wherever possible.

### Files

Purpose: browse indexed file records and inspect selected file details/source/access.

Style:

- Left cards have strong selected state: accent stripe, icon box, metadata badges, card gradient.
- Shell quick filters are used well.
- Right modes use gradient inspector blocks and label/value rows.

Inconsistencies:

- Files and People are highly consistent with each other, but their card variant is not yet shared with Memory record cards or Backlog queue cards.
- Empty state includes action affordances, while most other empty states are passive blocks. This is useful but needs a named `actionable empty state` pattern.

### People

Purpose: browse contacts and inspect profile/context/activity/source/page details.

Style:

- Closely mirrors Files.
- Contact cards use accent stripe, icon box, badges, and selected border.
- Right modes use inspector blocks, context cards, activity rows, and compiled page preview.

Inconsistencies:

- Activity rows and context cards should align with Memory record/event card variants.
- Add-contact empty state matches Files in spirit but should use a shared actionable empty-state component.
- Profile detail styling and Files detail styling should share a common `entity inspector` pattern.

### Settings

Purpose: configure app, runtime profiles, model configs, and memory domains.

Style:

- Left areas use shell quick-access icons; area content uses settings section/config cards.
- Right content uses `FormPanel` and `FormSectionCard`.
- Forms use shared settings fields, autosave feedback, dropdowns, toggles, and source preview cards.
- CRUD placement is now shell-aligned.

Inconsistencies:

- Settings has the most coherent form style, but that form style is not consistently used by editable forms in Backlog Capture, Memory Capture, Workflow Steps, Task Overview, or Agent editing.
- Left App area renders a single selected tile, while Profiles/Models/Memory render collections. This is structurally okay, but the style guide should name it as a `single context tile`.
- The Settings form style is visually heavier than some dense editor panels; use it for configuration editing, not for every compact inspector field.

## Cross-Panel Style Inconsistencies

1. **Selectable cards have too many dialects.** Backlog queue cards, Memory record cards, Files cards, People cards, automation tiles, config-file tiles, and chat-session tiles all solve the same “select an object” problem with related but separate styles.

2. **Accent stripes are not governed by a shared rule.** Files, People, Backlog Queue, Memory Search, and Today Attention use stripes or accent bars, but the meaning of the stripe varies: selected state, object type, urgency, source, or category.

3. **Empty states vary in weight.** `PanelEmptyState` is plain centered text, `PanelEmptyBlock` is a bordered block, form editors sometimes put empty states inside `FormSectionCard`, and Files/People have actionable empty states.

4. **Editable forms split into Settings forms and local forms.** Settings uses shared field primitives and autosave feedback. Backlog, Memory Capture, Workflow Steps, Task Overview, and some Agent panels still feel more custom.

5. **Section block choices are ambiguous.** `PanelSectionBlock`, `PanelSectionBlock.gradient`, `PanelSectionBlock.plain`, and `FormSectionCard` are all used, but there is no documented rule for when each is correct.

6. **Badges and chips are visually fragmented.** `PanelBadge` is common, but Today chips, Memory filter chips, Backlog action chips, and graph labels use local variants.

7. **Canvas controls are local.** Stream, Constellation, DAG Builder, and Workflow Map each have graph/canvas affordances that should share a toolbar/control visual language.

8. **Typography is mostly consistent but not codified.** Pane labels are uppercase/letter-spaced, card titles are bold, secondary text is muted 12-14px, and dashboard numbers are larger. These are stable patterns but need names and limits.

9. **Padding uses several close-but-different values.** Command body lists commonly use 18/16/24px variants. Settings forms use 24px body padding and 18px section padding. Today dashboard uses larger route padding. These differences are defensible but should be tokenized.

10. **Search and filters have inconsistent visual hierarchy.** Shell search is consistent. Domain filters vary: Backlog Queue filters, Memory filters, Today Attention chips, and Files/People quick filters differ in look and placement.

11. **Primary content actions are mixed between icon and text styles.** Header CRUD is now icon-only. Content-level workflow actions, review decisions, capture commits, and explanatory links still use varied text/button treatments.

12. **Entity inspectors are not yet a named pattern.** Files Details, People Profile, Backlog Inspector, Memory Overview, and Settings App all show selected-object details, but they use different card composition and label/value row styles.

## Adopted Common Style Direction

The first implementation pass adopts these defaults for command-panel UI:

- Prefer flat bordered surfaces over gradient surfaces for repeated cards, sections, and controls.
- Use gradients for top-level shell chrome, route-level backgrounds, or brand moments, not routine panel content.
- Use selected border/fill as the primary selected state; avoid using bright accent text for every selected or metadata item.
- Treat badges as quiet metadata: muted text, compact radius, low-emphasis border, no category-colored fill by default.
- Keep accent stripes thin and reserve them for object category, urgency, or risk. Do not let stripes compete with title/content hierarchy.
- Use 16px/800-ish card titles for dense command lists; reserve heavier/larger titles for route dashboards and first-level summaries.
- Use shared panel radius and control-size tokens instead of one-off local values.

## Style Guide Decisions To Make

1. **Panel archetypes**

   Define which archetype a panel is using before designing content:

   - `collection`: selectable object list.
   - `inspector`: selected object summary/detail.
   - `form editor`: configuration or object editing with shared fields.
   - `dense editor`: compact editing inside a larger workflow.
   - `canvas`: graph/map/timeline/visual workspace.
   - `dashboard`: route-level summary, outside command-panel chrome.
   - `activity/event feed`: chronological or risk/history list.

2. **Selectable card variants**

   Create one shared card taxonomy:

   - `object card`: general selectable object.
   - `entity card`: Files/People-style card with icon box, accent stripe, and metadata badges.
   - `config card`: config/source file selector.
   - `graph node card`: canvas node, with fixed dimensions and compact ports/actions.
   - `chat/session card`: conversation selector.

3. **Accent semantics**

   Decide what accent color/stripe means:

   - Selection should primarily use border and selected gradient.
   - Object type/category can use icon color or small badge.
   - Urgency/risk can use a status badge or left stripe.
   - Do not reuse the same accent treatment for multiple meanings in the same panel.

4. **Empty-state scale**

   Use:

   - `PanelEmptyState` for filtered search misses.
   - `PanelEmptyBlock` for neutral no-data states inside panels.
   - `ActionableEmptyState` for no-data states where the next action is obvious, such as add file/contact/config.
   - Inline empty rows only inside dense editors.

5. **Form/editor rules**

   Use shared form fields for all command-panel forms.

   - `FormPanel` / `FormSectionCard` for configuration and settings.
   - `DenseEditorSection` for compact task/workflow/node editing.
   - Autosave fields for editing existing objects/config.
   - Explicit submit buttons only for creation, destructive operations, approvals, credential submission, or irreversible side effects.

6. **Content section rules**

   - Use `PanelSectionBlock.gradient` for normal inspector sections.
   - Use `PanelSectionBlock.plain` for dense editor subsections where nested gradients become heavy.
   - Use `FormSectionCard` only inside form editors.
   - Avoid nesting bordered cards inside bordered cards unless the nested item is a repeated selectable row.

7. **Badge/chip rules**

   - `PanelBadge` for metadata, status, type, sensitivity, and counts.
   - Shell quick filters for mutually exclusive or low-dimensional list filters.
   - Domain filter chips only for multi-dimensional filters or visualization controls.
   - Action chips should use a separate `PanelActionChip` style.

8. **Canvas controls**

   Create a shared canvas-control kit:

   - zoom segmented control.
   - recenter/fit icon button.
   - mini toolbar for selected node/card actions.
   - overlay placement rules.
   - fixed-size graph node cards.

9. **Inspector layout**

   Define one `entity inspector` pattern:

   - top summary block with title, subtitle, icon, and primary status badges.
   - secondary sections for metadata, source/access, relationships, and activity.
   - label/value rows with consistent label width, muted labels, and selectable values when technical.

10. **Density and spacing tokens**

   Codify:

   - shell header padding: 18 horizontal, 14 top, 12 bottom.
   - command list body padding: 18 horizontal, 16 top, 24 bottom.
   - compact card padding: 12.
   - standard section padding: 14-18.
   - form body padding: 24.
   - dashboard route padding: 28 horizontal.

11. **Typography roles**

   Define:

   - pane label: uppercase, letter-spaced, muted, bold.
   - section title: uppercase or title case, bold, compact.
   - card title: 14-16px, bold.
   - secondary metadata: 12-13px muted.
   - body copy: 14-15px.
   - dashboard metric: 18-22px.

12. **Search/filter placement**

   - Shell search belongs in shell headers.
   - Right detail search appears only when the right pane has multiple searchable blocks or item content.
   - Content-level filters belong immediately above the content they affect.
   - Visualization controls belong inside the canvas surface, not in shell chrome.

## Highest-Priority Cleanup Targets

1. Build shared selectable card components for object/entity/config/chat-session cards.

2. Build `ActionableEmptyState` and replace Files/People/custom actionable no-data states first.

3. Extend shared form/dense-editor primitives to Backlog Capture, Memory Capture, Workflow Steps, Task Overview, and Agent edit panels.

4. Create shared event/activity card styling for Operations History, Memory Safety, and People Activity.

5. Create shared canvas toolbar/node-card primitives for Backlog Stream, Backlog Constellation, Task Builder, and Workflow Map.

6. Turn the style decisions above into an authoritative `AGENTS.md` UI Style Guide section after we agree on names and component boundaries.
