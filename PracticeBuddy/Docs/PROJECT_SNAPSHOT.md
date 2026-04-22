PractiQuest — Project Snapshot (Current)

Last updated: 2026-04-21
Repository root: `/Users/nica/Downloads/Apps/PracticeBuddy/PracticeBuddy`
Branch during snapshot update: `codex/launch-hardening`

## 1) Product Overview
PractiQuest is an iOS practice companion app for musicians focused on:
- practice timer and verified practice tracking
- duet/duel progression and quests
- social layer (friends + direct chat)
- profile progression and token-based cosmetic inventory
- ad-supported free experience with optional Ad-Free monthly subscription

Public app name is `PractiQuest`. Internal project/repo naming remains `PracticeBuddy`.

## 2) Platform + Tech Stack
- UI: SwiftUI
- Local persistence: SwiftData (practice sessions, journaling/history models)
- Backend: Firebase Auth + Cloud Firestore
- Server: Firebase Cloud Functions (Node.js 22, 2nd gen)
- Push: APNs + Firebase Cloud Messaging
- Monetization: StoreKit 2 (Ad-Free monthly)
- Ads: Google Mobile Ads SDK integration via `PBAdsManager`
- Localization: English, Korean, Romanian

## 3) App Structure (Current)
Top tabs:
1. Home
2. Play (Journey / Duels)
3. Social
4. Profile
5. Settings

### Notes
- The old teacher/student Studio Manager/Planner flow was removed from active UI.
- `StudioHubView` now serves as the Social host surface (Friends + Chat segmentation).

## 4) Authentication + Onboarding
Current sign-in surface (`AccountSetupView`):
- Continue with Google
- Continue with Apple
- Sign up/sign in with Email + Password (sheet flow)
- language picker available on onboarding (EN/KO/RO)
- message indicating app is actively improving

Firebase auth handling is in `FirebaseBootstrap` and includes:
- Google OAuth sign-in
- Apple sign-in with nonce
- email/password sign-up and sign-in
- sign-out support

Display name constraints are normalized and Firestore rules enforce valid format/length.

## 5) Home (Practice)
Home currently centers around a consolidated practice flow:
- Practice Timer
- Verified Mode toggle and verification detail panel
- check-in system + check-in status UI
- Practice Session Builder (task list with minutes, add/remove tasks, progress tracking)
- Practice Tools (Metronome, Tuner)
- Goal section
- Practice Time summary cards
- save/discard session flow + journal capture

### Verified practice / shielding
- Family Controls entitlement is present in app entitlements.
- App shielding and check-ins are wired into the timer flow.
- Verified vs unverified seconds are tracked and displayed.

## 6) Play (Journey / Duels)
`JourneyView` includes:
- progression level card and XP
- daily and weekly quests (duel-focused)
- rewards inventory integration
- duels and league section:
  - Queue Duel / Cancel Queue
  - invite friends to duel
  - incoming/outgoing invite handling
  - active duel entry and recording capture flow
  - match history screen
  - season ladder scopes
  - unified duel action card styling (Queue Duel / Invite Friend / Match History)
  - outgoing invites surfaced as a dedicated card block for better clarity

Play top shortcuts now include a bell icon with unread badge, opening a full-screen notifications inbox.

Duel + rating state management is in `DuelLeagueManager` and synced to Firestore.

## 7) Social
Social is consolidated into:
- Friends view (friend code, requests, buddies, leaderboard)
- Chat view (friend DMs thread model)

Chat system (`StudioChatViewModel`) currently uses friend thread semantics (`friend` kind). It supports:
- thread list
- unread counting
- open thread routing
- send message flow
- local thread state (pin/mute/hide/read)

App icon badge count is composed from:
- pending friend requests
- unread social chat

## 8) Profile
Profile includes:
- top profile card + level/league display
- progress section
- icon selection section with carousel UI
- free icons + token-unlock icons
- token-gated unlock flow backed by `JourneyProgressManager`
- personalize section (instrument/bio)

Avatar unlock ownership is persisted and synced through user inventory fields.

## 9) Settings
Settings currently includes:
- Goals
- Appearance (themes/fonts)
- General (language, replay tutorial)
- Account (Sign Out)
- Notifications (category toggles + open iOS settings)
- History retention
- About

Debug-only controls:
- `Send Test Push` and Ads debug toggles appear only under debug/master-account conditions.

## 10) Shop, Subscription, Ads
### Shop
`ShopView` currently has:
- Ad-Free monthly subscription section
- 7-day trial trigger path
- Restore purchases
- Cosmetics (Coming soon) + Open Inventory link
- Skins (Coming soon)
- Bundles (Coming soon)

### Purchase model
`PurchaseManager` + server sync are aligned to Ad-Free subscription:
- product id: `com.alexmalaimare.practicebuddy.adfree.monthly`
- entitlement/trial state synced via function endpoint `syncEntitlements`

### Ads
`PBAdsManager` controls:
- banner ads (Play + Social placements)
- rewarded duel ad option
- debug placeholders / SDK toggles (debug/master only)
- kill switch and consent gating

