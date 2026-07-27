# PractiQuest 2.0 — Project Snapshot

Last updated: 2026-07-27
Release: 2.0.0 (31)
Internal target: `PracticeBuddy`
Bundle ID: `com.alexmalaimare.practicebuddy`

## Product

PractiQuest is a musician practice companion combining focused and verifiable
sessions, musical tools, planning/reflection, progression, friendly competition,
and a private social layer.

Studio Quest 2.0 uses four destinations:

1. Today
2. Quest
3. Community
4. You

The persistent Practice Dock keeps one-tap practice or the active timer
available across the shell. The v1 UI was removed; it is not hidden behind a
runtime flag.

## Platform

- Swift and SwiftUI
- SwiftData
- Firebase Auth, Firestore, Functions, Messaging, Storage, and App Check
- StoreKit 2
- ActivityKit
- Family Controls
- AVFoundation and existing tuner/audio analysis
- String Catalog localization: English, Korean, Romanian

There is no cross-platform layer, third-party UI framework, animation runtime,
live 3D engine, or advertising SDK/placement infrastructure.

## Navigation and deterministic QA

`AppRouter` owns an independent typed navigation path for every top-level
destination. `AppRoute` preserves friend, thread, challenge, quest, profile,
session, practice-preset, Pro-source, and Settings-section payloads.

`AppLaunchConfiguration` is immutable and parsed before shell construction.
Launch arguments can deterministically select:

- onboarding and identity state;
- destination and exact route;
- populated fixtures;
- appearance and Dynamic Type;
- loading, offline, and error states;
- active, paused, recovered, denied-permission, and failed-save tool states.

No `onAppear` path mutation is used to establish the requested launch route.

Validated incoming routes include practice, custom friend invites, Universal
friend invites, notifications, and exact typed app destinations. Friend invite
URLs use `https://practicebuddytracker.web.app/invite?code=XXXX-XXXX`; only the
trusted host and valid code shape are accepted.

## Practice runtime

`PracticeSessionCoordinator` owns:

- stable session identity;
- elapsed time and background transitions;
- active/paused/focused-tool state;
- verification and check-ins;
- distraction shielding;
- task progression;
- Live Activity presentation;
- launch, Quest, and Smart Coach attribution;
- recovery;
- transactional completion;
- Moment eligibility.

`PracticeAudioSessionCoordinator` serializes microphone capture, recording,
tuner listening, reference tone, and metronome playback. Incompatible owners
are replaced only through an explicit user decision.

Standalone tools create a focused session. Tools opened from an active session
attach results to the parent without creating another session or clock.
Timestamp-based phases prevent lost time during backgrounding or delayed frames.

Completion uses `SessionStore.savePracticeCompletion(_:)` to commit a session
and specialized result together. Quest credit, history refresh, success UI, and
Moment offers happen only after a successful commit. Failed saves remain
recoverable.

## Practice tools

The Practice Library provides search, categories, favorites, recents,
capability/availability explanations, and full-surface tool cards.

Rebuilt tools:

- Warm-up Generator
- Smart Loop
- Plan–Execute–Reflect
- Run-through
- Rhythm Accuracy
- Intonation
- Metronome
- Tuner
- Smart Coach

Each uses Studio Quest setup, active, paused, result, permission, recovery, and
error components. Primary tool screens no longer use the retired Form/List
compatibility grammar.

Lifecycle specifics:

- Smart Loop has timestamp work/rest phases, one clean mark per completed
  interval, deterministic tempo progression, and an explained Pro preset gate.
- Guided practice preserves the parent session while nested tools run.
- Run-through asks permission before countdown/metronome/recording and deletes
  orphan files on every abandoned path.
- Rhythm defaults to visual/haptic pulses, distinguishes insufficient input
  from poor timing, and exposes timing distribution/early-late tendency.
- Intonation waits for listening readiness, handles note mappings and reference
  frequencies, and releases the tuner on every exit path.
- Metronome and Tuner share the global audio owner.

## Root experiences

### Today

One dominant Next Practice action, daily goal, contextual Smart Coach, exact
Next Quest, recent session, and a small community pulse. Idle dock presentation
does not compete with the hero.

### Quest

One Journey path and one Duels & Leagues destination. Featured nodes are typed
catalog objects with objective, progress, reward, state, and one CTA:

- Warm-up Warrior
- Rhythm Clarity
- Dynamic Control
- Expression Mastery

Avatar Studio is not in Quest. Duel Arena is not duplicated outside Duels &
Leagues.

### Community

Feed is the root; Search and Messages are header actions. Connections is reached
from relationship/profile surfaces and contains friends, following, followers,
and requests.

Profiles are relationship-aware: Follow, Requested, Following, Friends,
Unfollow, approval, Message, Duel, block, report, mute, and removal states use
server-authoritative rules. The entire friend pill opens its action chooser.
Conversation backgrounds are opaque semantic surfaces.

