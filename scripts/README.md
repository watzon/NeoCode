# NeoCode release scripts

This directory mirrors the local release flow used in `../pindrop`, adapted for NeoCode's Sparkle-based update pipeline.

Primary docs live at the repo root:

- `BUILD.md`
- `RELEASING.md`

Included pieces:

- `create-dmg.sh` builds a distributable DMG from the exported app bundle.
- `sign-app-bundle.sh` re-signs Sparkle's nested executables if you ever need a manual signing fallback.
- `ExportOptions.plist` configures `xcodebuild -exportArchive` for Developer ID distribution.

Release prerequisites:

- `create-dmg` installed via Homebrew.
- A working `notarytool` keychain profile, defaulting to `notarytool-password` unless `NOTARYTOOL_PROFILE` is set.
- A Sparkle EdDSA key stored in your macOS Keychain for account `tech.watzon.NeoCode`. Create it once with `just sparkle-keygen`.
- Optionally, `SPARKLE_PRIVATE_KEY` can still be supplied for CI-style appcast signing, but local releases default to Keychain-backed signing just like Pindrop.

Primary commands:

- `just sparkle-keygen`
- `just sparkle-public-key`
- `just test`
- `just dmg`
- `just notarize dist/NeoCode.dmg`
- `just staple dist/NeoCode.dmg`
- `just appcast dist/NeoCode.dmg`
- `just release 1.0.0`
- `just release-beta 0.1.0`

Shipping note:

- public NeoCode releases are expected to use the Developer ID archive/export flow plus notarization
- do not distribute self-signed or ad hoc builds as release artifacts
