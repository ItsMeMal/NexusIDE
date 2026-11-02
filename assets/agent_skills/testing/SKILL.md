---
name: testing
description: Create or improve unit, widget, integration, regression, and manual verification tests; validate fixes and report evidence.
---
# Testing and verification

- Inspect the existing test setup and use the project's established testing framework.
- Add tests for expected behavior, important edge cases, errors, and regressions instead of testing implementation details only.
- For Flutter, use flutter_test for widget/unit tests where practical; for other stacks, follow existing test conventions.
- Keep tests deterministic. Avoid network access and real credentials in unit tests by using fakes or injected clients.
- Run the narrowest relevant test first, then broader checks if available.
- Separate checks that passed from checks that could not run. Never fabricate test output or imply a build succeeded without evidence.
