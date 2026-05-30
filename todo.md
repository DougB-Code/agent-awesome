# TODO

## Current

- Build and run runbooks.
- Rename 'Workflows' to 'Runbooks' and 'Operations' to 'Launchpad'.
- Are any of the automations tied to the Flutter UI? Can they be run via Slack chat?


## Next

- Run agent and Codex CLI remotely on Cloud provider.
- Open PR and publish to protected GitHub repo. 
- Enable remote via Slack.
- Enable overnight coding via CRON job.
- Run cleanup passes to eliminate excess logic and duplicate implementations.
- I can run UI from my computer, and it does all work on remote server, like remote control over an SSH tunnel. Will help when working with a poor connection.



## Parking Lot


### Agents

- The settings show an Assigned button, but it doesn't tell me where it's assigned. This is useless info.


### Chat

- Add support for ingesting files.
- Add support for invoking new model modalities:
  - Image gen
  - Audio/music gen
  - Video gen


### Features

- Add a batch job to organize memory and ask follow-up questions when an item needs more detail.

- Add hooks into UI to enable plugin creation. Main app shell remains the same. Users can create custom panels when can be added as quick access icons to existsting app panels or new menu sections. 

- Integrate/sync wih Apple calendars through external plugin architecture.

- Setup credential pattern to allow agents to login to website to take autonomous actions (D2l downloads).

- Have two UI chat modes. Mode 1: The UI remains static, the user chats with the AI in whatever chat window they started with, and the AI configures the app in the background. Mode 2: The chat is moved to the side panel, and the UI shows the changes being made by the AI as they're made. This can help users learn the tool better. Add a quick toggle for when users want to or don't want to see the UI be edited. 



### Memory

- Users should be able to create additional, local or cloud memory stores with just a few mouse clicks. 

- The reason to use MCP servers for tasks and memory is to allow multiple agents to work together while referencing a common knowledge base. We shouldn't have to restart the MCP servers when there is new data.


### Models

- Remove Model Id from the new model form. The ID can be composed from the provider id and model name, and kept constant once set. 

- There's no reason to show the provider yaml at all. 

- Add API key verification to model providers. 

- Add pill to show if it's saved in web credential of as env var

- Add a form note (make it reusable) that using env vars are less secure when the OS keyring is available. Perhaps make it a popup. 

- When I click on 'provider model' the placeholder text doesn't disappear. 

- Support for multiple provider endpoints needs to be added. xAI has different endpoints for chat and images, as an example.


### Products

- Can the workflow engine itself be used to provide training to employees on how to do processes? For example, can it be used to show people how to use AI to perform a role? 

- See how we can clone Kanban Lite, possibly using a plugin architecture, not first class. 


### Tooling

- Add a `go get` style feature so AA can download tools from SCM platforms. Does Go have a dedicated support for GitHub, GitLab, Go.dev, etc? Is everything routed through Go.dev?

- @PRIORITY Add a schema importer (OpenAPI, etc) which automatically creates a REST API as a CLI tool.

- Add an 'Installed Tools'(current Files panel) and an 'Available Tools' panel, which will pull in all indees and show the tools, with advanced filtering. 

- Make tools to convert binary files to text representations (Excel, Word, PDF, etc).

- Add tool versioning to the tool config. Configs should pull in config/verifications from previous versions as-is, and only have to provide their deltas.  

- Approved tool usage in the conversational agent needs to create/update tool configs if they don't already exist.


### User Interface

- Add UI plugins backed by Starlark script processing to allow for user plugins and custom UIs. 

- Have the left column default to 30% when the menu column is open, and 25% when the menu column is collapsed. 

- Add basic/advanced UI views. 

- Add a help icon in a fixed location which loads help documentation according to which screens are loaded. 

- Make the text input for secret storage a reusable component (ie has hide, show, etc, reads from keyring or env var, etc). Change 'keyring' prefix with '[Windows|Linux|Mac] Password Vault'. It's not 100% correct terminology, but intuitive for users. 

- Update top bar. Remove the two buttons and replace them with a drop down for 'Views' (ie: only view items related to a project, work, life).

- Add ability to save task filters. 

- I need a mechanism where I can just chat to the top bar and it figures out if I'm giving a command to for the current screen, or if I need to enter a new chat window. Bonus points if it can figure out if I want to continue an existing chat as well. 

- Reduce width of side menu by 10%.

- Pressing the side chat button isn't adding a third column, it's replacing the second column.

### Workflows

- There's no need to show the left side 'Actions' button unless the Builder canvas is active. It should only be enabled for that screen.

- Default opening the workflow to the workflow picker. 

- Move the copy/delete buttons to the right on each right panel. 


## Misc

> The repo’s dart shim tried to touch a read-only Flutter stamp, so I’m switching to the SDK Dart binary directly. Same formatter, less drama from the Flutter cache.

Can I create multiple Codex config profiles so I can separate live pilot from code updates which  need flutter?



