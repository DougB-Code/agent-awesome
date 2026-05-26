# TODO

## Current

- Add tool versioning to the tool config. Configs should pull in config/verifications from previous versions as-is, and only have to provide their deltas.  
- Approved tool usage in the conversational agent needs to create/update tool configs if they don't already exist.
- Add CLI verifications and node envelope verifications. May need a top/right content toggle. 
- Add an 'Installed Tools'(current Files panel) and an 'Available Tools' panel, which will pull in all indees and show the tools, with advanced filtering. 


## Priority 1

- Run Codex CLI remotely on remote VM. 
- Open PR and publish to protected GitHub repo. 
- Enable remove coding via Slack.
- Enable overnight coding via CRON job.

## Priority 2

- Migrate dedicated daemons/clis to reusable packages and integrate them into harness/workflow to elminiate all/most inter-process code and security concerns. 

## Priority 3

- Integrate/sync with Apple calendars through external plugin architecture.
- Setup credential pattern to allow agents to login to website to take autonomous actions (D2l downloads).

## Tooling

- Add a `go get` style feature so AA can download tools from SCM platforms. Does Go have a dedicated support for GitHub, GitLab, Go.dev, etc? Is everything routed through Go.dev?

- @PRIORITY Add a schema importer (OpenAPI, etc) which automatically creates a REST API as a CLI tool.

## Priority 5

- Run cleanup passes to eliminate excess logic and duplicate implementations.



## Roadmap

- Add UI plugins backed by Starlark script processing to allow for user plugins and custom UIs. 

- Add button to include new files in chat. 

- Add basic/advanced UI views. Users should be able to create additional, local or cloud memory stores with just a few mouse clicks. 

- Add a batch job to organize memory and ask follow-up questions when an item needs more detail.

- Can the workflow engine itself be used to provide training to employees on how to do processes? For example, can it be used to show people how to use AI to perform a role? 

- Add a help icon in a fixed location which loads help documentation according to which screens are loaded. 

