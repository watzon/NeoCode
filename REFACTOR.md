# Refactor Plan

## Purpose

This document captures the planned pre-release refactor work for NeoCode.

The goals are to:

- reduce release risk by fixing known correctness and state-management issues,
- split large files along feature boundaries,
- remove dead or legacy state that makes future work harder,
- improve testability and verification granularity, and
- leave a clear handoff point after Phase 2.

This plan is intentionally phased so we can land safer changes first and defer larger structural work until after the release-critical hardening is complete.

## Current Refactor Drivers

### Oversized files

- `NeoCode/AppStore.swift` is the highest-priority structural problem. It currently owns app selection state, persistence orchestration, runtime lifecycle, live event subscription, git state, dashboard refresh logic, composer state, queueing, and prompt/session reconciliation.
- `NeoCode/AppShell/ComposerViews.swift` contains multiple unrelated responsibilities: the composer UI, queued message UI, AppKit text view bridge, drag region helpers, status/toast helpers, and shared scroll metrics types.
- `NeoCode/AppShell/ConversationViews.swift` contains conversation layout, transcript paging, scroll coordination, revert flow, prompt overlay coordination, and auxiliary search state.
- `NeoCode/AppShell/SettingsViews.swift` and `NeoCode/Models/SettingsModels.swift` are both carrying too many responsibilities for a single file.
- `NeoCodeTests/NeoCodeTests.swift` is too large to serve as an effective regression surface during iterative refactors.

### Known correctness risks

- Live session status can collapse to `idle` after reconnect or relaunch because remote activity is filtered through local activity assumptions.
- Git UI state is shared too globally, which risks leaking preview/state across project switches.
- Composer option loading is not fully project-scoped and can be overwritten by late async responses.
- Attachment-only prompts can be sent by button but not with keyboard shortcuts.
- Empty text updates in the AppKit composer bridge can skip project-path and callback refreshes.
- Conversation scroll state currently relies on uncancelled delayed callbacks.
- Runtime/user-facing error state is too global for a per-project runtime model.
- Some git fallbacks are too broad and may obscure real failures.

### Dead or near-dead state

- `selectedModelVariant` appears to be legacy state now that reasoning levels are represented by `selectedThinkingLevel`.
- A few small UI helpers appear to be unused or nearly unused and should be verified/removed during cleanup.

## Guiding Principles

- Prefer behavior-preserving moves before logic rewrites.
- Keep `AppStore` as the main observable state owner, but stop treating it as the implementation home for every subsystem.
- Extract by feature boundary first; only introduce new service types when the boundary is stable.
- Run the narrowest relevant verification after each meaningful step.
- Preserve persisted behavior and migration compatibility unless explicitly changed.
- Avoid mixing release-hardening fixes with large UI redesigns.

## Phase 1: Release Hardening

### Goal

Fix correctness issues and remove low-risk dead code without changing the visible architecture more than necessary.

### Scope

#### 1. Session truth and runtime retention

- Fix live session status resolution so remote-running sessions are still represented correctly after reconnect/relaunch.
- Ensure runtime retention decisions do not depend solely on local activity when server state says a session is busy or awaiting work.
- Review `resolvedSessionStatus`, `effectiveLiveSessionActivity`, `terminationBlockReason`, and any runtime-idle shutdown paths.

Primary files:

- `NeoCode/AppStore.swift`

#### 2. Git state correctness

- Stop writing commit preview state for one project into the visible global git UI for another.
- Tighten post-operation refresh logic so follow-up refreshes operate against the intended project.
- Reduce the chance of stale git state after fast project switches or back-to-back git operations.

Primary files:

- `NeoCode/AppStore.swift`
- `NeoCode/GitBranchService.swift`
- `NeoCode/GitRepositoryService.swift`

#### 3. Composer input parity and bridge safety

- Make keyboard send match button send for attachment-only prompts.
- Fix `GrowingTextView.updateNSView` so empty text updates still refresh project path, callbacks, placeholder/theme state, and highlighting dependencies.
- Verify selection restore and auxiliary interaction still work after the change.

Primary files:

- `NeoCode/AppShell/ComposerViews.swift`

#### 4. Conversation scroll safety

- Replace fragile uncancelled delayed callbacks in conversation scroll management with cancellable task-based coordination or other session-safe logic.
- Ensure fast session switching does not produce stray scroll or pin-state updates.

Primary files:

- `NeoCode/AppShell/ConversationViews.swift`

#### 5. Remove dead / legacy code discovered during hardening

- Confirm whether `selectedModelVariant` is fully obsolete; if so, remove it from app state and persisted session composer state.
- Verify and remove small unused helpers if they are truly unreferenced.
- Keep removals surgical and backed by search evidence.

Primary files:

