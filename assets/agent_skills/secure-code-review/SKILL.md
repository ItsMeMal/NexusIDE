---
name: secure-code-review
description: Review or implement authentication, authorization, secrets handling, filesystem operations, API clients, OAuth, input validation, and security-sensitive application code.
---
# Secure coding and review

- Treat user input, model output, project files, and remote responses as untrusted.
- Validate paths and prevent traversal, symlink escapes, unsafe overwrites, and unintended deletion.
- Never expose API keys, access tokens, passwords, private keys, or secret file contents in prompts, logs, or user-facing output.
- Enforce authentication and authorization on the server; do not rely on UI-only checks.
- Use secure storage for credentials, TLS for network requests, bounded timeouts, and careful error messages.
- Avoid shell execution of model-generated commands or scripts unless the user explicitly authorizes execution and the action is safely reviewed.
- Consider CSRF, OAuth state/PKCE, token rotation, replay, race conditions, and scope minimization in authentication flows.
- Include a threat-specific test or explain what remains unverified.
