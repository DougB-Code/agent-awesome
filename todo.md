# TODO

## Priority 1

### Panels - General

- Remove the border card from all right side sections. See backlog, queue, memory.

### Chat Panel - Runtime

- Move Profile to top
- Make chat model second
- Move memory to end, allow multiple memory entries. 
- 'Memory memory' is not an informative name for the memory server. 
- 'Today loaded' is not a clear message. 
- Profiles should provide a default model, but chats should be able to switch models mid chat, as other providers allow. UX for this doesn't exist.  

### Panels - Backlog

- Why does the queue have a topics and the stream has a different kind of filter? Should both filters be on each panel?
- The right side needs to change for each left side content type. That means the inspector needs to work with each panel type. It just shows the same task for each view. 

### Panels - Backlog - Queue

- An 'Active' task is not intuitive. 
- We can dismiss a card, but where does it go? Is there a way to recover it? Do we need a Trash (right) panel?
- The 'queue score' is not clear. What does this number actually represent?
- The Clarify pill is not clear. What's the algorithm to place them on a card?
- Change 'Missing Person' to 'No Person'.
- Remove the 'Open' text. Redundant with Open pill.
- The 'Schedule' button is really an 'Auto Schedule' button. Everything should always be automatically scheduled by the system.

### Panels - Backlog - Queue - Memory

- There's a chat message. What is 'No Linked Memory'?

### Panels - Backlog - Stream

- Remove the preset buttons (Custom, Effort, etc). 

### Panels - Backlog - Terrain

- Why does the pill have a number in it? What's it represent?

### Panels - Backlog - Inspector

- Open and normal dropdown styling should match other form controls. 
- The same inspector panel is used for each backlog view (Queue, Stream, etc)

### Panels - Memory - Search

- Remove the refresh button.
- The use of the drop down vs buttons is not clear. 
- Clicking on a memory entry can cause glitching. 
- Memory cards are showing internal identifiers.
- The overview card is not showing anything which can't be shown on the card itself. 

### Panels - Memory - Browse, Review

- Remove these


### Panels - Memory - Safety

- What are these? How are they flagged?

### Panels - Files & People

- Remove the cards or buttons. Only one is needed. 
- Remove the person icon from the new person button.

### Shell

- The spacing between the top right buttons is not consistent. 


## Priority 2

- Prove multi-user, multi-memory model. 
- Run cleanup passes to eliminate excess logic and duplicate implementations.


## Priority 3

- Add button to include new files in chat. 

- Integrate/sync with Apple calendars through external plugin architecture.

- Integrate Codex, Claude Code, Gemini, and Copilot CLIs as tools. Cloud login and credential management may require server deployments.

- Add basic/advanced UI views. Users should be able to create additional, local or cloud memory stores with just a few mouse clicks. 

## Priority 4

- Add a batch job to organize memory and ask follow-up questions when an item needs more detail.