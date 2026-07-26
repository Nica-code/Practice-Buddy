# PractiQuest — Project Snapshot

Last updated: 2026-07-26
Release train: PractiQuest 2.0.0 (build 31)
Internal project name: PracticeBuddy
Bundle identifier: `com.alexmalaimare.practicebuddy`
Branch at snapshot: `codex/launch-hardening`

## Product

PractiQuest is an iOS practice companion for musicians. It combines focused and verifiable practice, session planning and reflection, musical tools, progression, friendly competition, and a private social layer.

PractiQuest 2.0 is the Studio Quest overhaul. Its primary experience is no longer a collection of generic dashboards, Forms, Lists, glass cards, and bordered buttons. The app uses one focused four-destination shell and a persistent Practice Dock.

## Technology

- Swift and SwiftUI
- SwiftData for practice sessions and journal/history data
- Firebase Auth and Cloud Firestore
- Firebase Cloud Functions on Node.js 22
- StoreKit 2
- ActivityKit and Live Activities
- Family Controls shielding
- Existing audio, metronome, tuner, rhythm, and intonation integrations
- String Catalog localization for English, Korean, and Romanian

No cross-platform rewrite, third-party UI framework, live 3D engine, Rive runtime, or Unity integration is used.

## Studio Quest shell

Top-level destinations:

1. Today
2. Quest
3. Community
4. You

`AppRouter` owns a typed path for each destination. `AppRoute` retains route payloads for quests, session IDs, practice presets, settings sections, friend IDs, thread IDs, profile IDs, and duel challenge IDs. Changing tabs preserves the other tabs' paths.

Legacy tab values remain readable through `PractiQuestV2Migration`. The `practiquestV2UI` flag remains the internal rollback boundary; production v2 uses the new shell.

## Practice Dock and Practice Studio

The measured dock is a persistent accessory above the tab bar:

- idle: one-tap Quick Start with the last setup;
- planned: next plan and duration;
- running: timer, task, and verification state;
- paused: resume or finish.

`PracticeSessionCoordinator` is the shared source of truth for Today, the dock, Practice Studio, Live Activity state, background timing, verification, check-ins, shielding, tasks, session progress, reflection, and persistence.

Practice Studio includes:

- immediate Quick Start;
- full setup for tasks, duration, verification, and check-ins;
- timer, current task, progress, pause, finish, and verified state;
- metronome and tuner without leaving the session;
- contextual tools drawer;
- reflection for mood, notes, accomplishments, and next step;
- save/discard behavior and history integration.

The Practice Library exposes recents/favorites and routes to Smart Loop, Warm-up Generator, Plan–Execute–Reflect, Rhythm, Intonation, Run-through, metronome, and tuner. Quest-launched sessions use a typed `PracticeLaunchContext` so completion never depends on user-entered text.

## Today

Today focuses on one dominant practice action plus:

- current daily goal;
- recommended/last setup;
- Next Quest;
- recent-session recap;
- small community pulse.

All content uses the responsive page container and can move fully above the Practice Dock.

## Quest and duels

The Quest tab contains a width-bounded 2:3 visual path with normalized node coordinates.

Featured practice quests:

- Warm-up Warrior → Warm-up Generator
- Rhythm Clarity → Rhythm tool
- Dynamic Control → preconfigured verified practice
- Expression Mastery → Run-through mode

Every node opens a typed detail containing objective, progress, reward, status, and CTA. `PracticeQuestProgressStore` persists content-free counters for warm-up, rhythm, dynamic control, expression/run-through, loops, and intonation.

Existing daily/weekly duel quests, league state, rewards, invitations, queue, active match, recording/results, history, and leaderboard behavior remain connected through the rebuilt Duel Arena.

## Community

Community opens on the generated-card Practice Moments feed. Its header leads to
search, Connections, and Messages; Connections locally switches among Friends,
Following, Followers, and Requests.

- Standard Dynamic Type: equal-width segmented navigation.
- Accessibility Dynamic Type: full-width menu.
- Friend rows: avatar, name, optional level context, online/offline status, and coarse last-practice activity.
- Entire friend/message pill is the hit target.
- No row chevrons, long dividers, or generic “Practice buddy” copy.
- Add friend, compose, accept, decline, cancel, contextual message actions, and exact conversation routing are functional.
- Conversation backgrounds are solid semantic surfaces in both appearances.

