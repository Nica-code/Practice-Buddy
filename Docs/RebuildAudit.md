# PractiQuest Rebuild Audit — Phase 0

Date: 2026-07-28
Branch audited: `codex/launch-hardening` (2.0.0 build 31, clean working tree)

## 0. Why this document reads differently than a typical rebuild audit

The rebuild brief that triggered this audit describes a codebase with generic
AI-generated visuals, nested `NavigationView`s, Boolean-driven navigation
sprawl, and duplicated/untrustworthy timer state. That description does not
match this repository. This branch is an active, near-shipped release
(signed App Store archive already exported, Firebase partially deployed to
production, 63/63 unit + 30/30 UI tests recorded in `PROJECT_STATE.md`) with
locked architectural decisions in `CLAUDE.md` that already satisfy most of the
brief's stated goals: one root `TabView`, typed per-tab routing, a single
session-state owner, a real semantic design-token system, no `NavigationView`,
no ads, one theme.

This audit reports what is actually here, so any further phase is scoped
against reality rather than the brief's assumed starting point.

## 1. Current architecture map

```
PractiQuestApp (PracticeBuddyApp.swift)
├── FirebaseBootstrap        (.environmentObject, app-root)
├── StudioQuestFeatureFlags  (.environmentObject, app-root)
├── PurchaseManager          (.environmentObject, app-root)
└── ContentView
    ├── SessionStore                    (@StateObject)
    ├── JourneyProgressManager          (@StateObject)
    ├── DuelLeagueManager               (@StateObject)
    ├── FriendRequestBadgeManager       (@StateObject)
    ├── FirebasePresenceManager         (@StateObject)
    ├── StudioChatViewModel             (@StateObject)
    ├── PBNotificationStore.shared      (@StateObject, singleton)
    ├── AppVersionGateManager           (@StateObject)
    ├── PracticeSessionCoordinator      (@StateObject)  ← session owner
    ├── AppRouter                       (@StateObject)  ← routing owner
    ├── BuddiesViewModel                (@StateObject)
    ├── FriendActivityPublisher         (@StateObject)
    ├── IdentityUpgradeCoordinator      (@StateObject)
    └── StudioQuestShell
        ├── TabView(selection: router.selectedDestination)
        │   ├── NavigationStack(path: router.pathBinding(.today))    → Today
        │   ├── NavigationStack(path: router.pathBinding(.quest))    → Quest
        │   ├── NavigationStack(path: router.pathBinding(.community))→ Community
        │   └── NavigationStack(path: router.pathBinding(.you))      → You
        ├── .tabViewBottomAccessory { StudioQuestPracticeDock() }
        ├── .fullScreenCover(roomEditorPresented) → StudioQuestRoomEditorView
        ├── .fullScreenCover(coordinator.studioPresented) → PracticeStudioView
        └── .sheet(momentPromptBinding) → PracticeMomentComposer
```

Each of the four tabs owns exactly one `NavigationStack` bound to its own
`[AppRoute]` path in `AppRouter`, and routes through a single
`.navigationDestination(for: AppRoute.self)`. This is already the "one
NavigationStack per tab, typed routes" structure the brief asks Phase 1 to
build.

## 2. Navigation inventory

- `TabView`: 1 in production code (`StudioQuestShell.swift:13`). A second
  `TabView` exists in `PracticeFirstOnboardingView.swift:34` — an onboarding
  page carousel, not a navigation container; not a violation.
- `NavigationView`: 0.
- `NavigationStack`: ~20 sites. Four are the per-tab root stacks
  (`StudioQuestShell.destinationStack`). The rest are `NavigationStack`
  wrappers inside `.sheet { NavigationStack { ... } }` closures (Pro paywall,
  challenge detail, notifications, community secondary screens, account
  setup) — this is the standard "give a sheet its own nav bar" pattern, not
  nested app-level stacks. Each sheet's internal stack is self-contained and
  does not nest inside a tab's primary stack.
- `NavigationLink`: 19 sites, all leaf-level (row taps pushing a value), none
  bypassing the typed-route system with ad hoc pushes.
- `navigationDestination`: 3 registration sites, all keyed on `AppRoute.self`
  (the four tab stacks share `StudioQuestRouteView`; one extra registration
  exists inside `StudioQuestIdentityViews.swift` for a self-contained sheet
  stack).
- `sheet(...)`: 20 sites across 10 files — paywall, composer, challenge
  detail, notifications, avatar/profile flows. Consistent with "short,
  focused tasks," per the brief's own rule.
- `fullScreenCover`: 2 sites, both in `StudioQuestShell.swift` — room editor
  and the full practice session (`PracticeStudioView`). This matches the
  brief's own guidance ("full-screen reserved for... the active practice
  session").
- Boolean-driven navigation: `roomEditorPresented` and `studioPresented` are
  the only presentation Booleans in the shell, and both gate genuinely modal,
  full-screen experiences, not ordinary navigation. No `showX`/`isShowingY`
  sprawl was found driving primary navigation.

