# Architecture

Agent Fanny Pack is one native Swift executable with two modes: a menu-bar UI and an explicit command-line helper. It uses SwiftUI for the popover, AppKit for the status item, Foundation for subprocesses and bounded JSON metadata, and no third-party runtime packages.

## Trust boundary

The app never reads transcripts, browser cookies, passwords, auth files, or local token counters. Provider credentials remain in provider-owned configuration homes, the macOS Keychain, or the provider's OAuth store. Stored metadata is limited to 32 account profiles, one active profile ID per tool surface, and at most eight quota snapshots per profile (128 total). Synthetic preview snapshots are never persisted.

## Provider adapters

- Codex CLI launches the documented local `codex app-server` process with an isolated `CODEX_HOME`, performs the JSONL initialization handshake, then calls `account/read` and `account/rateLimits/read`. It does not start a model turn.
- Claude Code runs `claude auth status` with an isolated `CLAUDE_CONFIG_DIR`. Authoritative quota arrives through Claude Code's documented status-line JSON. The bridge ignores context-window and token-estimate fields.
- The Codex macOS app is guided-only. The app's own sign-out/sign-in UI remains authoritative.
- Cursor is an explicit unsupported adapter until Cursor documents a safe personal quota and isolated-profile switching contract.

## Switching

The active account is scoped to one provider/tool surface. A switch changes only the profile selected by the `agent-fanny-pack run codex` or `agent-fanny-pack run claude` launcher. Running sessions keep their original environment and credentials. There is no global winner between Codex and Claude.

## Runtime behavior

There is no daemon, telemetry, analytics, update ping, transcript index, or LLM call. Refresh is manual and coalesced. Network activity can occur only inside the first-party provider command explicitly invoked for a refresh or login.