- `NeoCode/AppStore.swift`
- `NeoCode/Models/ComposerModels.swift`
- `NeoCode/AppShell/ComposerViews.swift`

### Deliverables

- Session state reflects remote truth correctly.
- Git preview/status no longer leaks across projects.
- Keyboard send behavior matches button send behavior.
- Conversation scroll logic is safer during session changes.
- Obsolete composer state is removed or formally re-wired.

### Verification

- Add or update unit tests in `NeoCodeTests` for session status, git preview refresh, attachment-only send, and composer state persistence.
- Run targeted `xcodebuild test` for unit tests after each high-risk cluster.

## Phase 2: Structural Decomposition

### Goal

Split the largest files into smaller, feature-scoped files while minimizing behavior changes.

### Scope

#### 1. Split `AppStore.swift` by subsystem

Move implementation into feature-scoped files while keeping the observable type and public surface stable.

Proposed file split:

- `NeoCode/AppStore.swift`
  - keep type definition, stored properties, init, and core cross-feature computed properties only.
- `NeoCode/AppStore+Projects.swift`
  - project selection, workspace selection, session selection, project ordering.
- `NeoCode/AppStore+Composer.swift`
  - model/agent/reasoning selection, composer state persistence, slash command routing, send preparation.
- `NeoCode/AppStore+Git.swift`
  - git refresh, branch switching, repo initialization, commit/push, cached git state.
- `NeoCode/AppStore+Runtime.swift`
  - runtime connection acquisition, idle shutdown, service connection identity, live service lifecycle.
- `NeoCode/AppStore+Events.swift`
  - event subscription, event application, transcript mutation, buffering, streaming recovery.
- `NeoCode/AppStore+Dashboard.swift`
  - dashboard polling, snapshot refresh, range/project filters, dirty session coordination.
- `NeoCode/AppStore+Permissions.swift`
  - permission/question tracking and reply flows.

Note: this phase is primarily a file split. Avoid introducing brand-new coordinators unless a move is impossible without them.

#### 2. Split `ComposerViews.swift`

Proposed file split:

- `NeoCode/AppShell/ComposerViews.swift`
  - `ComposerView` only.
- `NeoCode/AppShell/QueuedMessageViews.swift`
  - queued message stack/cards and delivery controls.
- `NeoCode/AppShell/GrowingTextView.swift`
  - `GrowingTextView`, `ComposerNSTextView`, coordinator, and input bridge logic.
- `NeoCode/AppShell/WindowChromeViews.swift`
  - `WindowDragRegion`, `WindowChromeConfigurator`, related AppKit helpers.
- `NeoCode/AppShell/ComposerSupportViews.swift`
  - `ComposerAttachmentChip`, small status/toast helpers, dropdown models if they are still shared.
- Move `TranscriptScrollMetrics` to the conversation domain if it is primarily used there.

#### 3. Split `ConversationViews.swift`

Proposed file split:

- `NeoCode/AppShell/ConversationViews.swift`
  - `ConversationScreen` and top-level composition.
- `NeoCode/AppShell/ConversationScrollCoordinator.swift`
  - scroll/pinning logic, metrics handling, initial presentation helpers.
- `NeoCode/AppShell/ConversationPromptOverlay.swift`
  - prompt surface, queued message overlay, todo panel integration.
- `NeoCode/AppShell/ConversationMessageGrouping.swift`
  - `buildDisplayMessageGroups` and display-group helpers.
- `NeoCode/AppShell/ConversationRevertFlow.swift`
  - revert preview presentation helpers if still substantial after split.

#### 4. Prepare follow-on splits without fully executing them yet

- Mark internal seams in settings/theme/test files to make Phases 3 and 4 faster.
- Prefer moving shared internal helpers to the file that semantically owns them.

### Deliverables

- `AppStore` behavior preserved with logic split across focused files.
- Composer and conversation files reduced to manageable feature scopes.
- No functional regressions introduced by pure moves.

### Verification

- After each file split cluster, run unit tests.
- Run the full unit suite once Phase 2 is complete.
- If shell/layout behavior changes while moving view code, run UI smoke tests too.

## Phase 3: Settings and Theme Domain Cleanup

### Goal

Untangle settings UI from settings/theme domain models and reduce the size of the theme catalog/model file.

### Scope

#### 1. Split settings UI by section

Proposed file split:

- `NeoCode/AppShell/SettingsViews.swift`
  - top-level screen/sidebar only.
- `NeoCode/AppShell/GeneralSettingsView.swift`
- `NeoCode/AppShell/AppearanceSettingsView.swift`
- `NeoCode/AppShell/SettingsSharedViews.swift`
  - cards, rows, dividers, section scaffolding.

#### 2. Split settings/theme model layer

Proposed file split:

- `NeoCode/Models/SettingsModels.swift`
  - app settings and section enums only.