**Conclusion:** the navigation architecture already matches the brief's
Phase 1 target. No structural navigation rebuild is indicated.

## 3. Session / timer state ownership

`PracticeSessionCoordinator` (`Services/PracticeSessionCoordinator.swift`,
1243 lines) is the single `ObservableObject` owning: session id/type/title,
plan, start time, elapsed/remaining time, running/paused/completion state,
current activity, background/foreground transitions (via `scenePhase`),
Live Activity state, launch attribution, recovery, save, and discard. Elapsed
time is derived from `Date()`/`timeIntervalSince` against a stored
`startDate`, not accumulated by a repeating counter — this satisfies the
brief's explicit "favor timestamp math over per-second counters" rule
already.

Other `Timer.publish` usages found (`PulseRhythmAccuracyView`,
`RunThroughModeView`, `ScaleIntonationView`, `PlanExecuteReflectView`,
`JourneyDuelRecordingCaptureView`, `BuddiesViewModel`,
`HomeViewComponents.swift`) are all UI-refresh tickers (redraw a waveform,
refresh a presence badge every 30s) local to their own view/view-model, not
competing session clocks. `HANDOFF_TO_CODEX.md`/`PROJECT_STATE.md` describe
`PracticeAudioSessionCoordinator` as the sole serializer for
metronome/tuner/reference-tone/mic/recording, preventing a second
incompatible audio owner — consistent with what the code shows.

**Conclusion:** one authoritative session/timer owner already exists; no
duplicated session state was found.

## 4. Mini-player / tab-bar conflict (the one concrete complaint that checks out)

`StudioQuestShell` renders the practice dock via the native
`.tabViewBottomAccessory { StudioQuestPracticeDock() }` (iOS 26 API), then
separately measures its height with `onGeometryChange` and publishes a
**hand-rolled** `studioQuestDockClearance` environment value
(`max(92, dockHeight + 26)`) that every scrollable page manually adds as
extra bottom padding (`StudioQuestScrollPage`, plus one more site in
`StudioQuestDestinationViews.swift:556`).

This is a real architectural smell: the app is running a manual safe-area
substitute alongside a native API that already participates in the system's
own safe-area/accessory layout. Two things can go wrong from this:

