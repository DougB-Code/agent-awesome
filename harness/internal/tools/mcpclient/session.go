// This file opens MCP client sessions from harness tool configuration.
package mcpclient

import (
	"context"

	"agentawesome/internal/config/schema"
	"agentawesome/internal/tools/mcptransport"
	"github.com/modelcontextprotocol/go-sdk/mcp"
)

// ValidateServer checks whether a configured MCP server has a supported transport.
func ValidateServer(server schema.MCPServer) error {
	_, err := mcptransport.New(server)
	return err
}

// Connect opens an MCP client session for one configured server.
func Connect(ctx context.Context, server schema.MCPServer, name string, version string) (*mcp.ClientSession, error) {
	transport, err := mcptransport.New(server)
	if err != nil {
		return nil, err
	}
	client := mcp.NewClient(&mcp.Implementation{Name: name, Version: version}, nil)
	return client.Connect(ctx, transport, nil)
}