Configured production IDs are in `Info.plist`:
- AdMob app id
- play banner unit id
- rewarded duel unit id

## 11) UI/Theming State
Recent shared styling refactor pushed UI toward Liquid Glass aesthetics through shared primitives:
- `PBLayout` (card/backdrop glass styling)
- `PBShortcutBar` (glass chip styling)

This centralization improves consistency across tabs/popups that use shared components.

## 12) Notifications + Push
Push infrastructure present:
- APNs token registration
- FCM token storage under `users/{uid}/devices/{deviceId}`
- category preference sync from app to backend/user document
- app routing handler for notification deep-links (`PBNotificationRoute`)
- in-app notifications inbox (`PBInAppNotifications`) shared across tabs
- top bell badge count currently aggregates:
  - duel invites
  - friend requests
  - chat unread threads
- tapping any in-app notification now routes to destination:
  - duel invite -> Play duel entry
  - friend request -> Social friends/pending requests
  - chat message -> exact Social chat thread

Cloud Functions include push triggers for:
- friend invite created
- friend chat message created
- studio chat message created (legacy/compat path)

## 13) Backend (Functions + Rules)
### Functions currently exported (`functions/index.js`)
- `syncEntitlements`
- `pushTestNotification`
- duel lifecycle endpoints (`duelQueueJoin`, `duelQueueCancel`, `duelInvite`, `duelRespond`, `duelSubmitAttempt`, `duelSettleSweep`)
- push triggers (`onFriendInviteCreated`, `onFriendChatMessageCreated`, `onStudioChatMessageCreated`)

### Firestore rules
Current rules enforce:
- protected server-only duel writes
- friend invite/friendship/chat access policies
- display-name validation
- restricted entitlement fields on user docs

Note: rules still include legacy studio/assignment paths for compatibility, while related app-side studio manager/planner/assignment UI and repos were removed.

## 14) Major Removals / Simplifications (Recent)
Removed from active codebase:
- `StudioManagerView`, `StudioPlannerView`, `StudioManagerViewModel`
- assignment-specific services and notification manager
- old studio repository (`FirebaseStudiosRepository`)
- warmup-of-week manager
- app icon picker / multi-icon manager
- alternate icon asset sets and old preview icon sets

## 15) Branding + App Identity
- Display name: `PractiQuest`
- Bundle identifier remains: `com.alexmalaimare.practicebuddy`
- URL scheme remains: `practicebuddy://`
- Associated domain configured: `applinks:practicebuddytracker.web.app`

## 16) Entitlements / Capabilities (Current)
`PracticeBuddy.entitlements` currently includes:
- `aps-environment` (development)
- Sign in with Apple entitlement
- associated domains
- Family Controls entitlement

Info.plist highlights:
- `ITSAppUsesNonExemptEncryption = false`
- portrait orientation on iPhone
- background modes include `audio` and `remote-notification`

## 17) Localization
Active app languages:
- English
- Korean
- Romanian

Onboarding now allows immediate language selection before sign-in.

## 18) Current Build/Source Control Status at Time of Snapshot
- Branch: `codex/launch-hardening`
- HEAD commit observed in audit: `72ce230`
- Local uncommitted change observed: build number bump in `project.pbxproj` (`CURRENT_PROJECT_VERSION` 19 -> 20)

## 19) Known Follow-up Items
- Firestore rules still contain legacy studio/assignment blocks; can be cleaned once no longer needed by any deployed clients/functions.
- Snapshot had previously drifted; this version replaces stale sections describing removed Studio Manager/Planner and assignment-linked home flows.
- Validate release entitlements/cert context (`aps-environment`) before App Store production submission builds.

## 20) Key Files to Start From
- App shell and pipeline orchestration:
  - `PracticeBuddy/App/ContentView.swift`
- Home practice flow:
  - `PracticeBuddy/Features/Home/HomeView.swift`
- Play/Journey/Duel flow:
  - `PracticeBuddy/Features/Journey/JourneyView.swift`
  - `PracticeBuddy/Features/Journey/JourneyDuelRecordingCaptureView.swift`
- Social and chat:
  - `PracticeBuddy/Features/Studio/StudioHubView.swift`
  - `PracticeBuddy/Features/Social/StudioChatViewModel.swift`
- Profile + avatar economy:
  - `PracticeBuddy/Features/Profile/UserProfileView.swift`
  - `PracticeBuddy/SharedUI/PBAvatarView.swift`
  - `PracticeBuddy/Services/JourneyProgressManager.swift`
- Settings / notification prefs:
  - `PracticeBuddy/Features/Settings/SettingsView.swift`
  - `PracticeBuddy/Features/Settings/SettingsViewSections.swift`
- Monetization and ads:
  - `PracticeBuddy/Features/Shop/ShopView.swift`
  - `PracticeBuddy/Services/PurchaseManager.swift`
  - `PracticeBuddy/Services/PBAdsManager.swift`
- Backend:
  - `functions/index.js`
  - `firestore.rules`
