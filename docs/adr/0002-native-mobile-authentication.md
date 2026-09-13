# ADR 0002: Reuse upstream Cookie sessions for mobile

The iOS client authenticates with ChatAPI's existing local or OIDC login flow and uses the resulting HTTPS Cookie session for REST and `/api/ws`. The app validates every restored session through `/api/auth/session` and stores only a Keychain session marker; it does not claim a device token or PKCE flow that the server has not implemented.

This preserves direct compatibility with deployed ChatAPI instances. A future device-token flow may be added only as a versioned Mobile Extension without replacing upstream sessions.
