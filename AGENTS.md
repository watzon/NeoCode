# NeoCode Agent Guide

## Purpose

- This repo is a macOS SwiftUI client for OpenCode.
- The app launches an OpenCode runtime, connects over HTTP/SSE, and renders sessions, transcript items, tool calls, and composer state.
- Prefer repository-specific behavior over generic Swift or SwiftUI advice.

## Repo Snapshot

- Xcode project: `NeoCode.xcodeproj`
- Main app target: `NeoCode`
- Unit test target: `NeoCodeTests`
- UI test target: `NeoCodeUITests`
- No `Package.swift`, no SwiftLint config, no SwiftFormat config, no test plan file
- No repo-local `.cursor/rules/`, `.cursorrules`, or `.github/copilot-instructions.md` were found

## High-Value Paths

- `NeoCode/NeoCodeApp.swift`: app entry point; injects `AppStore` and `OpenCodeRuntime`
- `NeoCode/ContentView.swift`: top-level split view shell and toast wiring
- `NeoCode/AppShellViews.swift`: primary UI surface; sidebar, conversation screen, composer, markdown rendering, transcript rows, window chrome
- `NeoCode/AppStore.swift`: main app state, session orchestration, event application, composer state, project/session mutations
- `NeoCode/OpenCodeRuntime.swift`: launches `opencode serve`, tracks runtime state, resolves executables, waits for health
- `NeoCode/OpenCodeAPI.swift`: HTTP client, SSE parser, decoders, OpenCode domain models, JSON helpers
- `NeoCode/Theme.swift`: shared colors and font tokens
- `NeoCodeTests/NeoCodeTests.swift`: unit tests using the Swift `Testing` framework
- `NeoCodeUITests/`: basic XCTest UI smoke tests

## Build And Test Commands

- List schemes/targets: `xcodebuild -list -project "NeoCode.xcodeproj"`
- Build app: `xcodebuild build -project "NeoCode.xcodeproj" -scheme "NeoCode" -destination 'platform=macOS'`
- Run all tests: `xcodebuild test -project "NeoCode.xcodeproj" -scheme "NeoCode" -destination 'platform=macOS'`
- Run unit tests only: `xcodebuild test -project "NeoCode.xcodeproj" -scheme "NeoCode" -destination 'platform=macOS' -only-testing:NeoCodeTests`
- Run UI tests only: `xcodebuild test -project "NeoCode.xcodeproj" -scheme "NeoCode" -destination 'platform=macOS' -only-testing:NeoCodeUITests`
- Single Swift Testing suite/test pattern: `xcodebuild test -project "NeoCode.xcodeproj" -scheme "NeoCode" -destination 'platform=macOS' -only-testing:NeoCodeTests/NeoCodeTests/<test-name>`
- Single XCTest UI test pattern: `xcodebuild test -project "NeoCode.xcodeproj" -scheme "NeoCode" -destination 'platform=macOS' -only-testing:NeoCodeUITests/NeoCodeUITests/<test-name>`

## Linting And Verification Expectations

- There is no dedicated lint command in the repo.
- Treat compiler warnings and Xcode diagnostics as the lint layer.
- Before larger edits, prefer language-server diagnostics for quick feedback.
- Before finishing, run the narrowest relevant `xcodebuild` command that exercises the changed area.
- If you touch shared models, networking, or event decoding, run unit tests.
- If you touch app launch, window chrome, navigation, or shell layout, run at least the UI smoke tests if feasible.

## Platform And Toolchain Facts

