# TODO

## Priority 1

- Prove multi-user, multi-memory model. 

## Priority 2

### Chat Panel - Runtime

- Move Profile to top
- Make chat model second
- Move memory to end, allow multiple memory entries. 
- 'Memory memory' is not an informative name for the memory server. 
- 'Today loaded' is not a clear message. 
- Profiles should provide a default model, but chats should be able to switch models mid chat, as other providers allow. UX for this doesn't exist.  

### Backlog - Backlog

- The same inspector panel is used for each backlog view (Queue, Stream, etc)
- Remove the double card from the inspector panel
- An 'Active' task is not intuitive. 
- The buttons (ex: Clarify) are not clear. What's the algorithm to place them on a card?
- We can dismiss a card, but where does it go? Is there a way to recover it? Do we need a Trash (right) panel?


- Remove the refresh button from memory.
- Remove the person icon from the new person button.

- Audit the screens and panels.
- Run cleanup passes to eliminate excess logic and duplicate implementations.


## Priority 3

- Add button to include new files in chat. 

- Integrate/sync with Apple calendars through external plugin architecture.

- Integrate Codex, Claude Code, Gemini, and Copilot CLIs as tools. Cloud login and credential management may require server deployments.

- Add basic/advanced UI views. Users should be able to create additional, local or cloud memory stores with just a few mouse clicks. 

## Priority 4

- Add a batch job to organize memory and ask follow-up questions when an item needs more detail.