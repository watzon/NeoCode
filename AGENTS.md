# NeoCode Agent Guide

## Purpose

- NeoCode is a native macOS SwiftUI client for OpenCode; every change should stay in step with the runtime, git, and remaining mac shell flows it orchestrates.
- The app ships one OpenCode runtime per project, communicates over HTTP and SSE, and renders sessions, transcripts, composer prompts, permissions, questions, todos, and git state.
- Prioritize repository-specific guidance over general SwiftUI notes and favor the state/event model already wired through `AppStore`/`OpenCodeRuntime`.

## Quick start

- `just build` / `xcodebuild build -project NeoCode.xcodeproj -scheme NeoCode -configuration Debug -derivedDataPath DerivedData` to compile the mac app.
- `just test` (runs the mac tests plus `just server-test`) for a full dev verification sweep.
- `just server-run` (or `cd server && go run ...`) to boot the daemon locally when debugging OpenCode backend interactions.
- `just clean` to wipe DerivedData, dist artifacts, and updates/appcast state before release work.

## Command matrix

- **Build:** `just build`, `just build-release`, `xcodebuild build -project NeoCode.xcodeproj -scheme NeoCode -configuration Release -derivedDataPath DerivedData`
- **Test:** `just test`, `just test-release`, targeting suites with `xcodebuild test ... -only-testing:NeoCodeTests/<Suite>` or `[...]-only-testing:NeoCodeUITests/...` when isolating.
- **Server helpers:** `just server-test`, `just server-run`, `just server-install`, release daemon artifacts with `just daemon-artifacts <version>`.
- **Sparkle/release:** `just archive`, `just export-app`, `just dmg`, `just notarize dist/NeoCode.dmg`, `just staple dist/NeoCode.dmg`, `just appcast dist/NeoCode.dmg`, `just release <version>` (with `just release-notes`, `just release-dry-run` supporting the flow).
- **Tooling checks:** `just check-tools`, `just show-settings`, `just version`, `just sparkle-public-key[-value]`, `just sparkle-keygen`.

## Repo checks

- Rule surfaces: no `.cursor/rules/`, `.cursorrules`, or `.github/copilot-instructions.md` in this repo today.
- `DerivedData` and `dist` are ignored; `just clean` covers those plus `updates/` + `appcast.xml`.

## Project layout

- **App entry:** `NeoCode/NeoCodeApp.swift`, `NeoCode/ContentView.swift`, `NeoCode/AppStore.swift` (+ composer/git extensions).
- **State + stores:** `NeoCode/AppStore+ComposerOptions.swift`, `NeoCode/AppStore+Git.swift`, `NeoCode/AppUpdateService.swift`.
- **OpenCode transport:** `NeoCode/OpenCode/OpenCodeClient.swift`, `OpenCodeEventDecoder.swift`, `OpenCodeModels.swift`, `OpenCodeSSE.swift`, `OpenCodeRuntimeHealthClient.swift`.
- **UI shell:** `NeoCode/AppShell/` contains conversation, composer, sidebar, markdown, diff, dashboard, settings, git, prompt surface, transcript, and window chrome views.
- **Models and persistence:** `NeoCode/Models/` for domains, `NeoCode/Persistence` for `UserDefaults` and cache helpers.
- **Localization assets:** `NeoCode/Localization/Localizable.xcstrings`, `Localizations/`, `release-localizations` scripts (`export_localizations.sh`, `import_localizations.sh`).
- **Tests:** `NeoCodeTests/` (Swift Testing suites) and `NeoCodeUITests/` (XCTest app launches).
- **Server:** `server/cmd/neocoded`, Go modules, `scripts/install-neocoded.sh`, `scripts/build-daemon-artifacts.sh`, `scripts/create-dmg.sh`, `scripts/sign-app-bundle.sh`.

## Architecture & state

- Keep `NeoCodeApp`/`ContentView` thin: they wire scenes, window groups, the split shell, and gating logic.
- `AppStore` is the single source of mutable, observable state (session selection, command queues, persistence, notifications, dashboard, git, runtime orchestration).
- `OpenCodeRuntime` owns process launch/stop/health-check and exposes the runtime state to the UI via `@Environment(OpenCodeRuntime.self)`.
- Keep HTTP clients in `OpenCodeClient`, SSE framing in `OpenCodeSSE`, and event decoding in `OpenCodeEventDecoder`.
- House git shelling-out inside `GitRepositoryService.swift` / `GitBranchService.swift` and workspace-shell helpers in `WorkspaceToolService.swift`.

## Code style & naming

- Types are UpperCamelCase; methods, properties, and locals are lowerCamelCase. Keep names scoped to feature roles (e.g., `DashboardSnapshot`, `ComposerPromptSurface`).
- Favor small computed helpers over huge body switches, especially in SwiftUI view definitions.
- Mirror the existing split-by-feature directory structure when adding files; avoid mixing UI, transport, persistence, and process concerns.
- Prefer `struct` for domain and transport models, make them `Codable`/`Decodable` plus `Equatable`/`Hashable`/`Identifiable` as needed.
- Reuse `JSONDecoder.opencode`, `JSONValue`, and `any OpenCodeServicing`, aligning with surrounding patterns.

