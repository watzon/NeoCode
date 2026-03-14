# NeoCode Agent Guide

## Purpose

- This repo is a macOS SwiftUI client for OpenCode.
- The app launches per-project OpenCode runtimes, connects over HTTP/SSE, and renders sessions, transcript items, tool output, permissions, questions, and composer state.
- Prefer repository-specific behavior over generic Swift or SwiftUI advice.

## Repo Snapshot

- Xcode project: `NeoCode.xcodeproj`
- App scheme: `NeoCode`
- Targets: `NeoCode`, `NeoCodeTests`, `NeoCodeUITests`
- No `Package.swift`, no SwiftLint config, no SwiftFormat config, no test plan file
- Checked repo-local rules: no `.cursor/rules/`, no `.cursorrules`, and no `.github/copilot-instructions.md`

## Current File Layout

- `NeoCode/AppShell/`: split SwiftUI shell views for composer, conversation, sidebar, markdown, prompts, and transcript rows
- `NeoCode/OpenCode/`: HTTP client, SSE parser, event decoder, and transport/domain models
- `NeoCode/Models/`: app-side project/session/composer models
- `NeoCode/Persistence/`: `UserDefaults` and cache-backed persistence helpers for store state
- Root app files in `NeoCode/`: `NeoCodeApp.swift`, `ContentView.swift`, `AppStore.swift`, `OpenCodeRuntime.swift`, theme, git services, and workspace tool discovery

## High-Value Paths

- `NeoCode/NeoCodeApp.swift`: app entry point; creates `AppStore` and `OpenCodeRuntime` with `@State`, injects them into the environment
- `NeoCode/ContentView.swift`: top-level split view shell; gates runtime bootstrapping during UI tests with `NEOCODE_UI_TEST_MODE`
- `NeoCode/AppShell/ComposerViews.swift`: composer UI, attachments, slash commands, branch creation, and shell window behavior
- `NeoCode/AppShell/ConversationViews.swift` and `NeoCode/AppShell/ConversationHeaderViews.swift`: conversation layout, session header, git actions, and runtime header state
- `NeoCode/AppShell/PromptSurfaceViews.swift`, `NeoCode/AppShell/TranscriptViews.swift`, `NeoCode/AppShell/MarkdownViews.swift`, and `NeoCode/AppShell/SidebarViews.swift`: prompts, transcript rows, markdown rendering, and project/session navigation
- `NeoCode/AppStore.swift`: main app state, persistence hooks, session orchestration, live service caching, event application, and composer options
- `NeoCode/OpenCodeRuntime.swift`: launches `opencode serve`, resolves executables, owns per-project runtime state, and performs health checks
- `NeoCode/OpenCode/OpenCodeClient.swift`: HTTP transport and request building; defines `OpenCodeServicing`
- `NeoCode/OpenCode/OpenCodeEventDecoder.swift`, `NeoCode/OpenCode/OpenCodeModels.swift`, and `NeoCode/OpenCode/OpenCodeSSE.swift`: event decoding, transport models, and SSE framing
- `NeoCode/Persistence/AppStorePersistence.swift`: persisted project, draft, and yolo preference storage
- `NeoCode/GitBranchService.swift`, `NeoCode/GitRepositoryService.swift`, and `NeoCode/WorkspaceToolService.swift`: git helpers plus external editor/file-manager discovery
- `NeoCode/Theme.swift`: canonical color and font tokens
- `NeoCodeTests/NeoCodeTests.swift`: Swift `Testing` suite for decoding, store behavior, and request building
- `NeoCodeUITests/`: XCTest smoke tests for launch behavior

## Build And Test Commands

