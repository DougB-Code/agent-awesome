# TODO

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

## Priority 5

- Run cleanup passes to eliminate excess logic and duplicate implementations.



## Roadmap

- Add UI plugins backed by Starlark script processing to allow for user plugins and custom UIs. 


- Add button to include new files in chat. 


- Add basic/advanced UI views. Users should be able to create additional, local or cloud memory stores with just a few mouse clicks. 

## Priority 4

- Add a batch job to organize memory and ask follow-up questions when an item needs more detail.