# NeoCode Agent Guide

## Purpose

- This repo is a native macOS SwiftUI client for OpenCode.
- The app launches one OpenCode runtime per project, talks to it over HTTP and SSE, and renders sessions, transcript parts, tool output, questions, permissions, todos, and git state.
- Prefer repository-specific guidance over generic SwiftUI advice.

## Repo Facts

- Xcode project: `NeoCode.xcodeproj`
- Main scheme: `NeoCode`
- Targets: `NeoCode`, `NeoCodeTests`, `NeoCodeUITests`
- Command runner: `just`
- Release docs: `BUILD.md`, `RELEASING.md`, `TRANSLATIONS.md`
- Repo-local AI rule files checked: no `.cursor/rules/`, no `.cursorrules`, no `.github/copilot-instructions.md`

## Project Layout

- `NeoCode/NeoCodeApp.swift`: app entry and test-host bootstrapping
- `NeoCode/ContentView.swift`: top-level split view shell and startup gating
- `NeoCode/AppStore.swift`: main app state, orchestration, persistence hooks, event application, queued sends, dashboard state, git refresh, and composer options
- `NeoCode/AppStore+ComposerOptions.swift`, `NeoCode/AppStore+Git.swift`: store extensions for focused concerns
- `NeoCode/OpenCodeRuntime.swift`: launches `opencode serve`, resolves executables, tracks per-project runtime state, and performs health checks
- `NeoCode/OpenCode/`: transport layer (`OpenCodeClient.swift`, `OpenCodeEventDecoder.swift`, `OpenCodeModels.swift`, `OpenCodeSSE.swift`, `OpenCodeRuntimeHealthClient.swift`)
- `NeoCode/AppShell/`: split SwiftUI feature views for conversation, composer, sidebar, markdown, diff, dashboard, settings, git, prompt surface, transcript, and window chrome
- `NeoCode/Models/`: app-side models for sessions, dashboard, diff, tool calls, settings, themes, and composer state
- `NeoCode/Persistence/`: `UserDefaults` and cache-backed persistence helpers
- `NeoCodeTests/`: Swift Testing suites
- `NeoCodeUITests/`: XCTest launch and smoke coverage

## Build, Test, And Release

- List schemes: `xcodebuild -list -project "NeoCode.xcodeproj"`
- Debug build: `just build` or `xcodebuild build -project "NeoCode.xcodeproj" -scheme "NeoCode" -configuration Debug -derivedDataPath DerivedData`
- Release build: `just build-release`
- Run all tests: `just test` or `xcodebuild test -project "NeoCode.xcodeproj" -scheme "NeoCode" -destination 'platform=macOS'`
- Run unit tests only: `xcodebuild test -project "NeoCode.xcodeproj" -scheme "NeoCode" -destination 'platform=macOS' -only-testing:NeoCodeTests`
- Run UI tests only: `xcodebuild test -project "NeoCode.xcodeproj" -scheme "NeoCode" -destination 'platform=macOS' -only-testing:NeoCodeUITests`
- Run one Swift Testing suite or case: `xcodebuild test -project "NeoCode.xcodeproj" -scheme "NeoCode" -destination 'platform=macOS' -only-testing:NeoCodeTests/<SuiteName>` or `-only-testing:NeoCodeTests/<SuiteName>/<test-name>`
- Run one UI test: `xcodebuild test -project "NeoCode.xcodeproj" -scheme "NeoCode" -destination 'platform=macOS' -only-testing:NeoCodeUITests/NeoCodeUITests/<test-name>`
- Release helpers live in `justfile`; common commands include `just archive`, `just export-app`, `just dmg`, `just notarize dist/NeoCode.dmg`, `just staple dist/NeoCode.dmg`, and `just release X.Y.Z`

## Toolchain And Platform

