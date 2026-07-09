---
name: implementing
description: After plan approval ('go ahead', 'sounds good', 'make it so') or on direct build/fix/implement requests. Load whenever conversation transitions from planning to implementation. Documents plans as PRDs in spec/, implements code, and tracks issue resolutions.
---

## End Criteria
If the user has not specified explicit end criteria, solicit them before proceeding. Do not start implementation until end criteria are clear.

## Workflow

### 1. Generate PRD
Summarize the accepted plan as a Product Requirements Document including:
- **Context**: What prompted this work
- **Alternatives considered**: Other approaches that were discussed and why they were rejected
- **Rationale**: Why the chosen path was selected
- **Requirements**: What will be built
- **Technical approach**: How it will be implemented
- **Files affected**: Known files that will be created or modified

Write the PRD to `spec/` with filename format:
```
spec/YYYY-MM-DD-XX-<short_description_all_lowercase_with_underscores>.md
```
Where `XX` is a zero-padded sequence number (01, 02, etc.) and `<short_description>` is a slug of the feature name.

### 2. Implement
Execute the plan according to the PRD. Follow existing code conventions in the project.

### 3. Track Issues
When encountering issues, blockers, or deviations from the plan:
- Resolve the issue
- Append an **Issues & Resolutions** section to the PRD document documenting what happened and how it was resolved
- Do not delete or alter the original plan — append only

### 4. Completion
Do NOT stop execution until all end criteria from step 1 are satisfied. If stuck on a blocker, inform the user and ask for guidance rather than stopping.
