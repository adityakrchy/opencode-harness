# Security Policy

## Reporting a vulnerability

**Please do not report security vulnerabilities through public GitHub issues.**

Instead, report them privately by email to **conductor@example.com**.
Include as much of the following as you can:

- Type of issue (e.g. command injection, credential leak, privilege escalation)
- Step-by-step reproduction or a proof of concept
- Affected component (`Core/APIClient.swift`, `Core/OpenCodeServer.swift`, `Core/EventStream.swift`, …)
- macOS and OpenCode CLI versions
- Suspicious logs — the app keeps a diagnostic log (see Diagnostics pane in Settings)

You will receive an acknowledgement within **72 hours**, and we aim to ship a fix
or mitigation within **30 days** for confirmed issues. We will credit reporters
by default; tell us if you prefer to stay anonymous. Coordinated disclosure is
appreciated — please give us a reasonable window before publishing details.

## Threat model: what is and isn't a vulnerability

OpenCode Harness is a local desktop client that **introspects and drives the
OpenCode agent runtime**. Several behaviors are *by design* and are **not**
security vulnerabilities, though reports about how to make them safer are still
welcome:

- **Not sandboxed, deliberately.** The app launches/discoverers the OpenCode CLI
  and reads your project folders. This is documented in the README.
- **The agent runs arbitrary commands.** Tool execution and the shell runner
  execute what you (or the model you chose) ask, guarded by OpenCode's own
  permission system. The app renders permission prompts but is not itself a
  sandbox administrator.
- **Credentials live locally.** API keys/OAuth tokens belong to OpenCode's own
  storage; the app only stores the *server password* in the Keychain.

Genuine issues worth reporting include, but are not limited to:

- The app leaking the server password or tokens into logs, exports, crash files,
  or process arguments
- MitM/bypass possibilities when connecting to a **remote** OpenCode server
  (`Basic` auth over plain `http://`, no cert pinning)
- Export/import session flows including provider credentials (the local export
  uses `sanitize=false` — see below) or executing arbitrary code from a crafted
  session JSON
- The SSE event stream accepting forged events, or permission prompts being
  auto-answerable by untrusted content

## Known limitations (documented, not bugs)

- Connections to remote servers use HTTP Basic auth; use HTTPS or an SSH tunnel.
- The app is **ad-hoc signed** for local builds. Gatekeeper verification of the
  binary only applies to releases distributed by the maintainers.
- Session export intentionally allows unsanitized data (`sanitize=false`) so
  exports round-trip fully — treat exported session JSON as sensitive.

## Supported versions

| Version | Supported |
| --- | --- |
| latest `main` | ✅ |
| older releases | best effort — rebase and test against `main` |
