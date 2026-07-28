# PractiQuest Rebuild Plan — Phase 0 Output

Date: 2026-07-28
Companion to `Docs/RebuildAudit.md`. Read that first — this plan only makes
sense in light of what it found: most of the brief's "rebuild" target
architecture already exists on `codex/launch-hardening`.

## Ground rule

Because this is a shipping release branch with locked decisions in
`CLAUDE.md`, no phase below touches the four-tab shell, the
`PracticeSessionCoordinator`/`PracticeAudioSessionCoordinator` pair, the
`AppRouter`/`AppRoute` system, or the `StudioQuestTokens` design system as
architecture. Those are preserved per §10 of the audit. Work here is scoped
to the concrete gaps found in §11 of the audit, plus screen-level visual
QA the brief asked for — not a ground-up replacement.

## Proposed phases

### Phase A — Dock/safe-area fix (highest priority; addresses the one
confirmed user-facing bug)

- Replace the hand-measured `studioQuestDockClearance` environment value +
  manual `.padding(.bottom, dockClearance + ...)` call sites with a
  `safeAreaInset(edge: .bottom)`-based approach, or verify and rely on
  `tabViewBottomAccessory`'s own reserved-space contract if it already
  publishes an accurate inset (needs a quick spike to confirm what
  `tabViewBottomAccessory` guarantees on this deployment target, iOS 26.2+).
- Verify across: Dynamic Type XL, iPad, rotation, and the dock's
  expanded/collapsed states (if it has both).
- Add a UI test asserting no content is obscured by the dock in the largest
  Dynamic Type size on the smallest supported device.
- Files: `StudioQuestShell.swift`, `StudioQuestDesign.swift`,
  `StudioQuestDestinationViews.swift:531-556`.

### Phase B — Targeted cleanup

- Delete empty `Features/Profile/` and `Features/History/` directories.
- Spot-check the 144 unstructured `Task {}` sites for missing cancellation /
  retain-cycle risk, prioritizing ones inside views (view lifecycle) over
  ones inside long-lived service singletons.
- No behavior change expected; this is risk reduction, not a feature.

### Phase C — "Quest" → "Journey" rename

- Rename the user-facing tab label (`AppDestination.quest.title`) and any
  copy/doc references from "Quest" to "Journey," keeping the underlying
  `AppDestination.quest` case/rawValue and `AppRoute` cases stable (the enum
  is `Int`-backed via `AppStorage`, so no persisted-state migration is
  needed). Internal Swift symbol renames (e.g. `StudioQuestQuestView` →
  a "Journey"-named view) are optional cosmetic follow-up, not required for
  correctness.
- Confirm this doesn't collide with any external contract (deep links,
  analytics event names) — grep for `"quest"` in Universal Link handling and
  `PracticeAnalytics` event names before renaming anything beyond the label.

### Phase D — Large-file decomposition (optional, lower priority)

- Split `JourneyProgressManager.swift` (2997 lines),
  `StudioQuestSecondaryViews.swift` (2405 lines), and
  `PracticeStudioView.swift` (1801 lines) along existing responsibility
  boundaries (e.g. progression math vs. persistence vs. view composition).
- Refactor only — no behavior change, and each split should land as its own
  reviewable commit with tests still green.

### Phase E — Screen-level design-token adherence audit

- Rather than rebuilding the design system, audit whether every screen
  actually uses `StudioQuestTokens`/`StudioQuestScrollPage`/shared row and
  button styles consistently, or whether any screen has drifted into
  one-off styling. This is the closest match to the brief's visual-hierarchy
  complaints, if they're real anywhere in the app today.
- Requires visual inspection (simulator screenshots per screen, light/dark,
  a couple of Dynamic Type sizes) before deciding anything needs to change.

## Explicitly out of scope unless you decide otherwise

- Any rewrite of the tab shell, navigation architecture, or session/timer
  ownership — the audit found these already correct.
- Building a new design-token system — one exists and is in active use.
- Anything touching Firestore rules cutover, DeviceCheck/.p8 registration,
  TestFlight, or App Store submission — those are tracked separately in
  `PROJECT_STATE.md` §"Release gates still open" and are unrelated to this
  UI/architecture request.

## Requested decision points before starting any phase above

1. Confirm Phase A (dock fix) as the immediate priority — this is the one
   complaint from the original brief that the audit actually substantiates.
2. Confirm whether Phase E (visual audit) should happen via simulator
   screenshots you review, or whether there's a specific screen you already
   believe looks wrong — the audit did not find "generic AI UI" symptoms in
   the token system itself, so a screen-by-screen visual pass is the only way
   to confirm or rule out the complaint.
3. Confirm the "Quest" → "Journey" rename is still wanted given it's a
   user-facing string change on a release branch close to submission.

## Test plan for any of the above

Per `CLAUDE.md`, before claiming any phase complete:

```bash
xcodebuild test \
  -project PracticeBuddy.xcodeproj \
  -scheme PracticeBuddy \
  -destination 'platform=iOS Simulator,id=54EC2207-327E-4262-AE90-3A31D022F394' \
  -parallel-testing-enabled NO
```

If Firebase/rules/Functions files change (none of the phases above should
touch them):

```bash
cd functions
npm run test:rules
npm run test:functions
```
