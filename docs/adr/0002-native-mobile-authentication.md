# ADR 0002: Use native PKCE and device sessions

The browser-oriented OIDC cookie flow is not reused by the native client. The compatibility server issues a one-time authorization code after OIDC and exchanges it with PKCE for a revocable device session.