- List schemes and targets: `xcodebuild -list -project "NeoCode.xcodeproj"`
- Build app: `xcodebuild build -project "NeoCode.xcodeproj" -scheme "NeoCode" -destination 'platform=macOS'`
- Run all tests: `xcodebuild test -project "NeoCode.xcodeproj" -scheme "NeoCode" -destination 'platform=macOS'`
- Run unit tests only: `xcodebuild test -project "NeoCode.xcodeproj" -scheme "NeoCode" -destination 'platform=macOS' -only-testing:NeoCodeTests`
- Run UI tests only: `xcodebuild test -project "NeoCode.xcodeproj" -scheme "NeoCode" -destination 'platform=macOS' -only-testing:NeoCodeUITests`
- Run one Swift Testing case: `xcodebuild test -project "NeoCode.xcodeproj" -scheme "NeoCode" -destination 'platform=macOS' -only-testing:NeoCodeTests/NeoCodeTests/<test-name>`
- Run one UI test: `xcodebuild test -project "NeoCode.xcodeproj" -scheme "NeoCode" -destination 'platform=macOS' -only-testing:NeoCodeUITests/NeoCodeUITests/<test-name>`

## Linting And Verification Expectations

- There is no dedicated lint command in the repo.
- Treat compiler warnings, language-server diagnostics, and focused `xcodebuild` runs as the lint layer.
- Before larger edits, prefer language-server diagnostics for quick Swift feedback.
- Before finishing, run the narrowest relevant `xcodebuild` command that exercises the changed area.
- If you touch `NeoCode/OpenCode/`, `NeoCode/Models/`, or event application in `NeoCode/AppStore.swift`, run unit tests.
- If you touch launch behavior, shell layout, or window chrome, run at least the UI smoke tests if feasible.

## Platform And Toolchain Facts

