---
name: coding-implementation
description: Implement complete features, create files, refactor code, and make coherent multi-file changes in an existing repository. Use for coding requests that require working implementation rather than explanation.
---
# Coding implementation

- Inspect the existing project tree, relevant source files, configuration, and conventions before changing code.
- Implement the requested behavior, not just a plan. Create missing files and update every necessary integration point.
- Keep changes minimal but complete. Reuse existing dependencies and architecture; do not introduce a new dependency without a clear need.
- Return complete final contents for every proposed file. Avoid placeholders, TODO-only code, omitted sections, or pseudocode.
- Handle loading, empty, success, failure, and boundary states where relevant.
- Keep public APIs and existing features compatible unless the request explicitly calls for a breaking change.
- Do not claim builds, tests, or runtime behavior were verified unless they were actually run.
- The user must review proposed file changes before they are applied.
