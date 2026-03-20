# Building NeoCode

This document covers the local build, signing, DMG, notarization, and release-related commands for NeoCode.

NeoCode now ships with a matching `neocoded` daemon release alongside the app. Debug and release workflows should treat the app and daemon as a single versioned unit.

At runtime, NeoCode prefers a managed daemon install in:

```text
~/Library/Application Support/tech.watzon.NeoCode/Daemon/bin/
```

If a matching managed daemon is not installed, NeoCode falls back to `PATH` only when the daemon version exactly matches the app version. Otherwise it downloads the matching daemon from the GitHub release for the app version.

For the full shipping checklist, see `RELEASING.md`.

## Core Commands

### Debug build

```bash
just build
```

### Release build

```bash
just build-release
```

For distributable builds, use the release flow in `RELEASING.md` rather than shipping a plain local build.

### Run tests

```bash
just test
```

This runs both the Swift app tests and the Go daemon tests.

### Build daemon artifacts for release

```bash
just daemon-artifacts X.Y.Z
```

Output:

```text
dist/daemon/neocoded-vX.Y.Z-darwin-arm64.tar.gz
dist/daemon/neocoded-vX.Y.Z-darwin-amd64.tar.gz
dist/daemon/neocoded-vX.Y.Z-checksums.txt
```

### Show current version/build

```bash
just version
```

## Sparkle Tooling

### Download Sparkle CLI tools locally

```bash
just sparkle-tools
```

This installs the Sparkle utilities into `bin/`:

- `generate_keys`
- `generate_appcast`
- `sign_update`

### Generate or install the local Sparkle signing key

```bash
just sparkle-keygen
```

### Print the current Sparkle public key

```bash
just sparkle-public-key
```

NeoCode uses the Keychain account:

```text
tech.watzon.NeoCode
```

## Code Signing

### Requirements

- signed-in Xcode account with the correct Apple Developer team
- automatic signing enabled for the `NeoCode` target
- Developer ID Application certificate available locally
- release artifacts must be Developer ID signed and notarized before distribution
- do not ship ad hoc, self-signed, or locally re-signed builds as releases

Check certificates:

```bash
security find-identity -v -p codesigning
```

### Archive a release build

```bash
just archive
```

This command:

- requires the Sparkle signing key to be available in Keychain
- verifies the Sparkle key is available locally and passes the active public key into the archive build

The daemon release artifacts are built separately with `just daemon-artifacts X.Y.Z` and published with the same release tag as the app.

Normal Xcode and `just build` / `just build-release` builds already embed NeoCode's checked-in `SUPublicEDKey`, so Sparkle stays available outside the release pipeline too.

### Export the signed app bundle

```bash
just export-app
```

This uses `scripts/ExportOptions.plist` with `method=developer-id`.
That is the only supported signing path for release artifacts.

### Manual fallback signing

```bash
just sign
```

This is only for manual bundle re-signing. The normal release path should use `just export-app`.
It does not replace the Developer ID archive/export flow or notarization, so it is not sufficient for a public release on its own.

### Verify signatures

```bash
just verify-signature
```

## DMG Packaging

### Build and package the signed DMG

```bash
just dmg
```

### Rebuild DMG without repeating archive/export

```bash
just dmg-quick
```

Output:

```text
dist/NeoCode.dmg
```

## Notarization

### Store notarization credentials once

```bash
xcrun notarytool store-credentials "notarytool-password" \
  --apple-id "your@email.com" \
  --team-id "YOUR_TEAM_ID" \
  --password "app-specific-password"
```

### Notarize the DMG

```bash
just notarize dist/NeoCode.dmg
```

NeoCode release binaries are expected to go through notarization before they are distributed.

### Staple the ticket

```bash
just staple dist/NeoCode.dmg
```

## Appcast Generation

Generate an appcast from the final stapled DMG:

```bash
just appcast dist/NeoCode.dmg
```

Behavior:

- uses the Sparkle key in Keychain by default
- falls back to `SPARKLE_PRIVATE_KEY` only if you explicitly supply it
- writes `appcast.xml` at the repo root

The generated download prefix targets GitHub Releases:

```text
https://github.com/watzon/NeoCode/releases/download/vX.Y.Z/
```

## Local Release Helper

If you want everything up to the publish step except GitHub release creation:

```bash
just release-local
```

That runs:

1. `clean`
2. `test`
3. `dmg`
4. `daemon-artifacts X.Y.Z`

Then you continue with notarization, stapling, and appcast manually.

### Beta release

```bash
just release-beta 0.1.0
```

This keeps the bundle version numeric for macOS while publishing the GitHub release as a beta prerelease.

## Full Release Command

```bash
just release X.Y.Z
```

For beta distribution with a numeric app version, use:

```bash
just release-beta X.Y.Z
```

See `RELEASING.md` for the complete operational flow and expectations.

## Troubleshooting

### Rebuild and relink the local daemon

```bash
just server-install
```

This builds `neocoded` with the current app marketing version and links it into `~/.local/bin` for local development.

### Missing Sparkle key

```bash
just sparkle-keygen
```

### Missing release tools

```bash
just check-tools
```

### Inspect build settings

```bash
just show-settings
```

### Start from clean state

```bash
just clean
```