Practice Moments are optional generated cards only: app-rendered avatar/room,
fixed tag/category, coarse duration bucket, and factual verification badge. They
expire after 24 hours, have no photos, media, captions, comments, or private
reflection data, and support only the bounded musical reaction set. Social
writes—follows, approvals, blocks, mutes, and reports—are Cloud-Function
owned, with age, private-profile, and block precedence enforced server-side.

One root `BuddiesViewModel` supplies friends, requests, and presence.

`FriendActivityPublisher` publishes only a last-practice timestamp into accepted-friend projections. It never publishes duration, notes, pieces, audio, messages, friend codes, or profile content. Sharing is enabled by default and can be disabled in Privacy. Opt-out stops publication, marks the user offline, and clears projections. Online presence expires after 120 seconds.

## You and secondary destinations

You includes:

- a runtime-composed empty-room musician studio hero;
- weekly insight and trend;
- recent session timeline;
- Goals;
- History;
- Settings.

Dedicated Studio Quest destinations:

- Goals: daily/weekly targets, progress, and adaptive controls.
- History: trends, filters, session timeline, notes, detail, and Pro export entry.
- Profile editing is a direct action from the You hero: photo, display name, bio, instrument, avatar identity, and public-profile preview.
- Settings: System/Light/Dark appearance, language, notifications, privacy, retention, Pro, Help, About, sign-out, and account deletion.
- Pro: advanced insights/export, unlimited plans and presets, premium avatar/room collections, and no rewarded-ad prompts.
- Notifications, Practice Library, Duel Arena, Avatar Studio, Help, and About.

The v2 Settings UI ignores the legacy six-theme and four-font-palette preferences. Those values remain stored only for rollback compatibility.

## Design system

`StudioQuestTokens` defines:

- semantic light/dark colors;
- cobalt/violet identity;
- mint verified/success state;
- coral/gold reward and competition state;
- spacing, widths, radii, elevation, motion, and typography.

Typography:

- Space Grotesk for display moments where available;
- SF Pro/system semantic styles for body and controls;
- monospaced system type for timers, tempo, measurements, and scores.

Native materials are reserved for navigation and interactive chrome. Content uses opaque or standard-material semantic surfaces. Ordinary screens do not run a continuously animated full-screen backdrop.

`StudioQuestScrollPage` constrains pages to device width, applies adaptive 16–20 point margins, and adds measured dock clearance. Layouts use wrapping, `ViewThatFits`, or accessibility alternatives rather than fixed horizontal assumptions.

## Avatar identity and assets

`AvatarLoadout` is a versioned `Codable` model containing base, skin tone, hair, outfit, instrument, accessory, pose, room IDs, and room-specific normalized decoration layouts.

Avatar Studio exposes an expandable V2 foundation:

- inclusive starter musician bases with loadout choices;
- 8 skin tones, 12 hairstyles, outfit and instrument selections, accessories, and poses;
- 3 intentionally empty rooms;
- 5 individually owned starter/collectible decorations.

Scene order is always `empty room → placed decorations → avatar → foreground/lighting`.
The room asset never includes a person or an optional decoration. Each room has
its own normalized placement layout; items can be dragged within wall/floor/
surface zones, adjusted with non-drag accessibility controls, removed without
losing ownership, and rendered in front of or behind the avatar through depth.

The renderer is native SwiftUI and uses generated 2.5D raster bases plus native composition. It does not use a live 3D engine. Legacy avatar IDs migrate into starter loadouts and remain written during the compatibility window.

Generated asset provenance and prompts are documented in `ASSET_PROVENANCE.md`.

## Authentication and onboarding

Practice-first onboarding:

1. brand welcome;
2. instrument and goal;
3. optional avatar starter;
4. first practice.

The app continues using anonymous Firebase authentication underneath. Permanent sign-in is requested when entering Community, cloud-linked identity/inventory, account backup, or other account-dependent functionality. User-facing errors use recovery-oriented copy; raw Firebase errors remain diagnostic-only.

## Monetization

