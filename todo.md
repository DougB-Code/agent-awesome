# TODO

- Ensure `flutter run -d linux` issues Go build only for dev profiles. Optimally, that code shouldn't even make it into the final binary.

- The app background should not be black. It must be the same colour as the panel backgrounds. 

- Allow agents to use multiple memory servers at once.
- Add a batch job to organize memory. If batch sees a task such as 'buy a new computer', the agent can ask for details about the users needs and then research options.

- Integrate/sync with Apple/Gmail/Outlook calendars. Must be done externally to the agent to ensure plugin architecture. 

- Integrate Codex, Claude Code, Gemini, Copilot CLIs as tools. Cloud login and credential management may require server deployments.

- Integrate server provisioning and hardening as tools.