# ADR 0001: Keep mobile additions additive in the Compatibility fork

`Ccat-Q/ChatAPI-iOS-Client-Compatibility` is the deployable ChatAPI fork for mobile-only additions. It exposes `/api/mobile/v1` for Bark, device-facing capabilities, and private media assets while preserving upstream protocol and Web-console routes.

The iOS repository contains no server secrets, Bark keys, R2 credentials, or server implementation.
