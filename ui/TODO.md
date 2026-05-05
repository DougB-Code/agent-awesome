# TODO

Add API key verification to model providers. 
Add pill to show if it's saved in web credential of as env var

Add a tabbed interface to the panels. Use case: we have especially dense configuration. 

Update top bar. Remove the two buttons and replace them with a drop down for 'Views' (ie: only view items related to a project, work, life).

Update the panel switcher title to work more like a bread crumb. It can show 'Models / OpenAI' or 'Models / xAI', etc. 

Remove Model Id from the new model form. The ID can be composed from the provider id and model name, and kept constant once set. 

I can no longer edit the provider YAML. I should be able to edit the YAML, and it should be verified according to a YAML schema and errors should be shown in place. 


I need a mechanism where I can just chat to the top bar and it figures out if I'm giving a command to for the current screen, or if I need to enter a new chat window. Bonus points if it can figure out if I want to continue an existing chat as well. 

> The repo’s dart shim tried to touch a read-only Flutter stamp, so I’m switching to the SDK Dart binary directly. Same formatter, less drama from the Flutter cache.

Make the text input for secret storage a reusable component (ie has hide, show, etc, reads from keyring or env var, etc). Change 'keyring' prefix with '[Windows|Linux|Mac] Password Vault'. It's not 100% correct terminology, but intuitive for users. 

Add a form note (make it reusable) that using env vars are less secure when the OS keyring is available. Perhaps make it a popup. 

Remove duplicate path from the agent settings.

Support for multiple provider endpoints needs to be added. xAI has different endpoitns for chat and images, as an example.

When I click on 'model provider name' the placeholder text doesn't disappear. 


The reason to use MCP servers for tasks and memory is to allow multiple agents to work together while referencing a common knowledge base. We shouldn't have to restart the MCP servers when there is new data.

Add ability to save task filters. 

Codex reports "The normal Flutter wrapper is trying to touch the SDK cache, which is read-only in this sandbox. I’m switching to the cached Dart binary directly for formatting/analyze, then I’ll run Flutter tests if the wrapper can execute without needing to update the cache." How can I fix this?
