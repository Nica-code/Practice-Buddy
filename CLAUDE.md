# Claude Instructions — PractiQuest

Before code:

1. Read `PROJECT_STATE.md`.
2. Read `HANDOFF_TO_CODEX.md`.
3. Read the relevant runbook/checklist for release or Firebase work.
4. Inspect the immediate implementation area; do not re-derive locked
   architecture from old filenames.

## Current baseline

- Branch: `codex/launch-hardening`
- Version: 2.0.0 (31)
- Scheme: `PracticeBuddy`
- Unit: 59/59
- UI: 30/30
- Firebase rules: 10/10
- Function contracts: 3/3
- Clean App Store archive/export: passed; exported IPA contains no internal
  Markdown resources
- Firebase deployed from this branch: indexes, Functions, Hosting, and Storage
  are live; the base rollout is from `3898fe9`, with corrected Hosting and
  `syncEntitlements` from `bd88167`; owner-only Firestore rules are held for
  client cutover

## Locked decisions

- v1 UI is deleted; do not restore it or add `practiquestV2UI`.
- One Studio Quest theme.
- SwiftUI only; no Rive/Lottie/live 3D/cross-platform UI.
- No advertising.
- Space Grotesk requires explicit bundled faces; never add `.weight()` to a
  Space-Grotesk font.
- Body/control copy remains system-native for Korean.
- Room stack:
  `empty room → placed decorations → avatar → foreground/lighting`.
- Avatar and optional decorations are never baked into room artwork.
- Public Explore remains off for initial production.
- Paid Pro access comes from verified StoreKit 2 current entitlements, not
  client-submitted product IDs.

## Active architecture

- Design: `PracticeBuddy/SharedUI/StudioQuestDesign.swift`
- Routing: `PracticeBuddy/App/AppNavigation.swift`
- Shell: `PracticeBuddy/Features/StudioQuest/StudioQuestShell.swift`
- Practice runtime: `PracticeBuddy/Services/PracticeSessionCoordinator.swift`
- Audio ownership: `PracticeBuddy/Services/PracticeAudioSessionCoordinator.swift`
- Tools: `PracticeBuddy/Features/Home/` (active V2 tools despite folder name)
- Identity/social: `PracticeBuddy/Features/StudioQuest/` and Firebase services
- Backend: `functions/index.js`, `firestore.rules`, `firestore.indexes.json`

Do not delete `Features/Home/HomeViewComponents.swift`. It owns active
metronome, shielding, sound, subdivision, and tuner-gauge types.

Legacy HTTP Functions, legacy Ad-Free SKU support, legacy avatar IDs, and
`/join-studio` are deliberate compatibility seams. Remove them only after
production-adoption verification.

## Quality rules

- Use Studio Quest tokens and interaction surfaces.
- Full visible pills/cards/rows own their hit regions.
- Never use decorative controls that look actionable.
- Critical mutations need loading, committed success, failure, and retry.
- Practice completion must use transactional store behavior.
- Do not add a second timer or audio engine outside the shared coordinators.
- Preserve typed route payloads.
- Log diagnostic errors; show recovery-oriented user copy.
- Do not record user-authored content in analytics.
- Use `apply_patch` or precise edits; preserve unrelated changes.

## Required tests

Run both targets before claiming a coding slice complete:

```text
xcodebuild test \
  -project PracticeBuddy.xcodeproj \
  -scheme PracticeBuddy \
  -destination 'platform=iOS Simulator,id=54EC2207-327E-4262-AE90-3A31D022F394' \
  -parallel-testing-enabled NO
```

If Firebase/rules/Functions changed:

```text
cd functions
npm run test:rules
npm run test:functions
```

CoreSimulator can stall while materializing workers. Follow the reset sequence
in `PROJECT_STATE.md`; do not count a cancelled run.

## Firebase and release

Do not deploy without following:

- `Docs/FIREBASE_DEPLOYMENT_RUNBOOK.md`
- `Docs/PHYSICAL_DEVICE_RELEASE_CHECKLIST.md`

Never claim Firebase, App Check monitoring/enforcement, TestFlight,
physical-device behavior, or App Store submission is complete until it actually
is.

App Attest is registered, but DeviceCheck still requires the Apple `.p8` key and
Key ID. Firestore and Authentication App Check remain in Monitoring with no
verified device traffic yet. Do not enable broader product enforcement early.

The app target is a filesystem-synchronized root group. Keep the explicit
Markdown membership exceptions in `PracticeBuddy.xcodeproj/project.pbxproj`;
without them, internal repository documents are copied into the IPA.

Do not deploy `firestore.rules` before reading the rollout state in
`PROJECT_STATE.md`. App Store build 1.0.5 (30) directly queries `users`, while
the v2 rule makes those documents owner-only. The rule requires a coordinated
v2 client/migration cutover.

## End-of-session handoff

1. Check branch and immediate git status.
2. List session commits.
3. Summarize behavioral changes.
4. Record interfaces, migrations, compatibility seams, and unresolved risks.
5. Record exact tests.
6. Update `PROJECT_STATE.md`.
7. Update the handoff document.
8. Provide a ready-to-paste prompt for the next agent when Nica requests one.
9. Do not push unless Nica requested or authorized it.
