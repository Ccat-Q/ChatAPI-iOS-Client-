# ChatAPI iOS Client

Native iOS 26+ operator workspace and administration client for self-hosted ChatAPI instances.

ChatAPI exposes a human operator through OpenAI Responses, Chat Completions, and Anthropic Messages compatible APIs. AI clients create conversations; an operator uses this app to inspect the conversation, provide the assistant response, and complete it. The app also provides request inspection, user administration, and server settings for administrators.

## Build

All compilation runs in GitHub Actions on pull requests, pushes to `main`, or manual dispatch. Protocol, session, and WebSocket regressions run before the unsigned iOS archive and IPA/dSYM packaging. Sign the IPA with your existing signing tool before installing it on a device.

## Server compatibility

This repository contains only the iOS client. Server-side mobile authentication, capability negotiation, and Bark notification support live in `Ccat-Q/ChatAPI-iOS-Client-Compatibility`.

## Documentation

See the [documentation index](docs/README.md) for architecture, supported features and protocol contracts, development and validation, troubleshooting, and the [project audit](docs/reviews/2026-10-22-project-audit.md).
