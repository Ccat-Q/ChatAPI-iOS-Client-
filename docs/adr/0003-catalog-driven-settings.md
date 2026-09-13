# ADR 0003: Use server metadata for administrator settings

The mobile management UI reads the existing administrator settings catalog and document endpoints. It renders only declared editable fields and sends typed patches back to the server. High-risk changes require local biometric authentication and explicit confirmation.
