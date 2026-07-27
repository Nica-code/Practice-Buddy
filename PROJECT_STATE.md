# PractiQuest — Authoritative Development State

Last updated: 2026-07-27
Release train: 2.0.0 (build 31), not uploaded
Branch: `codex/launch-hardening`
Internal Xcode target/scheme: `PracticeBuddy`

## Current verification

- Exact simulator command:
  `xcodebuild test -project PracticeBuddy.xcodeproj -scheme PracticeBuddy -destination 'platform=iOS Simulator,id=54EC2207-327E-4262-AE90-3A31D022F394' -parallel-testing-enabled NO`
- Unit tests: 58/58 passed.
- UI tests: 30/30 passed.
- Firebase emulator/rules tests: 10/10 passed.
- Function contract tests: 3/3 passed.
- Korean and Romanian source-key coverage: complete.
- Latest verified commits:
  - `99e4ae6` — StoreKit and trial entitlement trust hardening.
  - `d3bd68a` — secure musician invite links and Universal Link routing.
- Firebase has not been deployed from this branch.
- Physical-device and TestFlight release checks remain open.

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
- Legacy HTTP endpoints remain only for the shipped-client compatibility window.
- Firestore indexes are committed.
- Rules tests cover private data, public projections, minors, relationships,
  friends-only messaging, blocks, Moment audience/expiry, reports, and
  server-owned data.
- Function instance counts and cleanup jobs are bounded.
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
- The new Pro SKU still needs to be created in App Store Connect.

### Assets, localization, and visual evidence

- Avatar rooms are empty assets; avatar and decorations are runtime layers.
- Room layouts store normalized position, scale, orientation, depth, and order,
  with drag and non-drag accessibility controls.
- Current combined visual boards are:
  - `Design/StudioQuest2/QA/launch-quality-root-comparison.png`
  - `Design/StudioQuest2/QA/launch-quality-compact-comparison.png`
  - `Design/StudioQuest2/QA/launch-quality-promax-comparison.png`
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
2. Deploy indexes, backward-compatible Functions, rules, and hosting in the
   documented order.
3. Register/observe App Check debug and production metrics before broader
   Firestore/Storage enforcement.
4. Run the physical-device checklist for audio, recording, backgrounding,
   Family Controls, Live Activities/Dynamic Island, APNs, StoreKit, account
   upgrade, and Universal Links.
5. Run internal then focused external TestFlight migration testing.
6. Capture final release screenshots from the deployed release configuration.
7. Update App Store privacy/age/moderation metadata and submit with the
   `PracticeBuddy` scheme.

## Known infrastructure caveat

CoreSimulator occasionally stalls after building while workers materialize. The
reliable recovery is:

1. cancel the stalled `xcodebuild`;
2. `killall -9 com.apple.CoreSimulator.CoreSimulatorService`;
3. boot the known simulator;
4. wait with `xcrun simctl bootstatus <id> -b`;
5. rerun the exact test command.

Do not count an interrupted run as a failure or a pass.