- No persistent banner appears in the v2 shell or v2 destinations.
- Rewarded ads are disabled for duels and never interrupt active practice.
- Core practice, verification, messaging, fair duels, and progression remain free.
- PractiQuest Pro recognizes:
  - new product: `com.alexmalaimare.practiquest.pro.monthly`;
  - legacy product: `com.alexmalaimare.practicebuddy.adfree.monthly`.
- Legacy Ad-Free owners are treated as Pro.
- Both product IDs are recognized locally and by `functions/index.js`.

The Pro product still needs to be created in App Store Connect, and the updated entitlement function must be deployed before release.

## Localization and analytics

- `PracticeBuddy/Localizable.xcstrings` contains 1,534 keys.
- Korean missing keys: 0.
- Romanian missing keys: 0.
- Placeholder mismatches: 0.
- `scripts/generate_string_catalog.mjs` and its translation cache maintain the catalog.

`PracticeAnalytics` records bounded, content-free events for onboarding, practice start/save/abandon, dock use, tool discovery, route depth, duel entry, and sign-in conversion. It never records notes, messages, audio, profile text, or friend codes.

## Persistence and migration

Preserved:

- SwiftData sessions and journal/history;
- XP and level;
- league rating and duel history;
- token balances and inventory;
- quest state;
- avatar identity;
- notification preferences;
- subscription entitlements;
- existing friends, requests, and messages;
- legacy tab and appearance/font values for rollback.

New v2 state:

- selected `AppDestination`;
- independent typed navigation paths;
- versioned `AvatarLoadout`;
- practice quest event counters;
- friend activity sharing preference;
- privacy-safe analytics markers.

## Testing and QA

Targets:

- `PracticeBuddyTests/StudioQuestFoundationTests.swift`
- `PracticeBuddyUITests/StudioQuestNavigationUITests.swift`

Foundation tests cover migration, typed path preservation, quest completion/persistence, avatar-room schema/zone clamping, presence expiry, and bounded analytics. UI tests cover the four-tab shell, featured Quest nodes, rebuilt secondary routes, full friend-pill action selection, and accessibility/pseudolocalization.

Visual evidence:

- `Design/StudioQuest2/QA/final-reference-comparison.png`
- `Design/StudioQuest2/QA/final-secondary-destinations.png`
- `Design/StudioQuest2/QA/final-responsive-matrix.png`
- root `design-qa.md`

The app compiles cleanly and the foundation and Studio Quest UI test targets pass on the iPhone 17 Pro simulator.

## Primary files

- Shell and routing:
  - `PracticeBuddy/App/ContentView.swift`
  - `PracticeBuddy/App/AppNavigation.swift`
  - `PracticeBuddy/Features/StudioQuest/StudioQuestShell.swift`
- Destinations:
  - `PracticeBuddy/Features/StudioQuest/StudioQuestDestinationViews.swift`
  - `PracticeBuddy/Features/StudioQuest/StudioQuestSecondaryViews.swift`
- Practice:
  - `PracticeBuddy/Features/StudioQuest/PracticeStudioView.swift`
  - `PracticeBuddy/Services/PracticeSessionCoordinator.swift`
  - `PracticeBuddy/Models/PracticeRuntimeModels.swift`
- Design:
  - `PracticeBuddy/SharedUI/StudioQuestDesign.swift`
  - `PracticeBuddy/SharedUI/PBAvatarView.swift`
- Progress/social:
  - `PracticeBuddy/Services/PracticeQuestProgressStore.swift`
  - `PracticeBuddy/Services/FriendActivityPublisher.swift`
  - `PracticeBuddy/Features/Friends/BuddiesViewModel.swift`
- Commerce:
  - `PracticeBuddy/Services/PurchaseManager.swift`
  - `PracticeBuddy/Features/Settings/StoreView.swift`
  - `functions/index.js`

## Release gates

Before App Store submission:

1. Create the new Pro product in App Store Connect.
2. Deploy updated Firebase Functions and verify entitlement synchronization.
3. Run the final UI suite from a healthy Xcode/CoreSimulator host.
4. Validate anonymous account upgrade, StoreKit purchase/restore/grandfathering, APNs, Live Activities, Family Controls, and audio on physical devices/TestFlight.
5. Capture final release screenshots and complete App Store metadata.
