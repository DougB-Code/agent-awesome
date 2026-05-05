# AGENTS.md

## Architecture

### Code Documentation

ALWAYS add concise code documentation for each file and function.
OPTIONALLY add concise code comments for nuanced statements that should be highlighted.

### Folder Structure

Root-adjacent packages wire systems together. Deeper packages contain narrower, more reusable logic and should not import their parent package.

Consolidate logically related code together. Use subfolders to adhere to the single responsibility principle.

```
security/
  auth/
    oauth/
    mtls/
```

### File Structure

ALWAYS maintain strict adherence to the single responsibility principle. Each function or data model MUST have a single responsibility, even if that responsibility is aggregation.

ALWAYS keep data models as dumb data stores, akin to Java POJOs.

NEVER mix UI logic with business logic. They are separate concerns that need to live in separate files.

NEVER create competing or duplicate implementations. Prioritize spending more time and tokens on understanding the codebase so you can better adhere to SOLID principles.

### Coding Practices

ALWAYS follow SOLID principles. Place particular emphasis on the Single Responsibility Principle.

NEVER add backwards compatibility or legacy support unless explicitly asked.

ALWAYS write production-grade code. DO NOT write shims, stubs, or non-test mocks unless explicitly asked.

ALWAYS give security and bug fixes priority over other coding concerns. Your implementation is only complete once it is secure and bug free.

ALWAYS add concise documentation to each package. ALWAYS state the package's intended use cases and high-level examples to help users know when they are misusing the package if required.

NEVER use fake fallbacks, fake seed data, fake stubs, or the like, unless explicitly asked.

## Build and Test

Codegen files needed for the project are allowed to be generated in the project source tree. All other files related to binary builds, inspection, verification, etc. must be located in the project's `build` folder.

Work summaries can be provided in the chat window, or in `build/ai`.

## Collaboration

ALWAYS scope changes to one task, such as adding a new LLM provider, fixing a bug, or changing the persistence layer. Remind the user to restructure their requests when they ask for broad, sweeping changes.
