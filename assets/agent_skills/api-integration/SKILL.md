---
name: api-integration
description: Integrate REST APIs, OAuth, JSON responses, network clients, backend routes, retries, error handling, and external service contracts.
---
# API integration

- Inspect existing client wrappers, route definitions, schemas, configuration, and authentication patterns before coding.
- Keep base URLs and credentials out of source when they vary by environment; never put secrets in the client bundle.
- Validate response status, shape, pagination, timeouts, and error payloads; handle malformed responses safely.
- Preserve cancellation and loading/error states in the UI, and avoid duplicate or stale requests.
- Use typed models or small parsing helpers where helpful. Match the actual documented API instead of inventing endpoints or fields.
- For OAuth, validate state and redirect URI and use PKCE where appropriate. Store and refresh tokens securely.
- Add focused tests around success, authentication failure, malformed data, timeout, and rate-limit responses.
