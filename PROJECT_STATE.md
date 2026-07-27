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
- Signed generic iOS build: passed for the `PracticeBuddy` scheme, including
  `PracticeBuddyLiveActivityExtension`.
- Clean App Store archive and `app-store-connect` export: passed. The exported
  IPA was inspected and contains no repository Markdown/internal planning files.
- Korean and Romanian source-key coverage: complete.
- Latest verified commits:
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
8. Update App Store privacy/age/moderation metadata and submit with the
   `PracticeBuddy` scheme.

App Store Connect is not authenticated in the current browser session, so no
subscription product or TestFlight upload has been created. The connected
physical iPhone is currently reported offline by Xcode and has not been used to
clear any device checklist item.

## Release archive audit

Build 31 was archived with the `PracticeBuddy` scheme and exported using the
`app-store-connect` export method:

- archive:
  `/private/tmp/PractiQuest-2.0.0-31-clean.xcarchive`
- exported IPA:
  `/private/tmp/PractiQuest-2.0.0-31-clean-export/PracticeBuddy.ipa`

The filesystem-synchronized app target initially copied seven repository
Markdown documents into the bundle. They are now explicit target-membership
exceptions in `PracticeBuddy.xcodeproj/project.pbxproj`. A clean archive/export
was repeated, and the resulting IPA contains no `.md` resources.

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
