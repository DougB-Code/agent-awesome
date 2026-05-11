// This file defines the runtime-neutral ADK tool bundle.
package toolbundle

import "google.golang.org/adk/tool"

// Bundle contains runtime tools and toolsets to install on an agent.
type Bundle struct {
	Tools    []tool.Tool
	Toolsets []tool.Toolset
}
