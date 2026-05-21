# Agent Awesome

## Commands

```sh
go run ./cmd/agent-awesome run -- console
```

```sh
go run ./cmd/agent-awesome run --provider google --model-id gemini-flash-lite -- console -streaming_mode sse
```

```sh
go run ./cmd/agent-awesome run -- web --port 8080
```

```sh
go run ./cmd/agent-awesome run --model model.yaml --agent agent.yaml --tool tool.yaml -- console
```

```sh
go run ./cmd/agent-awesome run --provider cloudflare --model-id gemma-4 -- console
```

```sh
go run ./cmd/agent-awesome credentials set OPENAI_API_KEY
```

```sh
go run ./cmd/agent-awesome credentials set OPENAI_API_KEY --value "$OPENAI_API_KEY"
```

```sh
go run ./cmd/agent-awesome credentials remove OPENAI_API_KEY
```

```sh
go run ./cmd/agent-awesome --help
```

```sh
go run ./cmd/agent-awesome run --help
```

```sh
go run ./cmd/agent-awesome credentials --help
```

```sh
go test ./...
```

```sh
go mod tidy
```

## MCP tools

MCP servers are configured in the active tool package or installed beside it as
`mcp/<package>/mcp.yaml`. The harness validates the YAML, creates the MCP
transport, and passes MCP toolsets into the agent runtime; the runtime owns MCP
sessions, discovery, invocation, result conversion, and confirmation.

```yaml
mcp:
  enabled: true
  servers:
    - name: filesystem
      transport: stdio
      command: npx
      args:
        - -y
        - "@modelcontextprotocol/server-filesystem"
        - /absolute/path/to/workspace
      require-confirmation: true
      tools:
        allow:
          - read_file
          - list_directory

    - name: remote
      transport: streamable-http
      endpoint: https://example.test/mcp
      require-confirmation-tools:
        - delete_item
```
