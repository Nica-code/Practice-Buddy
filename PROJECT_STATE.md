# PractiQuest — Authoritative Development State

Last updated: 2026-07-28
Release train: 2.0.0 (build 31), not uploaded
Branch: `codex/launch-hardening`
Internal Xcode target/scheme: `PracticeBuddy`

## 2026-07-28 session (part 2) — practice session bug fix, check-ins purged, verification onboarding

Uncommitted, same branch, continuing the same day. Follows directly on part 1
below.

- **Root-caused and fixed the "Finish refreshes repeatedly / can't tap
  Finish" bug.** The Practice Studio (`PracticeStudioView`) had a
  full-screen `.overlay` (`PracticeStudioCheckInOverlay`, a "Are you still
  practicing?" modal driven by `checkInManager.isAwaitingResponse`) active
  on the exact same view that also presents `.sheet(isPresented:
  $coordinator.reflectionPresented)` for the post-Finish reflection form.
  `requestFinish()` calls `pause()`, which does not clear a check-in already
  awaiting response — so if a check-in prompt was live when Finish was
  tapped, the full-screen check-in overlay and the reflection sheet
  competed for the same presentation layer simultaneously, which is what
  produced the repeated-refresh/unresponsive-Finish symptom. Fixed by
  deleting the entire check-in mechanism (see below), which removes the
  overlay and the conflict outright. Verified via a new UI test exercising
  the real interaction path (tap "Start practice" → tap Finish → reveal and
  tap "Save session" → confirm return to Today) — see Tests below.
- **Check-ins purged completely**, per explicit instruction ("I don't intend
  to have that implemented anymore"). Deleted
  `Services/PracticeCheckInManager.swift` and `Models/PracticeCheckInModels.swift`
  outright. Removed all check-in state, settings, notification scheduling,
  and persistence keys from `PracticeSessionCoordinator` (renamed
  `checkInStatusMessage` → `verificationStatusMessage`, since that property
  is also used for non-check-in verification messages). Removed the
  check-in fields (`checkInCount`, `missedCheckInCount`, `checkInLogJSON`)
  from `PracticeSessionModel` (SwiftData `@Model` — a schema change; see
  migration note below), `PracticeSessionSnapshot`, `SessionStore`, and
  `SessionExportService`'s CSV/JSON export. Removed the "Check-ins" metric
  from the reflection sheet and the History detail screen (replaced with
  "Unverified" in both places). Removed the "Practice check-ins" toggle and
  interval picker from Practice Setup. Also deleted
  `Models/PracticeSession.swift` — a separate, entirely unused legacy
  `Codable` struct (confirmed zero call sites) that also carried check-in
  fields; simpler to remove than to edit dead code.
  - **SwiftData migration note:** since this is pre-launch (build 31, never
    submitted, no TestFlight/production users), removing stored properties
    from `PracticeSessionModel` was done directly rather than kept as
    unused compatibility columns. Any local dev/QA simulator install with
    an on-disk store from before this change should be deleted/reinstalled
    if it exhibits any SwiftData issue (none observed in this session's
    testing, including on a simulator with pre-existing local session data).
- **Verified/Unverified practice made discoverable**, per instruction that
  it was "too hidden." Two changes:
  1. New onboarding step in `PracticeFirstOnboardingView` — "How should we
     track your practice?" — inserted between the instrument/goal step and
     the avatar step (i.e. before avatar setup, as requested). Lets the user
     choose Verified vs. "just track time" up front; sets
     `coordinator.isVerified` accordingly. Existing skip/complete buttons
     updated to use the chosen value instead of a hardcoded `verified: true`.
  2. New "Practice verification" section in Settings
     (`StudioQuestSettingsView`, new `StudioQuestSettingsSection.practiceVerification`
     case) — exposes the same Verified toggle, distraction-blocking toggle,
     and "Set up distraction protection" action that previously only
     existed inside the Practice Setup sheet. Help screen copy updated to
     point here.
- Also fixed, while in this code: the reflection sheet
  (`PracticeReflectionView`)'s Save/Discard buttons were tight against the
  bottom edge with minimal clearance. Increased bottom padding to
  `StudioQuestTokens.Spacing.xl` and added `.scrollBounceBehavior(.basedOnSize)`.

### Files changed this part

`Services/PracticeSessionCoordinator.swift`, `Services/SessionStore.swift`,
`Services/Export/SessionExportService.swift`,
`Models/PracticeRuntimeModels.swift`, `Models/PracticeSessionModel.swift`,
`Models/PracticeSessionModel+Journal.swift`,
`Features/StudioQuest/PracticeStudioView.swift`,
`Features/StudioQuest/StudioQuestSecondaryViews.swift`,
`Features/Onboarding/PracticeFirstOnboardingView.swift`, `App/AppNavigation.swift`,
`PracticeBuddyUITests/StudioQuestNavigationUITests.swift` (new test:
`testPracticeStudioFinishReachesReflectionAndSaves`). Deleted:
`Services/PracticeCheckInManager.swift`, `Models/PracticeCheckInModels.swift`,
`Models/PracticeSession.swift`.

### Tests (this part)

Same command as below. Added accessibility identifiers `studio.finish`,
`studio.reflection.save`, `studio.reflection.discard` to support the new
test. Full-suite runs during this part surfaced two false leads, both
confirmed unrelated to this session's app-code changes before moving on:

- `testWarmUpRuntimePausesResumesAndReachesAResult` flaked under full-suite
  load (dock/tool-clock drift assertion), passed cleanly in isolation both
  times it was checked — this is the same pre-existing timing-sensitive
  test documented in part 1 of this same day's session, not a regression.
- `testPracticeLibraryCardsAndFavoritesUseTheirFullSurfaces` failed
  reproducibly, including after a full CoreSimulator reset — traced to this
  session's own earlier accessibility-testing artifact: the simulator's
  system-wide Dynamic Type size had been left at `medium` (from testing the
  Today redesign at accessibility sizes) instead of the true default
  `large`. Fixed with `xcrun simctl ui <device> content_size large`; test
  passed immediately after. Not an app bug — a leftover simulator setting
  from this session. Worth knowing if a future session sees unexplained
  layout/hit-testing test failures: check `xcrun simctl ui <device>
  content_size` first.

Final confirmed state after the content-size fix: a clean full-suite run of
94/94 (63 unit + 31 UI, including the new test), 0 failures.

## 2026-07-28 session — audit + dock fix + Journey rename + Today recomposition

Uncommitted on this branch as of this update (not yet committed — no commit
was requested this session):

- `Docs/RebuildAudit.md`, `Docs/RebuildPlan.md` — Phase 0 architecture audit.
  Finding: the "generic AI UI / broken navigation / duplicated timer state"
  premise assumed by the rebuild brief does not match this repo. The
  four-tab shell, typed `AppRoute`/`AppRouter`, single
  `PracticeSessionCoordinator`, and `StudioQuestTokens` design system are
  already structurally sound and were explicitly preserved, not rebuilt.
- `Docs/VisualProductAudit.md`, `Docs/ScreenRedesignSpecifications.md` —
  Phase E1/E2 screen-by-screen audit and redesign spec for Today, Journey,
  Community, You, and practice completion.
- **Dock/safe-area fix**: removed the manually-measured
  `studioQuestDockClearance` environment value (`StudioQuestShell.swift`'s
  `dockHeight`/`onGeometryChange` + the `max(92, dockHeight + 26)` estimate)
  that duplicated what the native `.tabViewBottomAccessory` already reserves
  via safe area. `StudioQuestScrollPage` and the You-tab scroll view now use
  a small fixed `StudioQuestTokens.Spacing.lg` bottom margin instead of
  trying to replicate the accessory's height. Verified live on simulator
  (Journey/Quest tab and You tab, light + dark): content now reaches the
  safe-area boundary correctly, with the standard translucent-tab-bar
  blur-through of the topmost scrolled-past row — no dead gap, no hard
  overlap. Files: `StudioQuestShell.swift`, `StudioQuestDesign.swift`,
  `StudioQuestDestinationViews.swift`.
- **"Quest" tab renamed to "Journey"**: user-facing label only
  (`AppDestination.quest.title`, the Quest-screen page title, one
  accessibility hint, one code comment). `AppDestination.quest`'s Swift
  case name and `Int` rawValue are unchanged — no persisted-state migration
  needed (`AppStorage("practiquest.v2.destination")` stores the raw `Int`).
  Individual challenges are still called Quests. Updated 2 UI test
  assertions (`StudioQuestNavigationUITests.swift`) and the
  `Localizable.xcstrings` entry (Korean/Romanian marked `needs_review` —
  not professionally translated, flagged for review before shipping).
- **Today screen recomposed** (Phase E3): replaced four identically-styled
  `studioQuestSurface()` cards (Smart Coach, Next Quest, Recent Session,
  Community Pulse) with one unsurfaced row list under a single "Next steps"
  label, so the hero ("Next practice"/active-session) is the only card on
  the screen. Added one new shared component, `StudioQuestPlainRow`, to
  `StudioQuestDesign.swift`. No data/service/business-logic changes — this
  is a composition-only change; `store.sessions.first` is now typed
  correctly as `PracticeSessionModel` in the new row helper (was a
  build-breaking typo during editing, fixed before this state was recorded).
  Verified live on simulator: light mode, dark mode, and accessibility XXXL
  Dynamic Type (see known issue below).
- **Known issue found, not fixed this session**: at accessibility XXXL
  Dynamic Type, the Today hero's primary button label truncates to "Start"
  (from "Start practice"), and the hero card alone can reach the fold before
  any scrolling — pre-existing hero-layout behavior, not introduced by the
  dock-clearance fix or the Today recomposition. Not fixed in this pass;
  flagged in `Docs/VisualProductAudit.md` for a future accessibility pass.
- **No preview infrastructure was added.** Zero `#Preview` blocks exist
  anywhere in this codebase; adding real ones for Today's 12 requested
  states would require building fixture-friendly initializers for
  `SessionStore`, `PracticeSessionCoordinator`, `AppRouter`,
  `BuddiesViewModel`, and an in-memory SwiftData container — a genuinely
  separate infrastructure task, not a Today-specific change. Deliberately
  not built this session; live-simulator verification was used instead.
  Flagging as a real gap against the request, not a silent omission.
- Journey, Community, You, and practice-session-completion redesigns are
  **specified but not implemented** — `Docs/ScreenRedesignSpecifications.md`
  covers them; only Today was rebuilt this session, per instruction to stop
  after Today for product review.

### Exact tests run this session

```text
xcodebuild test \
  -project PracticeBuddy.xcodeproj \
  -scheme PracticeBuddy \
  -destination 'platform=iOS Simulator,id=54EC2207-327E-4262-AE90-3A31D022F394' \
  -parallel-testing-enabled NO
```

- Baseline (before any change): 93/93 passed (63 unit + 30 UI), 0 failures.
- After dock fix + Journey rename: 93/93 passed, 0 failures.
- After Today recomposition: two consecutive full-suite runs each showed one
  failure, `testWarmUpRuntimePausesResumesAndReachesAResult`, on the same
  dock/tool-clock timing assertion (2s drift vs. an allowed 1s). It passed
  cleanly every time it was run in isolation. After a clean CoreSimulator
  reset (`killall -9 CoreSimulatorService` + reboot, the recovery sequence
  this file already documents), a third full-suite run passed 93/93 with 0
  failures. Conclusion: simulator-load-induced flakiness in a timing-
  sensitive test that samples two independently-updating live values
  sequentially (not a regression — no timer/clock code was touched this
  session, only layout, padding, and string literals).

## Current verification

- Exact simulator command:
  `xcodebuild test -project PracticeBuddy.xcodeproj -scheme PracticeBuddy -destination 'platform=iOS Simulator,id=54EC2207-327E-4262-AE90-3A31D022F394' -parallel-testing-enabled NO`
- Unit tests: 63/63 passed.
- UI tests: 30/30 passed.
- Firebase emulator/rules tests: 10/10 passed.
- Function contract tests: 3/3 passed.
- Xcode static analysis: passed with no diagnostics for the app and embedded
  Live Activity extension.
- The only deployable Functions source is the root `functions/` codebase named
  by `firebase.json`. The obsolete, undeployed `firebase/functions/`
  teacher-assignment package was removed after its stale dependencies reported
  high and critical advisories. The supported root package reports no
  high/critical production advisory; its remaining moderate transitive `uuid`
  chain requires a breaking `firebase-admin` 14 upgrade and should be reviewed
  separately rather than force-upgraded during release handoff.
- Signed generic iOS build: passed for the `PracticeBuddy` scheme, including
  `PracticeBuddyLiveActivityExtension`.
- Clean App Store archive and `app-store-connect` export: passed. The exported
  IPA was inspected and contains no repository Markdown/internal planning files.
- The current source-exact archive/export was rebuilt from `9b15f8e` after the
  completion audit:
  - `/private/tmp/PractiQuest-2.0.0-31-9b15f8e.xcarchive`
  - `/private/tmp/PractiQuest-2.0.0-31-9b15f8e-export/PracticeBuddy.ipa`
  - SHA-256:
    `f0112da19527f47ed2ce436378c239036b886f5caa7db061fcfcf358a2b9b26c`
- Korean and Romanian source-key coverage: complete.
- Latest verified commits:
  - `3c1b36d` — removed the obsolete undeployed Firebase Functions package.
  - `c411640` — recorded the physical-device launch preflight.
  - `901a035` — refreshed final launch-quality evidence.
  - `d92d31a` — recorded the source-exact completion-audit archive.
  - `9b15f8e` — closed deterministic room, Dock, and audit-evidence gaps.
  - `f699bca` — refreshed release handoff checkpoints.
  - `43e68b8` — recorded the pushed v2 legal-site review branch and browser QA.
  - `d79152a` — pinned the physical release checklist to the source-exact artifact.
  - `5a924e7` — recorded the source-exact signed archive and IPA audit.
  - `e6b3b35` — recorded launch-hardening verification.
  - `5a5827d` — deterministic QA process isolation and safe Apple sign-in anchor handling.
  - `852697e` — recorded privacy release hardening and remaining gates.
  - `c152689` — validated App Store metadata and v2 legal-site requirements.
  - `50fdb9b` — App Store privacy declarations and centralized legal links.
  - `bd88167` — correct App Store identity and lifetime Pro recognition.
  - `43e54b0` — clean App Store export membership hardening.
  - `8b0e6c2` — staged Firebase rollout record and compatibility hold.
  - `4d0955a` — callable rate limits and client recovery copy.
  - `ee26541` — release state and operational runbooks.
  - `99e4ae6` — StoreKit and trial entitlement trust hardening.
  - `d3bd68a` — secure musician invite links and Universal Link routing.
- Firebase rollout from commit `3898fe9` began on 2026-07-27:
  - eight additive Firestore indexes are deployed;
  - all 41 Functions are deployed and active;
  - Hosting/AASA/invite fallback is deployed and verified;
  - Storage rules were already current and were re-released successfully;
  - the owner-only Firestore rules are intentionally **not deployed yet**.
- Physical-device and TestFlight release checks remain open.
- The PractiQuest website v2 legal/support rewrite is prepared and pushed:
  - repository `Nica-code/PractiQuest-Website`;
  - branch `codex/practiquest-v2-legal`;
  - commit `8788602`;
  - not merged or deployed;
  - browser-verified in desktop/mobile, light/dark, Reduce Motion, keyboard,
    44-point navigation, and no-horizontal-overflow states.
- Release privacy hardening is implemented locally:
  - stale Calendar permission copy was removed;
  - microphone copy now covers every microphone-backed v2 capability;
  - the app privacy manifest declares first-party collection plus the
    UserDefaults and system-boot-time required-reason APIs;
  - a packaged-manifest regression test is present;
  - App Store copy, privacy/age answers, and v2 legal-site requirements are
    prepared in `Docs/`.
- QA launches explicitly terminate any previous app process before applying
  their immutable launch configuration. This prevents UIKit scene restoration
  from leaking a prior tab into accessibility/pseudolocalization runs.
- Deterministic launches also reset the local starter room arrangement, so
  screenshot and room-editor fixtures cannot inherit decorations placed by an
  earlier test. A standalone focused-tool fixture advances the canonical
  practice clock as well as the tool phase clock; the Warm-up live panel and
  Practice Dock are asserted to remain within one second of each other.
- The current completion audit and milestone evidence matrix is
  `Docs/LAUNCH_PLAN_COMPLETION_AUDIT.md`.
- Apple sign-in no longer crashes when no presentation scene exists. It uses a
  retained scene-specific presentation provider and exposes a retryable state
  when the app cannot provide a safe anchor.

## Locked product and engineering decisions

- The deleted v1 interface is not a runtime fallback. Rollback is by git/release,
  not `practiquestV2UI`.
- PractiQuest uses one Studio Quest theme in true light and dark appearances.
- SwiftUI only; no Rive, Lottie, Unity, Flutter, or React Native.
- Space Grotesk uses explicit bundled faces. Never add `.weight()` to a
  Space-Grotesk-derived font.
- Body/control copy remains SF/system so Korean has native glyph coverage.
- Do not delete `Features/Home/HomeViewComponents.swift`: it still owns active
  metronome, shielding, sound-style, subdivision, and tuner-gauge symbols.
- The studio scene order is always:
  `empty room → placed decorations → avatar → foreground/lighting`.
- No avatar or optional decoration may be baked into a room asset.
- PractiQuest 2.0 contains no advertising. Ad SDKs and placement infrastructure
  were removed.
- Public Explore is implemented behind `publicExplore` and is off for initial
  production.

## What is complete in the branch

### Deterministic launch and navigation

`AppLaunchConfiguration` is parsed before shell construction. QA destination,
exact route, fixture set, appearance, Dynamic Type, loading/error state, and
tool lifecycle state no longer race persisted navigation. `AppRouter` owns one
typed path per tab and retains associated IDs for chats, profiles, Moments,
duels, quests, sessions, presets, and Settings sections.

The UI-test launcher also forces a clean app process for every deterministic
state. Accessibility and pseudolocalization arguments are covered by a unit
regression test, and persisted UIKit scene state cannot override the requested
QA route.

Incoming links use a validated parser:

- `practicebuddy://practice`
- `practicebuddy://add-buddy?code=AB12-CD34`
- `https://practicebuddytracker.web.app/invite?code=AB12-CD34`

Only the trusted HTTPS host and a valid friend-code shape are accepted. Anonymous
practice links still start practice. Friend invites are retained through account
linking and retried afterward. Profile and Connections share a real invite URL,
not a raw code.

### Unified practice runtime

`PracticeSessionCoordinator` is the single source of truth for the main session
clock, focused tools, background transitions, verification, check-ins, shielding,
Live Activity state, launch attribution, recovery, save, and discard.

`PracticeAudioSessionCoordinator` serializes metronome, tuner, reference tone,
microphone capture, and recording. A second incompatible timer/audio owner cannot
start silently.

Standalone tools create one focused practice session. Contextual tools attach
their result to the active parent session without creating a second clock.
Timestamp-based phases survive backgrounding and delayed frames.

`SessionStore.savePracticeCompletion(_:)` commits the practice session and
specialized result together. Success UI, history refresh, quest credit, and
Moment eligibility occur only after the commit succeeds.

### Rebuilt practice tools

Warm-up, Smart Loop, Plan–Execute–Reflect, Run-through, Rhythm Accuracy,
Intonation, Metronome, and Tuner use Studio Quest pages and shared lifecycle
components instead of the retired Form/List compatibility grammar.

Key safeguards include:

- one clean mark per completed Smart Loop work interval;
- deterministic tempo ladders and visible Pro preset limits;
- parent-clock preservation for nested guided-practice tools;
- permission-before-count-in/recording for Run-through;
- orphan recording cleanup on cancel/failure/discard;
- visual/haptic Rhythm pulse by default and headphone-gated audible scoring;
- listening-ready timing and stop-on-exit for Intonation;
- extracted deterministic rhythm and pitch scoring tests;
- explicit denied, no-signal, interrupted, recovered, and save-retry states.

### Root IA and product parity

- Today: one dominant Next Practice action, goal, Smart Coach, exact Next Quest,
  recent session, and community pulse.
- Quest: one Journey plus one Duels & Leagues destination. Avatar Studio is not
  in Quest and Duel Arena is not duplicated.
- Community: feed root, Search and Messages header actions, relationship-aware
  profiles, full-pill friend chooser, opaque conversations, generated Moments,
  bounded reactions, requests/follows/blocks/reports, and coarse optional
  activity.
- You: integrated identity, empty runtime-composed room, accessible decoration
  editor, Avatar Studio, Goals, History, Pro, Settings, Help, and About.
- Shop: one cosmetic-only destination; no ad or duel advantage path.

### Identity, Firebase, and security

- Private `users/{uid}` data is separated from `publicProfiles/{uid}`.
- Handle reservation, profile upgrade, age-band behavior, privacy, Moments,
  relationships, friends, deletion, notifications, and duels have App
  Check-enforced V2 callable functions.
- App Attest is preferred on production-capable devices with DeviceCheck
  fallback; simulator/debug uses Firebase's debug provider.
- Firebase Console currently has App Attest registered for
  `com.alexmalaimare.practicebuddy`. DeviceCheck is not registered because the
  required Apple `.p8` key and Key ID are not available in the repository.
- Firestore and Authentication App Check remain in Monitoring and currently
  report 0% verified traffic. Do not enable broader product enforcement until a
  TestFlight/physical-device build produces accepted requests.
- Legacy HTTP endpoints remain only for the shipped-client compatibility window.
- Firestore indexes are committed.
- Rules tests cover private data, public projections, minors, relationships,
  friends-only messaging, blocks, Moment audience/expiry, reports, and
  server-owned data.
- Function instance counts and cleanup jobs are bounded.
- `firebase.json` has one authoritative Functions codebase (`functions/`).
  The stale `firebase/functions/` teacher-assignment implementation and its
  vulnerable lockfile were removed; do not recreate a second deployable
  Functions tree.
- V2 callable operations consume server-owned per-user rate-limit windows.
  Clients cannot read or write rate-limit state, and the app maps exhausted
  budgets to recovery-oriented copy.

### StoreKit and Pro trust

- Paid access is derived from verified StoreKit 2 current entitlements only.
- Current Pro and legacy Ad-Free SKUs both grant Pro.
- Server/local master access and a server-issued unexpired trial are supported.
- A stale cached Pro flag cannot grant access.
- Trial claiming uses `entitlementTrialV2` with App Check and a permanent
  identity.
- Legacy `syncEntitlements` rejects client-submitted paid product IDs and never
  persists paid access from them.
- App Store Connect contains:
  - approved monthly Ad-Free subscription
    `com.alexmalaimare.practicebuddy.adfree.monthly`;
  - approved lifetime Pro purchase `practicebuddy.pro.lifetime`;
  - an existing `PractiQuest Ad-Free` subscription group.
- Both legacy products are recognized as Pro from verified StoreKit
  transactions. The new monthly Pro SKU still needs final creation and
  configuration in App Store Connect.

### Assets, localization, and visual evidence

- Avatar rooms are empty assets; avatar and decorations are runtime layers.
- Room layouts store normalized position, scale, orientation, depth, and order,
  with drag and non-drag accessibility controls.
- Current combined visual boards are:
  - `Design/StudioQuest2/QA/launch-quality-root-comparison.png`
  - `Design/StudioQuest2/QA/launch-quality-compact-comparison.png`
  - `Design/StudioQuest2/QA/launch-quality-promax-comparison.png`
- Current-run root, tool, permission, History, and accessibility captures are
  recorded in `Docs/LAUNCH_PLAN_COMPLETION_AUDIT.md`.
- `selected-direction.png` remains the comparison reference, except that its
  baked-in person is explicitly superseded by the empty-room rule.
- `Localizable.xcstrings` and the translation cache were regenerated after the
  invite work; Korean and Romanian are complete for all 779 extracted source
  keys.

## Compatibility code that is deliberate

- Legacy Ad-Free product ID recognition.
- Legacy HTTP Functions while existing App Store clients remain active.
- Legacy avatar ID read/write during the loadout migration window.
- Legacy tab/appearance/font preference reads where needed for migration.
- `/join-studio` hosting/AASA path until old teacher/studio links can be retired.
- `HomeViewComponents.swift` active engines/managers.

Do not remove these merely because their names look old. Remove only after
production adoption/data checks prove they are no longer required.

## Release gates still open

See:

- `Docs/FIREBASE_DEPLOYMENT_RUNBOOK.md`
- `Docs/PHYSICAL_DEVICE_RELEASE_CHECKLIST.md`
- `Docs/INTERACTION_INVENTORY.md`

External/operational work still required:

1. Create `com.alexmalaimare.practiquest.pro.monthly` in App Store Connect.
2. Register DeviceCheck in Firebase Console using an Apple DeviceCheck `.p8`
   private key and its Key ID. App Attest is already registered.
3. Coordinate the owner-only Firestore-rule cutover with an available v2 client.
   Indexes, backward-compatible Functions, Hosting, and Storage are already
   deployed from `3898fe9`.
4. Observe App Check debug and production metrics before broader
   Firestore/Storage enforcement.
5. Run the physical-device checklist for audio, recording, backgrounding,
   Family Controls, Live Activities/Dynamic Island, APNs, StoreKit, account
   upgrade, and Universal Links.
6. Run internal then focused external TestFlight migration testing.
7. Capture final release screenshots from the deployed release configuration.
8. Review and merge website branch `codex/practiquest-v2-legal` at `8788602`,
   verify the deployed privacy/terms/support pages, then publish the prepared
   App Store privacy/age/moderation metadata and submit with the
   `PracticeBuddy` scheme.
9. When npm registry access is reliable, evaluate the supported root
   `functions/` package against `firebase-admin` 14 in a dedicated compatibility
   slice. Do not use `npm audit fix --force` during release operations without
   contract, emulator, and deployment-compatibility verification.

App Store Connect can be browsed in Xcode, but the source-exact TestFlight
upload cannot currently authenticate an App Store Connect provider. The upload
attempt on 2026-07-27 failed before any transfer with exit 70 and:

```text
IDEDistribution.DistributionCredentialedProviderLocatorError.providerRequestFailed(
Unexpected nil property at path: 'Actor/relationships/providerId')
```

Xcode also logged `App Store Connect team IDs for account (null)`. The archive
was not rejected and nothing was uploaded. No App Store Connect API-key
directory or `.p8` credential exists in the standard local
`~/.appstoreconnect` or `~/.private_keys` locations. Recovery requires either
reauthenticating the Apple ID in Xcode Settings → Accounts and confirming its
App Store Connect provider access, or supplying an App Store Connect API key
ID, issuer ID, and private `.p8` file for command-line authentication.

The new Pro creation form is prepared for
`com.alexmalaimare.practiquest.pro.monthly`, but no product has been created or
submitted without the required action-time confirmation. The paired iPhone 17
Pro is now available over a wired CoreDevice connection and already has
developer build 2.0.0 (31) installed. Normal unlocked launch, relaunch, process
residency, and a ten-second idle Time Profiler capture succeeded. The trace
reported no potential hang over 250 ms during that idle interval. The device
runs iOS 27 beta, and no interactive audio, practice, ActivityKit, APNs,
StoreKit, migration, or accessibility checklist item is cleared by this limited
preflight. See `Docs/PHYSICAL_DEVICE_PREFLIGHT_2026-07-27.md`.

The legal-site branch is ready for review at:
<https://github.com/Nica-code/PractiQuest-Website/pull/new/codex/practiquest-v2-legal>.
Merging may deploy the public site. Before merging, confirm
`contact@alexmalaimare.com` is monitored for support, privacy, moderation,
accessibility, and parental requests, and obtain final legal review as
appropriate.

## Release archive audit

Build 31 was archived from verified commit `9b15f8e` with the `PracticeBuddy`
scheme and exported using the `app-store-connect` export method:

- archive:
  `/private/tmp/PractiQuest-2.0.0-31-9b15f8e.xcarchive`
- exported IPA:
  `/private/tmp/PractiQuest-2.0.0-31-9b15f8e-export/PracticeBuddy.ipa`
- exported IPA SHA-256:
  `f0112da19527f47ed2ce436378c239036b886f5caa7db061fcfcf358a2b9b26c`

The filesystem-synchronized app target initially copied seven repository
Markdown documents into the bundle. They are now explicit target-membership
exceptions in `PracticeBuddy.xcodeproj/project.pbxproj`. A clean archive/export
was repeated, and the resulting IPA contains no `.md` resources.

App Store Connect and the public App Store listing confirm the live PractiQuest
Apple ID is `6759354312`. The previously configured `6744359618` was incorrect.
The app fallback and Hosting invite page now use the published ID and have a
unit regression assertion. Hosting and `syncEntitlements` were redeployed from
`bd88167`; the public invite page now contains only the correct App Store link,
and the legacy HTTP endpoint still rejects unauthenticated entitlement claims.

The current IPA was inspected after these corrections:

- Cloud Managed Apple Distribution signing expires 2027-02-18.
- App and Live Activity extension both use production distribution
  provisioning and `get-task-allow = false`.
- The app contains the production APNs, Sign in with Apple, associated-domain,
  and Family Controls entitlements.
- No Markdown file, retired advertising symbol, stale App Store ID, Calendar
  permission, Google Play reference, or ad framework is packaged.
- The current Pro, legacy Ad-Free, and Pro Lifetime product identifiers are
  embedded as expected.

- bundle ID `com.alexmalaimare.practicebuddy`;
- version `2.0.0` build `31`;
- correct App Store ID embedded;
- current monthly Pro and approved lifetime Pro IDs embedded;
- no stale App Store ID;
- no `.md` resources;
- no Google Mobile Ads, User Messaging Platform, AdSupport, or App Tracking
  Transparency framework;
- no stale `alexmalaimare.com/privacy` or `/terms` link;
- packaged first-party privacy declarations and required reasons;
- no Calendar permission key.

Prepared release material:

- `Docs/APP_STORE_RELEASE_METADATA_2.0.md`
- `Docs/LEGAL_SITE_V2_UPDATE.md`
- `scripts/validate_release_metadata.mjs`

The metadata validator passes Apple's current character limits. The live legal
pages are still v1 content and must be updated from the separate
`PractiQuest-Website` repository before submission.

## Current Firebase rollout status

Firebase CLI access was reauthenticated as `contact@alexmalaimare.com`, and
`practicebuddytracker` was confirmed active before deployment.

Verified production state after the staged rollout:

- Firestore composite indexes: 8 present.
- Functions: 41 active, including 18 V2 callables and 2 scheduled jobs.
- Existing production Functions removed: 0.
- V2 request without App Check/auth: rejected with HTTP 401.
- Legacy entitlement request without authentication: rejected; a client product
  identifier cannot grant access.
- Hosting AASA: HTTP 200, `Content-Type: application/json`, `/invite` and
  `/join-studio` both present.
- Invite fallback: valid-code and malformed-code validation logic deployed.
- Storage rules: compiled and current.

Firestore rules remain at the pre-v2 production release. The shipped App Store
build 1.0.5 (30) performs collection queries against `users`; immediately
deploying the v2 owner-only rule would break its social/leaderboard reads.
Coordinate that privacy boundary with the v2 client cutover and migration
testing. Do not deploy `firestore:rules` in isolation before that gate.

## Known infrastructure caveat

CoreSimulator occasionally stalls after building while workers materialize. The
reliable recovery is:

1. cancel the stalled `xcodebuild`;
2. `killall -9 com.apple.CoreSimulator.CoreSimulatorService`;
3. boot the known simulator;
4. wait with `xcrun simctl bootstatus <id> -b`;
5. rerun the exact test command.

Do not count an interrupted run as a failure or a pass.

On 2026-07-27, Xcode 26.5 twice completed all 30 UI tests on the iOS 26.5
simulator and then failed to establish the subsequent `PracticeBuddyTests`
runner connection. The `.xcresult` recorded 30 passed UI tests and one
infrastructure error, not a failed assertion. After a simulator reboot, the
isolated unit target reproduced the iOS 26.5 connection failure. The same unit
target then passed 60/60 on the iPhone 17 Pro Max iOS 26.4.1 simulator
(`9D737516-088B-44FD-906D-38375549A920`). Keep both results explicit until the
Xcode 26.5 unit-host issue stops reproducing.