- `NeoCode/Models/FontCatalog.swift`
  - `NeoCodeFontCatalog` and related font helpers.
- `NeoCode/Models/ThemeProfileModels.swift`
  - `NeoCodeThemeProfile`, `NeoCodeAppearanceSettings`, preset matching.
- `NeoCode/Models/ThemePresetCatalog.swift`
  - preset catalog and load logic.

#### 3. Move preset data out of inline source if worthwhile

- Evaluate whether the large preset JSON literal should become a bundled JSON resource for maintainability.
- Only do this if the bundle/resource path does not complicate app startup or tests too much.

### Deliverables

- Settings UI can evolve section-by-section.
- Theme/font code is easier to test independently.
- Theme catalog is no longer buried inside a huge general-purpose model file.

### Verification

- Unit tests for settings persistence, preset decoding, theme matching, and font normalization.

## Phase 4: Runtime, Transport, and Service Boundary Tightening

### Goal

Clarify the separation between app store orchestration, runtime process management, transport clients, and persistence helpers.

### Scope

#### 1. Runtime error scoping

- Move runtime error presentation toward a per-project model.
- Ensure background runtime failures do not leak confusingly into other selected projects.

#### 2. Runtime startup resilience

- Reduce dependence on a single exact log-line format when detecting the listening URL.
- Explore alternate startup signals if the CLI supports them, or make the parser more tolerant.

#### 3. Service interfaces and ownership

- Review whether `DashboardStatsService`, notification handling, sleep assertion handling, and workspace-tool handling should expose narrower interfaces to the store.
- Keep `OpenCodeRuntime` as the runtime owner, but consider whether some orchestration code belongs in dedicated helpers.

#### 4. Persistence organization

- Revisit whether persistence helpers should remain as-is or be reorganized under a clearer storage namespace.
- Keep migration behavior stable.

### Deliverables

- Cleaner runtime/service boundaries.
- Better project isolation for runtime failures.
- More resilient startup behavior.

### Verification

- Unit tests for runtime startup parsing and runtime error behavior.
- Focused build/test passes after any transport/runtime change.

## Phase 5: Test Suite Reorganization and Final Cleanup

### Goal

Turn the current monolithic unit test file into focused suites that make regression detection and iterative development faster.

### Scope

#### 1. Split `NeoCodeTests/NeoCodeTests.swift`

Proposed test file split:

- `NeoCodeTests/AppStoreSessionTests.swift`
- `NeoCodeTests/AppStoreComposerTests.swift`
- `NeoCodeTests/AppStoreGitTests.swift`
- `NeoCodeTests/OpenCodeTransportTests.swift`
- `NeoCodeTests/OpenCodeDecodingTests.swift`
- `NeoCodeTests/RuntimeTests.swift`
- `NeoCodeTests/SettingsAndThemeTests.swift`
- `NeoCodeTests/TranscriptRenderingTests.swift`

#### 2. Consolidate helper fixtures

- Extract duplicated JSON payloads, stubs, and helpers where doing so improves readability.
- Avoid over-abstracting tests; readability is more important than DRYness here.

#### 3. Final cleanup sweep

- Remove any remaining obsolete properties, helpers, and transitional compatibility code that became unnecessary after the earlier phases.
- Do one more pass for naming consistency and file placement.

### Deliverables

- Tests map cleanly to the architecture.
- Refactors become easier to verify selectively.
- Remaining transitional clutter is removed.

### Verification

- Full unit suite.
- UI smoke tests.
- Release build before the next release cut.

## Phase-by-Phase Exit Criteria

### Phase 1 complete when

- known correctness bugs are fixed,
- dead/legacy state targeted for removal is resolved,
- new or updated tests cover the fixes.

### Phase 2 complete when

- `AppStore.swift`, `ComposerViews.swift`, and `ConversationViews.swift` are materially smaller,
- feature logic is split into coherent files,
- behavior remains unchanged aside from the Phase 1 bug fixes.

### Phase 3 complete when

- settings UI and theme/font models are split into coherent files,
- large inline catalog/model complexity is reduced.

### Phase 4 complete when

- runtime and service boundaries are clearer,
- per-project runtime behavior is more explicit and robust.

### Phase 5 complete when

- the test suite is decomposed into focused files,
- the repo is ready for subsequent feature work with lower refactor friction.

## Recommended Execution Order For This Session

1. Land Phase 1 correctness fixes with tests.
2. Remove confirmed dead/legacy state touched by those fixes.
3. Split `AppStore.swift` by feature boundary.
4. Split composer and conversation files.
5. Run targeted tests throughout, then finish with a broader unit test pass.

## Out of Scope For Phases 1 and 2

- visual redesigns,
- product behavior changes unrelated to correctness,
- persistence format rewrites without a clear need,
- introducing third-party dependencies,
- broad architectural rewrites that invalidate existing test coverage.
