# Ubiquitous Language

## Operator

A human who responds as the Assistant when an external AI client opens a ChatAPI conversation.

## Caller

The external Agent or chat client that invokes ChatAPI through an OpenAI- or Anthropic-compatible API.

## Workspace

The real-time, owner-scoped view of an Operator's conversations, delivered by the upstream `/api/ws` protocol.

## Request

The protocol request that created a Conversation. It records the model, tool schemas, request format, status, and identifiers required to control output.

## Tool Call

A requested structured action in a Request. An Operator completes it with a tool name, call ID, validated input, and result.

## Mobile Extension

Additive, versioned functionality under `/api/mobile/v1` in the Compatibility fork. It never changes ChatAPI's `/v1/*`, `/messages`, or existing Web console APIs.

## Media Asset

A private object associated with one owner, conversation, and request. Assets are stored in Cloudflare R2 and read only through short-lived authorized URLs.

## Notification Target

An encrypted Bark Device Key and selected event categories for an Operator. It is configured through the Mobile Extension.