- If `tabViewBottomAccessory`'s actual reserved space and the app's own
  `dockHeight + 26` estimate disagree (rotation, Dynamic Type growing the
  dock's text, iPad vs. compact width), content is either clipped by the dock
  or has excess dead space below it.
- No `safeAreaInset` is used anywhere in the app (0 occurrences) — the brief
  asks for the mini-player to be handled via safe-area insets specifically
  because that composes correctly with scroll content and other chrome
  without this kind of manual bookkeeping.

**This is the most likely source of the "persistent active-practice bar
conflicts with the tab bar and covers content" complaint**, and it's narrow:
one environment key, one shell file, two consuming call sites.

## 5. Design system

`SharedUI/StudioQuestDesign.swift` (637 lines) already defines:

- `ColorRole` — semantic, scheme-aware (`background`, `surface`,
  `raisedSurface`, `separator`), not screen-specific names.
- `Spacing` — a constrained scale (6/10/16/24/32) plus a responsive page
  margin function, not arbitrary per-view magic numbers.
- `Radius` — exactly four roles (`control`, `surface`, `dock`, `hero`), not a
  different radius per component.
- `Elevation` — a genuinely thought-through light/dark model: shadows carry
  lift in light mode, a strengthening border carries it in dark mode. This
  is more deliberate than the brief's "avoid heavy shadows" guidance assumes
  is missing.
- `Typography` — role-based (`pageTitle`, `heroTitle`, `sectionTitle`,
  `cardTitle`, `statValue`, `timer`, `measurement`, `eyebrow`), with an
  explicit, documented reason Space Grotesk never takes `.weight()`
  (synthesized-weight smearing) and body copy stays system font for Korean
  glyph coverage — both already locked in `CLAUDE.md`.
- `StudioQuestScrollPage` — a shared scrolling-page shell used across
  screens, not ad hoc `ScrollView`s per screen.

**Conclusion:** Phase 2 (build a design system) is already largely done. Any
follow-on work here should audit for *inconsistent usage* of these tokens
across screens, not build new ones.

## 6. Domain/model ownership

No duplicate model types were found. `PracticeSession` (persisted),
`PracticeSessionSnapshot` (in-memory runtime snapshot), and
`PracticeSessionJournal`/`PracticeSessionJournalPiece` (reflection content)
are distinct, clearly named types with non-overlapping responsibilities —
this is the opposite of the "duplicate models" risk the brief warns about.

`ObservableObject` inventory (34 types) shows domain separation by
responsibility: `SessionStore` (persistence/history), `JourneyProgressManager`
+ `DuelLeagueManager` (progression/competition), `PracticeSessionCoordinator`
(active session), `PracticeAudioSessionCoordinator` (audio), `AppRouter`
(navigation), `PurchaseManager` (entitlements), `SocialGraphRepository` /
`BuddiesViewModel` / `StudioChatViewModel` (community), `FirebaseBootstrap`
(auth/backend bootstrap). This maps cleanly onto the brief's own "each domain
should have one clear owner" requirement — it's already satisfied, not a gap.

Two empty leftover directories were found:
`PracticeBuddy/Features/Profile/` and `PracticeBuddy/Features/History/`
contain no files. Harmless (dead scaffolding from a prior reorg), but worth
deleting for hygiene — actual Profile/History screens live under
`Features/StudioQuest/`.

## 7. Code-quality signals

- `try!`: 0 occurrences in `PracticeBuddy/`.
- `fatalError(`: 0 occurrences in `PracticeBuddy/`.
- Compiler warnings on a clean simulator build: **0** (verified this session,
  `xcodebuild build`, same scheme/destination as `CLAUDE.md`'s baseline —
  build succeeded).
- Unstructured `Task { ... }` call sites: 144, with 42 `[weak self]` capture
  sites nearby — plausible lifecycle discipline, but this ratio means most
  `Task {}` blocks are not obviously leak-audited one-by-one in this pass;
  flagged as a spot-check item, not a confirmed bug.
- `NotificationCenter` observer registrations: 4 — low count, low risk.
- Force unwraps: not exhaustively counted this pass (would need a
  higher-signal regex than a blind `!` grep); flagged for Phase 0 follow-up
  if a deeper pass is requested.

## 8. Accessibility / Dynamic Type / localization

- `accessibilityReduceMotion` is read in 6 files (avatar room, rhythm
  accuracy, community feed, destination views, practice studio, onboarding)
  — Reduce Motion is already a designed-for state in the highest-motion
  surfaces (Journey-adjacent avatar room, practice tools), not absent.
- `dynamicTypeSize`/`accessibilityLabel`/`accessibilityValue` appear in 23
  files.
- `Localizable.xcstrings` exists with (per `PROJECT_STATE.md`) complete
  Korean and Romanian coverage for all 779 extracted keys.
- No `safeAreaInset` usage anywhere — see §4.

## 9. Build/test baseline (this session)

- `xcodebuild build` — `PracticeBuddy` scheme,
  `platform=iOS Simulator,id=54EC2207-327E-4262-AE90-3A31D022F394` —
  **BUILD SUCCEEDED, 0 warnings.**
- Full `xcodebuild test` (same scheme/destination, per `CLAUDE.md`'s required
  command) was launched this session; see the end-of-session update for its
  result once complete.
- Firebase rules/function tests were not re-run this session (no
  Firebase/rules/Functions files changed); `PROJECT_STATE.md` records
  10/10 rules and 3/3 function contract tests from the prior verified run.

## 10. What is genuinely worth preserving

Everything in §1–§6: the four-tab shell, typed `AppRoute`/`AppRouter`, the
single `PracticeSessionCoordinator`/`PracticeAudioSessionCoordinator` pair,
the `StudioQuestTokens` design system, the model layer, the Firebase/StoreKit
integration, and all locked product decisions in `CLAUDE.md`. None of this
should be replaced under the brief's Phase 1/2 banner — it would be deleting
already-correct, tested, shipping work.

## 11. What is worth actually fixing

1. **Dock clearance vs. native `tabViewBottomAccessory`** (§4) — the single
   highest-value fix; matches the one concrete visual complaint in the brief.
2. **Very large files** — `JourneyProgressManager.swift` (2997 lines),
   `StudioQuestSecondaryViews.swift` (2405 lines), `PracticeStudioView.swift`
   (1801 lines) are large enough to slow review and risk hidden duplicate
   logic; worth a decomposition pass, but only after the dock fix, and only
   as a refactor (split by responsibility) — not a rewrite.
3. **Empty `Features/Profile/` and `Features/History/` directories** — safe,
   trivial cleanup.
4. **"Quest" → "Journey" tab rename** — the brief specifically asks for this;
   it's a `LocalizedStringKey` + a few doc references, low risk, but touches
   a user-visible label and `AppDestination.quest`'s stored raw value
   (`AppStorage("practiquest.v2.destination")` persists `Int`, so renaming
   the *label* without changing the *case*/rawValue is safe; renaming the
   Swift symbol itself is a larger, purely internal rename with no runtime
   risk since the enum is `Int`-backed, not string-backed).
5. **144 unstructured `Task {}` sites** — spot-check for structured
   lifecycle ownership (cancellation on view disappearance, no retain
   cycles), rather than a blanket rewrite.

## 12. What should not be done

- No tab-structure rebuild — it already matches the target IA (rename aside).
- No session/timer-architecture rebuild — one owner already exists and is
  timestamp-based.
- No design-system rebuild from zero — tokens already exist; if anything,
  audit *screen-level adherence* to the tokens that already exist.
- No deletion of `HomeViewComponents.swift`, StoreKit/Firebase integration,
  or any `CLAUDE.md`-locked decision.
- No restoring v1 UI, adding a second theme, or introducing UIKit/Rive/Lottie.
