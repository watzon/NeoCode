# Releasing NeoCode

This document describes the full local release flow for NeoCode: Sparkle signing, Developer ID export, notarization, appcast generation, and GitHub release publishing.

The goal is simple: when it is time to ship, the expected command is:

```bash
just release X.Y.Z
```

If the machine is already set up, that command should be all you need.

For beta distribution, use:

```bash
just release-beta X.Y.Z
```

## Release Model

NeoCode ships outside the Mac App Store and uses:

- Sparkle for in-app updates
- Developer ID signing for distribution
- Apple notarization for DMG delivery
- GitHub Releases for hosting both the DMG and `appcast.xml`

Beta releases use the same signed/notarized pipeline, but are published to GitHub as prereleases.

Important:

- keep `MARKETING_VERSION` numeric (for example `0.1.0`)
- do not use `1.0.0-beta.1` for the app bundle version; macOS bundle marketing versions are expected to remain numeric
- use the GitHub prerelease flag to communicate beta status instead

## Sparkle Keys

NeoCode uses Sparkle EdDSA signing for updates.

### Key Storage

- Public key: embedded into release builds as `SUPublicEDKey`
- Private key: stored in the macOS Keychain and managed by Sparkle's tooling
- Default NeoCode Sparkle Keychain account: `tech.watzon.NeoCode`

The private key is never committed to the repository.

### One-Time Sparkle Setup

Install the Sparkle CLI tools and generate the signing key:

```bash
just sparkle-keygen
```

Useful follow-up commands:

```bash
just sparkle-public-key
just sparkle-tools
```

Notes:

- `just sparkle-keygen` stores the private key in your login Keychain
- `just archive`, `just appcast`, and `just release` look up that key automatically
- you do not need to export `SPARKLE_PRIVATE_KEY` or `SPARKLE_PUBLIC_ED_KEY` for local releases

### CI / Non-Keychain Fallback

Local releases should use the Keychain.

If you ever need a non-Keychain path, `just appcast` still supports `SPARKLE_PRIVATE_KEY`, but that is intended as a fallback rather than the default flow.

## Notarization Credentials

NeoCode uses `notarytool` with a stored Keychain profile.

Create it once:

```bash
xcrun notarytool store-credentials "notarytool-password" \
  --apple-id "your@email.com" \
  --team-id "YOUR_TEAM_ID" \
  --password "app-specific-password"
```

Optional:

- set `NOTARYTOOL_PROFILE` if you want to use a profile name other than `notarytool-password`

## Prerequisites

Before cutting a release, make sure this machine has:

- Xcode installed and logged into the correct Apple Developer account
- automatic signing enabled for the `NeoCode` target
- Developer ID Application certificate available locally for the correct team
- `just`, `gh`, and `create-dmg` installed
- Sparkle key present in Keychain for `tech.watzon.NeoCode`
- `notarytool` credentials stored in Keychain
- GitHub CLI authenticated

Quick checks:

```bash
just check-tools
just sparkle-public-key
gh auth status -h github.com
security find-identity -v -p codesigning
xcrun notarytool history --keychain-profile "notarytool-password"
```

## One Command Release

The normal release command is:

```bash
just release X.Y.Z
```

Example:

```bash
just release 1.2.0
```

Beta example:

```bash
just release-beta 0.1.0
```

What it does:

1. Verifies Sparkle signing key access in Keychain
2. Verifies GitHub CLI authentication
3. Verifies the working tree is clean
4. Verifies release notes exist and contain no `TODO` markers
5. Bumps `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` if needed
6. Commits the version bump
7. Runs the test suite
8. Archives and exports a signed Developer ID build
9. Creates `dist/NeoCode.dmg`
10. Notarizes the DMG
11. Staples the notarization ticket
12. Generates `appcast.xml` from the final stapled DMG
13. Creates the git tag if it does not exist
14. Creates the GitHub release and uploads the DMG + appcast
15. Marks the GitHub release as a prerelease when you use `just release-beta`

## Release Notes

Release notes live in:

```text
release-notes/vX.Y.Z.md
```

Create a draft if needed:

```bash
just release-notes 1.2.0
```

The release command will stop if:

- the notes file does not exist
- the notes file still contains `TODO`

## Step-by-Step Manual Flow

If you do not want the all-in-one command, use this sequence:

```bash
just test
just dmg
just notarize dist/NeoCode.dmg
just staple dist/NeoCode.dmg
just appcast dist/NeoCode.dmg
gh release create vX.Y.Z dist/NeoCode.dmg appcast.xml \
  --repo watzon/NeoCode \
  --title "NeoCode vX.Y.Z" \
  --notes-file release-notes/vX.Y.Z.md
```

For a beta release, add `--prerelease` to the `gh release create` command.

## Appcast Hosting

NeoCode release builds point Sparkle at:

```text
https://github.com/watzon/NeoCode/releases/latest/download/appcast.xml
```

That means every published GitHub release must include:

- `dist/NeoCode.dmg`
- `appcast.xml`

## Important Release Assumptions

These are part of the expected release contract:

- release builds are produced through `just archive` / `just export-app` / `just release`
- Sparkle public key injection happens at archive time, not via a checked-in plain plist file
- the same Sparkle signing key must continue to be used unless there is an intentional key rotation
- notarization must happen before appcast generation so the signed bytes in the appcast match the stapled DMG users will download
- public releases must use Developer ID signing plus notarization; ad hoc or self-signed binaries are not valid release artifacts

## Key Rotation

Avoid rotating Sparkle keys unless absolutely necessary.

If you generate a new key:

- older versions signed with the previous public key may no longer trust new updates
- users may need to perform one manual download before Sparkle updates resume

If rotation is ever required, document it in the release notes and coordinate it as a deliberate breaking event.

## Troubleshooting

### Sparkle key missing

Symptoms:

- `just archive` or `just release` says the Sparkle key is missing

Fix:

```bash
just sparkle-keygen
```

### Notarization fails

Check the profile:

```bash
xcrun notarytool history --keychain-profile "notarytool-password"
```

### GitHub release creation fails

Check auth:

```bash
gh auth status -h github.com
```

### DMG creation fails

Check `create-dmg` and rebuild:

```bash
brew install create-dmg
just dmg
```

### Appcast signing problems

Check that the machine can still read the Sparkle key:

```bash
just sparkle-public-key
```

## Operator Checklist

Before saying a release is done, verify:

- tests passed
- DMG exists in `dist/NeoCode.dmg`
- DMG notarization succeeded
- DMG was stapled
- `appcast.xml` was generated from the stapled DMG
- GitHub release exists with both release assets attached
- release notes are final and user-facing

## Short Version

If the machine is already set up, the workflow is:

```bash
just release-notes X.Y.Z   # if notes do not already exist
# edit release-notes/vX.Y.Z.md
just release X.Y.Z
```

For a beta channel release, swap the last command for `just release-beta X.Y.Z`.