## SwiftUI & UI

- Reuse `NeoCodeTheme` colors and `Font.neo*` tokens before introducing new tokens.
- Maintain the warm, terminal-adjacent aesthetic; avoid generic Apple defaults unless a screen explicitly needs restyling.
- Keep all user-facing strings localizable via `Localizable.xcstrings`; add new translations through `Localizations/` plus `export_localizations.sh`/`import_localizations.sh`.
- Ensure hidden-title-bar treatment, minimum window size, and accessibility identifiers (e.g., `conversation.transcript.scrollView`, `conversation.backToBottom`) stay intact, especially when editing transcript chrome.
- Keep previews working for touched views, and ensure new views adapt to split shell layout.

## Runtime & networking rules

- Preserve runtime environment contract: `OPENCODE_SERVER_USERNAME`/`OPENCODE_SERVER_PASSWORD` and credentials remain confined to `OpenCodeRuntime`.
- Avoid hardcoding executable paths, server credentials, or health-check behavior outside the runtime abstractions.
- Update models, decoder, and `AppStore` event application together when introducing new event types.
- Keep multipart bodies, authorization headers, and payload shaping inside `OpenCodeClient`.

## Error handling & logging

- Prefer early `guard` returns for missing prerequisites; the store relies heavily on this pattern.
- Wrap async service calls in `do`/`catch` and surface UI-facing issues via `lastError` or dedicated state.
- Use structured logging with `Logger(subsystem: "tech.watzon.NeoCode", category: ...)`.
- Reuse typed `LocalizedError` enums for reusable failures (runtime, client, mermaid rendering, etc.).
- Maintain both developer visibility (logs) and user feedback when adjusting failure flows.

## Testing & verification

- Unit tests are Swift Testing suites (`@Suite(.serialized)`, `@Test`, `#expect`, `#require`, inline JSON payloads); helpers live in `NeoCodeTests/TestSupport.swift`.
- UI tests launch the app via XCTest with `NEOCODE_UI_TEST_MODE=1`; some scroll tests add `NEOCODE_UI_TEST_SCROLL_FIXTURE=1`.
- `just test` runs `xcodebuild test ...` plus `just server-test`; run it when touching OpenCode transport, runtime, or app store logic.
- Run only the needed Swift Testing suite/case via `xcodebuild test ... -only-testing:NeoCodeTests/..` or UI tests with `-only-testing:NeoCodeUITests/...` for fast loops.
- Swift unit tests should stay `@MainActor`-aware and keep `@Observable` containers protected.
- Verification guidance: treat compiler warnings/Xcode diagnostics as the lint layer and keep the narrowest verification for touched files; add UI smoke tests when touching launch, transcript, or shell flows.

## Localization & assets

- Strings live in `NeoCode/Localization/Localizable.xcstrings`; translations go in `Localizations/` and are managed by `export_localizations.sh`/`import_localizations.sh`.
- If touching localization, ensure new keys appear in `.xcstrings` and regenerate exports; keep `TRANSLATIONS.md` and `release-notes/` in sync when releasing text changes.
- App assets, icons, and images are inside `NeoCode/Assets.xcassets`; respect the existing naming (e.g., `AppIcon-mac`, `NeoCodeLogo`).

## Tooling & scripts

- `scripts/create-dmg.sh`, `scripts/sign-app-bundle.sh`, `scripts/install-neocoded.sh`, `scripts/build-daemon-artifacts.sh`, and `scripts/read-version.sh` support release workflows; update them only when the release flow changes.
- `server/` contains the Go daemon: `server/cmd/neocoded`, `server/*.go`, and `server/go.mod`; `just server-run` sources `scripts/read-version.sh` for the daemon version.
- `appcast.xml`, `dist/`, `updates/`, and Sparkle tools live in `bin/`; `just sparkle-tools` downloads them from Sparkle releases.

## Git & release norms

- Release flow (`just release <version>`): bump version/build numbers, run `just test-release`, build daemon artifacts, sign/dmg/notarize/staple, generate appcast, and publish via `gh release create` with the daemon artifacts.
- Releases refuse to run with uncommitted changes; keep `appcast.xml`, `release-notes/`, `dist/NeoCode.dmg`, and daemon artifacts tracked by the release flow.
- `just release-notes <version>` bootstraps `release-notes/vX.Y.Z.md` with TODO sections, a compare URL, and recent commits for drafting.
- Sparkle tooling (`generate_keys`, `generate_appcast`, `sign_update`) resides in `bin/`; `just archive`, `just archive` tasks rely on `Sparkle` keys (`SPARKLE_PRIVATE_KEY`, `sparkle-keygen`).

## Workflow expectations

- Start with the smallest repository-specific edit that satisfies the task; avoid introducing new dependencies unless the repo already points that way.
- Keep patches surgical; update or add tests when behavior changes and rerun the narrowest verification covering touched files.
- Preserve the current architecture: `AppStore` orchestrates state, `OpenCodeRuntime` owns the process, UI lives in `AppShell`.
- After changes, report touched files, the commands you ran, and any lingering TODOs (release notes, localization exports, missing assets).
