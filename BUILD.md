# Building NeoCode

This document covers the local build, signing, DMG, notarization, and release-related commands for NeoCode.

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
- automatically reads the Sparkle public key and injects it into the archive build as `SUPublicEDKey`

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