- Platform: macOS
- Deployment target: macOS 26.1
- Swift version in project settings: 5.0
- App target enables `SWIFT_APPROACHABLE_CONCURRENCY = YES`
- App target enables `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
- Test targets also enable approachable concurrency

## Architecture Rules

- Keep `NeoCode/NeoCodeApp.swift` and `NeoCode/ContentView.swift` thin; they should mostly wire environment state and high-level layout.
- `AppStore` is the main state owner; session selection, persistence, transport coordination, and server event application belong there.
- `OpenCodeRuntime` is the only place that should launch, stop, or health-check the OpenCode server process.
- `OpenCodeClient` and the other files in `NeoCode/OpenCode/` own HTTP, SSE, and payload decoding; do not move transport logic into views.
- Keep git-specific shelling out inside `GitBranchService` and `GitRepositoryService` instead of scattering `Process` usage.
- Keep workspace app/editor discovery inside `WorkspaceToolService`.
- Add new files near the layer they belong to; do not mix UI, runtime, persistence, and transport concerns.

## State Management Rules

- Follow the Observation pattern already in use.
- Shared mutable app state belongs in `@Observable` reference types such as `AppStore` and `OpenCodeRuntime`.
- Preserve `@MainActor` on observable state containers and actor-sensitive tests.
- Access shared state in views with `@Environment(AppStore.self)` and `@Environment(OpenCodeRuntime.self)`.
- Do not introduce singleton globals for app state.

## Type And Modeling Rules

- Prefer `struct` for app models and transport payloads, following patterns like `ProjectSummary`, `SessionSummary`, `OpenCodeSession`, and `OpenCodeCommand`.
- Existing models commonly conform to `Codable` or `Decodable` plus `Identifiable`, `Equatable`, or `Hashable`; match the nearby pattern instead of inventing a new one.
- Use `JSONValue` for mixed-shape server payloads instead of ad hoc `[String: Any]` dictionaries.
- Reuse `JSONDecoder.opencode` for server timestamps and mixed date formats.
- When storing protocol-typed services, use the current `any OpenCodeServicing` style.

## Naming And Style Conventions

- Types use UpperCamelCase.
- Properties, functions, enum cases, and locals use lowerCamelCase.
- Prefer names that describe role and UI meaning instead of implementation trivia.
- View types are noun-based and feature-scoped, for example `ComposerView`, `ConversationScreen`, `SessionHeaderView`, and `MessageRowView`.
- Service and store types are also noun-based, for example `OpenCodeRuntime`, `GitRepositoryService`, and `WorkspaceToolService`.
- Favor small computed properties and focused helpers over long inline branching in `body` implementations.

## SwiftUI Conventions

- Reuse `NeoCodeTheme` colors and `Font.neo*` tokens before introducing new styling constants.
- Match the existing warm, dark, terminal-adjacent visual language.
- Keep the current split AppShell structure; add UI code to the relevant file in `NeoCode/AppShell/` instead of reintroducing a monolithic shell view file.
- Keep previews working when touching previewed views.
- Preserve the existing minimum window sizing expectations around `980x600` unless the task explicitly changes shell layout requirements.

## Concurrency Conventions

- The app defaults toward main-actor-owned state.
- Use `Task` from UI handlers when bridging async work from taps, menus, or gestures.
- Keep async side effects in store, runtime, service, or transport layers rather than rendering helpers.
- Be careful with long-lived tasks in `AppStore`; the store already tracks refresh, persistence, runtime idle, event subscription, and streaming recovery tasks.

## Error Handling Rules

- Prefer early `guard` exits for missing prerequisites, especially in store/runtime entry points.
- Use `do/catch` around async service calls in `AppStore` and surface user-facing failures through `lastError`.
- Keep developer visibility with `Logger` using subsystem `tech.watzon.NeoCode`.
- Favor typed `LocalizedError` enums for reusable client/runtime failures.
- When an operation fails in runtime/store code, preserve both logging and user-facing error state such as `lastError` or `userFacingError`.

## Networking And Runtime Rules

- Preserve the current env-var contract used by runtime launch: `OPENCODE_SERVER_USERNAME` and `OPENCODE_SERVER_PASSWORD`.
- Keep request construction inside `NeoCode/OpenCode/OpenCodeClient.swift`.
- Keep SSE parsing in `NeoCode/OpenCode/OpenCodeSSE.swift` and event decoding in `NeoCode/OpenCode/OpenCodeEventDecoder.swift`.
- If you add or change a server event, update the transport models, decoder, `OpenCodeEvent`, and `AppStore` application logic together.
- Do not hardcode runtime credentials, executable paths, or health-check behavior outside `OpenCodeRuntime`.

## Testing Conventions

- Unit tests use Swift `Testing`, not XCTest.
- Follow the established style in `NeoCodeTests/NeoCodeTests.swift`: `@Suite(.serialized)`, `@Test`, `#expect`, `#require`, and `Issue.record`.
- Mark actor-sensitive unit tests with `@MainActor`.
- Inline multiline JSON payloads are the norm for decode, request, and event tests.
- UI tests launch with `NEOCODE_UI_TEST_MODE=1`; preserve that behavior when changing app startup.
- UI tests intentionally skip if NeoCode is already running, so avoid changes that would force-terminate an active local session.

## Change Guidance By Area

- UI-only change: edit the relevant file in `NeoCode/AppShell/`, `NeoCode/ContentView.swift`, or `NeoCode/Theme.swift`.
- App state change: update `NeoCode/AppStore.swift` first, then adjust models, bindings, and tests.
- Runtime/process change: update `NeoCode/OpenCodeRuntime.swift` and verify startup, stop, and error propagation.
- Transport or event change: update files under `NeoCode/OpenCode/` and add or adjust unit coverage in `NeoCodeTests/NeoCodeTests.swift`.
- Persistence change: update `NeoCode/Persistence/AppStorePersistence.swift` and verify cache migration behavior if relevant.
- Git integration change: keep it inside `NeoCode/GitBranchService.swift` or `NeoCode/GitRepositoryService.swift`.
- Workspace tool integration change: update `NeoCode/WorkspaceToolService.swift` rather than embedding launch logic inside a view.

## Agent Workflow Expectations

- Start with the smallest relevant edit.
- Preserve the current architecture unless the task clearly requires refactoring.
- Avoid introducing new dependencies or tooling unless the repo already points that way.
- Keep patches surgical and repository-specific.
- After edits, verify with the narrowest useful build or test command and report any remaining failures clearly.
