# ChatAPI iOS Client

Native iOS 26+ administrator console for self-hosted ChatAPI instances.

## Build

GitHub Actions produces an unsigned IPA and dSYM from the `main` branch. Sign the IPA with your existing signing tool before installing it on a device.

## Server compatibility

This repository contains only the iOS client. Server-side mobile authentication, capability negotiation, and Bark notification support live in `Ccat-Q/ChatAPI-iOS-Client-Compatibility`.
