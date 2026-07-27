# PractiQuest 2.0 — Codex/Claude Handoff

Read first:

1. `PROJECT_STATE.md`
2. this file
3. `Docs/FIREBASE_DEPLOYMENT_RUNBOOK.md` before any Firebase action
4. `Docs/PHYSICAL_DEVICE_RELEASE_CHECKLIST.md` before calling the client ready

Branch: `codex/launch-hardening`
Version: 2.0.0 (build 31)
Firebase deployed from this branch: **No**

## Verified baseline

The latest exact run passed:

- 58/58 unit tests
- 30/30 UI tests
- 10/10 Firebase emulator/rules tests
- 3/3 Function contract tests

Simulator:
`54EC2207-327E-4262-AE90-3A31D022F394` (iPhone 17 Pro Max, iOS 26.5)

Run:

```text
xcodebuild test \
  -project PracticeBuddy.xcodeproj \
  -scheme PracticeBuddy \
  -destination 'platform=iOS Simulator,id=54EC2207-327E-4262-AE90-3A31D022F394' \
  -parallel-testing-enabled NO
```

Rules:

```text
cd functions
npm run test:rules
```

Function contracts:

```text
cd functions
npm run test:functions
```

## Do not reverse

- v1 UI was intentionally deleted. There is no `practiquestV2UI` flag.
- One Studio Quest theme; do not restore theme/font pickers.
- SwiftUI only; no Rive/Lottie.
- Space Grotesk uses explicit `Face` values. Do not apply `.weight()` to it.
- System body/control type is intentional for Korean glyph coverage.
- Keep `Features/Home/HomeViewComponents.swift`; active engines depend on it.
- Room composition is:
  `empty room → placed decorations → avatar → foreground/lighting`.
- No room artwork may bake in a user/avatar or optional decoration.
- No ads. Do not restore banners, rewarded ads, UMP, or duel ad logic.
- Public Explore stays off for initial production.
- App Store paid access must come from verified StoreKit transactions, never
  client-submitted product identifiers.

## Work completed since the original handoff

Twenty-three launch-hardening commits now sit after the design handoff. They:

- removed the deterministic launch/navigation race;
- unified practice timing, audio ownership, recovery, and persistence;
- rebuilt every practice tool one at a time;
- polished Today, Quest, Community, You, and secondary destinations;
- made profiles relationship-aware;
- added App Check V2 callables for identity, social, friends, Moments, deletion,
  notifications, duels, and trial claiming;
- added production feature flags and Firestore indexes;
- removed all ad infrastructure;
- retired PBTheme/PBLayout/PBTypography compatibility;
- closed remaining interaction seams;
- hardened StoreKit/trial trust;
- added validated custom/Universal friend links and full-surface sharing.

Latest commits:

```text
d3bd68a Complete secure musician invite links
99e4ae6 Harden StoreKit and trial entitlement trust
0cd093d Protect friend mutations with App Check callables
d8d82b0 Retire legacy theme compatibility and expand launch QA
8e402c5 Polish deterministic root experiences
40a40e9 Polish deterministic launch states
```

## Current priority

The simulator implementation is past the main functional rewrite. The next
priority is release operations, in this order:

1. review the Firebase deployment diff and run the preflight;
2. create/verify the Pro product in App Store Connect;
3. deploy through the staged runbook;
4. make an internal TestFlight build;
5. execute the physical-device checklist;
6. fix any device-only defects;
7. recapture final App Store screenshots and finish metadata.

Do not deploy Firebase casually. Legacy HTTP endpoints remain intentionally for
old App Store clients, and App Check enforcement is staged to avoid locking out
legitimate builds.

## Landmines

- CoreSimulator may hang after compiling. Use the reset sequence in
  `PROJECT_STATE.md`; do not misreport a cancelled run.
- `GoogleAdsOnDeviceConversion` may still appear transitively through Firebase
  measurement packages. Google Mobile Ads/UMP and PractiQuest ad code are
  removed; do not confuse a transitive measurement library with an ad placement.
- The older selected visual board contains a baked-in person. That single detail
  is superseded by the empty-room decision.
- Legacy HTTP endpoints, legacy Ad-Free SKU handling, legacy avatar ID, and
  `/join-studio` are compatibility seams, not accidental dead code.
- The Pro product does not exist merely because its identifier is in code.
- Do not say Firebase is deployed, App Check enforcement is observed, or
  physical-device behavior is verified until those steps actually occur.

## End-of-session protocol

Before handing back:

1. run both app test targets;
2. run rules tests if Firebase/rules/Functions changed;
3. update `PROJECT_STATE.md`;
4. state the branch and immediate `git status`;
5. list commits created;
6. record migrations/interfaces/risks and exact results;
7. provide a ready-to-paste handoff prompt;
8. never claim the tree is clean without checking it immediately.