Practice Moments contain only generated avatar/room artwork, coarse duration,
instrument/category, preset tag, and factual verification state. They contain
no uploaded media, caption, comment, journal text, note, or audio. Reactions are
bounded musical enums. Expiry and cleanup are enforced server-side.

### You

You is the identity/progress destination, not a menu:

- runtime-composed studio room;
- identity and edit profile;
- weekly activity and achievements;
- Avatar Studio and room editor;
- Goals;
- History;
- Pro;
- Settings, Help, and About.

The studio scene is:
`empty room → placed decorations → avatar → foreground/lighting`.

Every decoration is an owned independent item. Placement is normalized and
room-specific, constrained to valid zones, and stores position, scale,
orientation, depth, and order. Users can drag, remove, return to inventory, or
use non-drag accessibility controls.

## Identity and age

Permanent profiles use server-reserved unique handles, display-name validation,
private date of birth, instrument, and privacy selection. Legacy permanent
profiles are gated through schema-v2 upgrade; offline private Today/Practice
remains available.

Age behavior:

- under 13: private practice only;
- 13–17: private account and approval relationships, no public publishing;
- 18+: private by default.

Private `users/{uid}` data is separate from minimal `publicProfiles/{uid}`.
Birth date, email, entitlements, device tokens, internal migration state, and
settings are never public.

## Firebase and social security

V2 client writes use App Check-enforced callable Functions for:

- identity completion/change/privacy;
- trial entitlement;
- friend invite and friend actions;
- social actions, connections, and relationship reads;
- Moment create/reaction;
- account deletion;
- push diagnostics;
- duel queue/invite/respond/attempt lifecycle.

App Attest is preferred with DeviceCheck fallback. Debug/simulator builds use
the Firebase debug provider. Legacy HTTP handlers remain temporarily for shipped
client compatibility; their client-trust paths are hardened.

Firestore rules and emulator tests cover private/public profile separation,
minors, accepted-friend messaging, follow approval, blocks, Moment
audience/expiry, reports, server-owned fields, and deletion constraints.
Compound indexes are committed. Cleanup jobs and Function instances are
bounded.

Feature flags:

- `practiceMoments`: on
- `publicExplore`: off
- `identityUpgradeRequired`: on
- `smartCoach`: on
- `newAvatarRenderer`: on

## Pro and commerce

PractiQuest contains no ads.

Recognized products:

- current: `com.alexmalaimare.practiquest.pro.monthly`
- legacy: `com.alexmalaimare.practicebuddy.adfree.monthly`

Verified StoreKit 2 current entitlements are the authority for paid access.
Legacy Ad-Free owners are Pro. An unexpired server trial or explicit
server/local master status can also grant access. Cached Pro state and
client-submitted product IDs cannot grant paid access.

Pro includes Smart Coach continuation, saved plans/presets, advanced insights,
export, premium avatar collections, rooms/decorations, and cosmetic allowance.
The current Pro product still requires App Store Connect configuration.

## Design and localization

`StudioQuestTokens` defines semantic light/dark colors, explicit Space Grotesk
display faces, SF/system body/control type, monospaced measurement roles,
spacing, radii, elevation, motion, and accessibility variants.

Native glass/material is reserved for navigation, the Practice Dock, and
transient controls. Feed, chat, forms, analytics, history, and content use
opaque semantic surfaces.

Combined design evidence:

- `Design/StudioQuest2/QA/launch-quality-root-comparison.png`
- `Design/StudioQuest2/QA/launch-quality-compact-comparison.png`
- `Design/StudioQuest2/QA/launch-quality-promax-comparison.png`

Reference:
`Design/StudioQuest2/QA/selected-direction.png`, with its baked-in person
superseded by the empty-room architecture.

The generated String Catalog currently contains 779 extracted source keys with
complete Korean and Romanian coverage.

## Verification

- Unit: 57/57
- UI: 30/30
- Firebase emulator/rules: 10/10
- Exact simulator: iPhone 17 Pro Max, iOS 26.5

Coverage includes launch/router determinism, practice clocks/audio ownership,
save/retry, tool recovery and permission states, scoring, file lifecycle,
routes, profile relationships, full-pill actions, room editing, localization,
and accessibility/pseudolocalization reachability.

## Release status

Internal implementation is launch-candidate quality, but release is not
complete until external gates pass:

1. App Store Connect Pro product;
2. staged Firebase deployment and App Check monitoring;
3. internal and focused external TestFlight migration;
4. physical-device audio, route, interruption, background, Family Controls,
   Live Activity, APNs, StoreKit, account-upgrade, and Universal Link tests;
5. final deterministic App Store screenshots and metadata;
6. resolution of every device/TestFlight P0–P2 issue.

Use `Docs/FIREBASE_DEPLOYMENT_RUNBOOK.md` and
`Docs/PHYSICAL_DEVICE_RELEASE_CHECKLIST.md`.
