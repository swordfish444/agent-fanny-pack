# Provenance and release boundary

All application source, copy, fixtures, tests, interface artwork, icon artwork, and documentation in this repository were created for Agent Fanny Pack. Demo identities use the reserved `sample.test` domain, values are synthetic, and demo configuration homes live under `/tmp`.

The app icon is rendered entirely from original vector drawing code in `tools/IconMaker.swift`. Interface glyphs use Apple SF Symbols through system frameworks. No external visual asset is bundled.

The shipped application has no third-party runtime dependencies. It links only Apple platform frameworks and the Swift runtime supplied by the toolchain. The repository is licensed under MIT.

Release archives are produced by `scripts/package_app.sh`. The script cross-builds arm64 and x86_64 binaries, combines them into a universal executable, generates the original icon, applies an ad-hoc code signature, normalizes archive timestamps, strips extra ZIP metadata, and writes a SHA-256 file.

The ad-hoc signature provides bundle integrity but is not a Developer ID signature and is not notarization. Until a maintainer provides Apple-issued signing and notarization credentials outside the repository, Gatekeeper may block the first launch. The documented recovery is the narrow, user-visible **Open Anyway** flow in macOS System Settings. Neither the cask nor the app removes quarantine metadata.