- Platform: macOS
- Deployment target: macOS 26.1
- Swift version in project settings: 5.0
- App target enables `SWIFT_APPROACHABLE_CONCURRENCY = YES`
- App target enables `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
- Tests also use approachable concurrency settings

## Project Structure Conventions

- The codebase is intentionally compact.
- Most UI lives in `NeoCode/AppShellViews.swift`; check there before creating a new view file.
- `ContentView` and `NeoCodeApp` stay thin and mostly wire environments and high-level layout.
- `AppStore` owns application state and applies server events to local models.
- `OpenCodeRuntime` owns process lifecycle; `OpenCodeClient` owns transport and decoding.
- `Theme.swift` is the canonical place for shared visual tokens.
- Keep new files near the layer they belong to; do not scatter runtime, transport, and UI logic together.

## State Management Rules

- Follow the existing Observation pattern.
- Shared mutable app state belongs in `@Observable` reference types such as `AppStore` and `OpenCodeRuntime`.
- Access shared state in views with `@Environment(AppStore.self)` and `@Environment(OpenCodeRuntime.self)`.
- Do not introduce singleton globals for app state.
- Prefer computed properties on store/model types over duplicating selection or derivation logic in views.
- Preserve `@MainActor` on observable state containers and actor-sensitive tests.

## Type And Modeling Rules

- Prefer `struct` for data models and payloads.
- Existing model types commonly conform to `Decodable`, `Equatable`, and `Identifiable`; match that pattern when appropriate.
- Use small nested helper types for request/response payloads instead of ad hoc dictionaries.
- Keep transport/domain translation close to the transport layer; `OpenCodeAPI.swift` is the precedent.
- Reuse `JSONDecoder.opencode` for server timestamps and mixed date formats.
- When holding protocol-typed services, follow the current `any OpenCodeServicing` style.

## Naming And Style Conventions

- Types: UpperCamelCase
- Properties/functions/locals: lowerCamelCase
- Enum cases: lowerCamelCase
- Use expressive names that describe role, not implementation trivia
- View types are noun-based (`ConversationScreen`, `MessageRowView`, `ErrorToast`)
- Services and stores are also noun-based (`GitBranchService`, `OpenCodeRuntime`, `AppStore`)
- Keep access control tight; many helper types and functions are `private`
- Favor small computed properties to clarify UI state and model presentation

## SwiftUI Conventions

- Reuse `NeoCodeTheme` colors and `Font.neo*` tokens instead of introducing one-off styling values unless a new token is justified.
- Match the existing dark, warm, terminal-adjacent aesthetic.
- Prefer composition through small local `View` structs over huge inline closures.
- Keep top-level view bodies readable by pushing repeated presentation logic into helpers/computed properties.
- Maintain existing environment-driven architecture rather than converting views to `ObservableObject` injection.
- Preserve preview support when touching previewed views.

## Concurrency Conventions

- The app defaults heavily toward main-actor-owned state.
- Use `Task` from UI event handlers when bridging async work from buttons or gestures.
- Mutate observable state on the main actor.
- Keep async side effects in store/runtime/client layers, not inside rendering-only view helpers.
- Use `withThrowingTaskGroup` and continuations only where they materially simplify runtime/process coordination, as seen in `OpenCodeRuntime`.

## Error Handling Rules

- Prefer early `guard` exits for missing prerequisites.
- Use `do/catch` around async service calls in `AppStore` and surface user-relevant failures via `lastError`.
- Log operational failures with `Logger` using the existing subsystem `tech.watzon.NeoCode`.
- Favor typed errors such as `LocalizedError` enums for reusable transport/runtime failures.
- Avoid `fatalError` for recoverable problems.
- When an operation fails in store/runtime code, preserve both developer visibility (log) and user visibility (`lastError` or `userFacingError`).

## Networking And Runtime Rules

- `OpenCodeRuntime` is the only place that should launch or stop the OpenCode server process.
- Do not hardcode server credentials outside runtime configuration.
- Preserve the current env-var contract: `OPENCODE_SERVER_USERNAME` and `OPENCODE_SERVER_PASSWORD`.
- Keep URL/session/request building inside `OpenCodeAPI.swift`.
- SSE parsing and event decoding belong in the API layer, not in views.
- If you add new server event handling, update both decode logic and store application logic.

## Testing Conventions

- Unit tests use Swift `Testing`, not XCTest.
- Follow the existing style: `@Test`, `#expect`, `#require`, and `Issue.record`.
- Mark actor-sensitive unit tests with `@MainActor`.
- UI tests remain XCTest-based.
- Inline JSON payloads in multiline strings are the current norm for decode/event tests.
- When adding server event support, add tests for decode plus store application behavior.
- When adding UI-only behavior, prefer lightweight UI smoke coverage unless the logic can be tested at the store/model layer.

## Change Guidance By Area

- UI-only change: update `AppShellViews.swift`, `ContentView.swift`, or `Theme.swift`; avoid leaking transport logic into views.
- Store/state change: update `AppStore.swift` first, then adjust view bindings and tests.
- Runtime/process change: update `OpenCodeRuntime.swift`; verify startup, stop, and error propagation paths.
- API/event change: update `OpenCodeAPI.swift`; add/adjust decoding tests in `NeoCodeTests/NeoCodeTests.swift`.
- New shared visual treatment: add tokens in `Theme.swift` before scattering literals.

## Agent Workflow Expectations

- Start with the smallest relevant edit.
- Preserve existing architecture unless the task clearly requires refactoring.
- Do not split `AppShellViews.swift` just because it is large; only do so when a task explicitly benefits from extraction.
- Avoid introducing dependencies or tooling unless the repo already points that way.
- Keep patches surgical and repository-specific.
- After edits, verify with the narrowest useful build/test command and report any remaining failures clearly.