- Project deployment target in `NeoCode.xcodeproj/project.pbxproj`: macOS 14.0
- Swift version: 5.0
- `SWIFT_APPROACHABLE_CONCURRENCY = YES` for app and test targets
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` for the app target
- The app still follows main-actor-owned state even where project settings are permissive

## Architecture Rules

- Keep `NeoCode/NeoCodeApp.swift` and `NeoCode/ContentView.swift` thin; they should mostly wire state, scenes, and top-level layout.
- `AppStore` is the primary state owner. Session selection, event application, persistence coordination, queued sends, notifications, dashboard refresh, and runtime-facing orchestration belong there.
- `OpenCodeRuntime` is the only place that should launch, stop, or health-check the OpenCode server process.
- Keep HTTP request construction inside `NeoCode/OpenCode/OpenCodeClient.swift`.
- Keep SSE framing inside `NeoCode/OpenCode/OpenCodeSSE.swift` and server event decoding inside `NeoCode/OpenCode/OpenCodeEventDecoder.swift`.
- Keep git shelling-out isolated to `GitRepositoryService.swift` and `GitBranchService.swift`.
- Keep external app and editor discovery in `WorkspaceToolService.swift`.
- Place new files beside the layer they belong to; do not mix UI, transport, persistence, and process concerns.

## State And Concurrency Conventions

- Shared mutable state lives in `@Observable` reference types such as `AppStore`, `OpenCodeRuntime`, and `AppUpdateService`.
- Preserve `@MainActor` on state containers and actor-sensitive tests.
- Views access app state through `@Environment(AppStore.self)` and `@Environment(OpenCodeRuntime.self)`.
- Use `Task` from UI handlers to bridge into async work, but keep the real side effects in store, runtime, or service layers.
- Be careful with long-lived tasks already tracked by the store: refresh, event subscription, runtime idle shutdown, streaming recovery, persistence, dashboard refresh, and git debounce tasks.
- Do not introduce singleton globals for app state.

## Type And Modeling Conventions

- Prefer `struct` for transport and domain models, matching patterns like `ProjectSummary`, `SessionSummary`, `OpenCodeSession`, `OpenCodeCommand`, and theme/settings models.
- Existing models usually conform to `Codable` or `Decodable` plus `Equatable`, `Hashable`, or `Identifiable`; match nearby types.
- Protocol-typed services use existential syntax such as `any OpenCodeServicing`.
- Reuse `JSONDecoder.opencode` for server payloads and date parsing.
- Use `JSONValue` for mixed-shape server payloads instead of inventing `[String: Any]` plumbing.

## Naming And Style

- Types use UpperCamelCase.
- Properties, methods, enum cases, and locals use lowerCamelCase.
- Keep names feature-scoped and role-based: `ConversationViews`, `DashboardSnapshot`, `WorkspaceToolService`, `GitOperationState`.
- Prefer small computed properties and focused helpers over long `body` branches or giant inline transforms.
- Follow the existing split-by-feature file organization inside `NeoCode/AppShell/` and `NeoCode/Models/`.
- Reuse existing terminology from the app: project, session, transcript, prompt, permission, question, todo, dashboard, runtime.

## SwiftUI And UI Rules

- Reuse `NeoCodeTheme` colors and `Font.neo*` tokens before adding new styling constants.
- Preserve the app's warm, terminal-adjacent aesthetic rather than introducing a generic Apple-default look.
- Keep user-facing copy localizable; add strings through `NeoCode/Localization/Localizable.xcstrings` and the app localization helpers rather than hardcoding English.
- Keep previews working when touching previewed views.
- Preserve the hidden-title-bar window treatment and current minimum-size expectations unless the task explicitly changes shell layout.
- When changing transcript or conversation chrome, verify accessibility identifiers used by UI tests such as `conversation.transcript.scrollView` and `conversation.backToBottom` still work.

## Error Handling And Logging

- Prefer early `guard` exits for missing prerequisites; `AppStore.swift` relies on this style heavily.
- Use `do`/`catch` around async service calls and surface user-visible failures through `lastError` or other explicit state.
- Keep structured logging with `Logger(subsystem: "tech.watzon.NeoCode", category: ...)`.
- Reuse typed `LocalizedError` enums for reusable failures such as runtime, client, test-support, or mermaid rendering errors.
- When changing failure flows, preserve both developer visibility in logs and user-facing error state.

## Runtime And Networking Rules

- Preserve the runtime env-var contract: `OPENCODE_SERVER_USERNAME` and `OPENCODE_SERVER_PASSWORD`.
- Do not hardcode runtime credentials, executable paths, or health-check behavior outside `OpenCodeRuntime`.
- If you add or change an event type, update models, decoder, and `AppStore` event application together.
- Keep authorization, multipart body construction, and request payload shaping inside `OpenCodeClient`.

## Testing Conventions

- Unit tests use Swift Testing, not XCTest.
- Test suites are split across files like `OpenCodeDecodingTests.swift`, `OpenCodeTransportTests.swift`, `AppStoreSessionTests.swift`, `AppStoreComposerTests.swift`, `AppStoreGitTests.swift`, `RuntimeTests.swift`, `SettingsAndThemeTests.swift`, `TranscriptRenderingTests.swift`, `ToolCallPresentationTests.swift`, and `ComposerAuxiliaryTests.swift`.
- Swift Testing suites commonly use `@Suite(.serialized)`, `@Test`, `#expect`, `#require`, and inline multiline JSON payloads.
- Shared unit-test helpers live in `NeoCodeTests/TestSupport.swift`.
- UI tests use XCTest and launch the app with `NEOCODE_UI_TEST_MODE=1`; some transcript scroll coverage also uses `NEOCODE_UI_TEST_SCROLL_FIXTURE=1`.
- UI tests intentionally skip if NeoCode is already running; avoid changes that would force-terminate an active local session.

## Verification Expectations

- There is no dedicated linter; treat compiler warnings, Swift diagnostics, and focused `xcodebuild` runs as the lint layer.
- Prefer the narrowest verification that covers the files you changed.
- If you touch `NeoCode/OpenCode/`, runtime launch logic, event decoding, or `AppStore` event application, run unit tests.
- If you touch launch behavior, transcript scrolling, window chrome, or other shell interactions, run the relevant UI smoke tests when feasible.
- If you touch localization behavior, verify the impacted strings still resolve from `Localizable.xcstrings` and keep the XLIFF workflow intact via `export_localizations.sh` and `import_localizations.sh`.

## Practical Change Map

- UI-only work: `NeoCode/AppShell/`, `NeoCode/ContentView.swift`, `NeoCode/Theme.swift`
- Runtime/process work: `NeoCode/OpenCodeRuntime.swift`, `NeoCode/OpenCode/OpenCodeRuntimeHealthClient.swift`
- Transport/event work: `NeoCode/OpenCode/` plus matching tests in `NeoCodeTests/`
- Store/state work: `NeoCode/AppStore.swift` and related model or persistence files
- Git integration: `NeoCode/GitRepositoryService.swift`, `NeoCode/GitBranchService.swift`, `NeoCode/AppStore+Git.swift`
- Settings/theme/localization work: `NeoCode/AppLocalization.swift`, `NeoCode/Localization/Localizable.xcstrings`, theme/settings models and views

## Workflow Expectations

- Start with the smallest repository-specific edit that solves the task.
- Preserve the current architecture unless the request clearly requires refactoring.
- Avoid new dependencies or new tooling unless the repo already points that way.
- Keep patches surgical, and update tests when behavior changes.
- After changes, report the exact files touched and the narrowest verification you ran.
