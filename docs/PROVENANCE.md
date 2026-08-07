# Provenance and release boundary

All application source, copy, fixtures, tests, interface artwork, icon artwork, and documentation in this repository were created for Agent Fanny Pack. Demo identities use the reserved `sample.test` domain, values are synthetic, and demo configuration homes live under `/tmp`.

The app icon is rendered entirely from original vector drawing code in `tools/IconMaker.swift`. Interface glyphs use Apple SF Symbols through system frameworks. No external visual asset is bundled.

The shipped application has no third-party runtime dependencies. It links only Apple platform frameworks and the Swift runtime supplied by the toolchain. The repository is licensed under MIT.

Public releases are deterministic tagged source archives produced by `scripts/package_source.sh` and accompanied by a SHA-256 file. The supported Homebrew formula compiles that exact source inside Homebrew's build sandbox, generates the original icon, applies a local ad-hoc bundle signature, and installs no downloaded executable app.

`scripts/package_app.sh` also cross-builds arm64 and x86_64 binaries, combines them into a universal executable, normalizes archive timestamps, and writes a checksum for CI and maintainer verification. That ad-hoc-signed app archive is not distributed to users. The prebuilt Homebrew cask is disabled until Developer ID signing and Apple notarization are available; the project does not instruct users to remove quarantine metadata or override Gatekeeper.
