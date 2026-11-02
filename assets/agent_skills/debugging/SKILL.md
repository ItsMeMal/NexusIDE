---
name: debugging
description: Diagnose compiler errors, runtime failures, regressions, logs, stack traces, and broken behavior. Use when asked to fix a bug or explain an error.
---
# Debugging

1. Start from the exact error, stack trace, or failing behavior. Identify the relevant source location and inspect surrounding code and call paths.
2. Find the smallest root cause that explains the symptoms. Do not mask errors or rewrite unrelated modules.
3. Check nullability, asynchronous state, resource cleanup, lifecycle, type mismatches, platform differences, and edge cases as applicable.
4. Make a targeted fix and update affected tests or assertions when possible.
5. Inspect callers and similar code paths for the same defect.
6. Report the root cause and the exact verification performed. Never claim a test or build passed unless the command actually ran successfully.
