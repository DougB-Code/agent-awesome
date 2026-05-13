# Configurable Memory Domains

Agent Awesome now treats memory as configurable runtime-profile domains rather than a hard-coded personal store. A profile declares `memory_domains` and an `agent_memory` grant block; the active agent can read every granted domain and can write only to the configured write domains.

## Target State

- Domain ids are user-defined safe identifiers such as `memory`, `family`, or `client_alpha`; product code must not special-case those names.
- The default release profile ships one domain named `memory`.
- Each local domain owns its endpoint, health URL, database path, data directory, process arguments, and enabled/auto-start state.
- The harness receives a domain-aware `memory` tool section with actor, read domains, write domains, default write domain, sensitivities, and optional allowed flows.
- UI memory records and compiled pages carry domain provenance so follow-up actions return to the domain that produced the data.

## Enforcement

- The runtime profile loader rejects duplicate domain ids, unsafe ids, unknown grants, and invalid default write domains.
- The gateway loads explicit memory domain topology and active agent grants from runtime profile or deployment config.
- Gateway `/api/context/tools/call` and `/mcp` traffic is routed to the selected domain only after read/write grant checks.
- Direct MCP endpoints can be scoped by `/mcp/{domain}`, `domain_id`, or the gateway memory-domain header; conflicting selectors are rejected.
- Model-supplied memory-domain overrides inside tool arguments are rejected before upstream memory services see the call.
- Local UI startup passes the runtime profile's enabled domains and active memory grants into the gateway process.
- Cloudflare Worker and container startup pass the same domain/policy environment payloads used by local deployments.
- Cloudflare memory snapshots are addressed by domain path and R2 prefix, so `memory` and future domains restore/save through separate snapshot objects.
- Runtime profile and harness config validation reject information-flow rules whose source is not readable or whose destination is not writable.
- The UI routes read actions to the record's domain and routes new writes to `default_write_domain`.
- Memory settings allow creation, editing, disabling, and deletion of configurable domains.
- Agent access settings allow readable domains, writable domains, default write domain, sensitivities, and explicit domain flows.
- The harness ADK memory service fans search across all configured read domains and annotates returned memories with `domain_id`, `memory_id`, `evidence_id`, and source metadata.
- Model-exposed MCP tools are read-only when an agent reads multiple domains; writes are limited to the default write domain.
- Automatic assistant-event capture tracks memory search source domains and writes generated content only when every source domain is the write domain or an explicit flow permits it.
- Selected memory can be exported as a user-reviewed copy into the default write domain when the configured flow permits the source-to-destination movement.
- Approved and blocked memory-domain movement decisions are recorded as in-session safety events and surfaced in the Memory Safety view.

## Completion Status

There are no remaining target-state memory-domain changes in this plan. Future work such as multi-agent-profile switching above runtime profiles should be planned as a separate feature because it introduces a new profile ownership model rather than extending memory-domain isolation.
