# PractiQuest — Development State Snapshot

**Last Updated**: 2026-05-30
**Current App Version**: 1.0.5 (build 30) — pending App Store upload
**Active Branch**: `codex/launch-hardening` (all commits pushed to GitHub)
**Build Status**: `BUILD SUCCEEDED` via simulator build check

**Before uploading 1.0.5:** (1) upload `.p8` APNs key to Firebase (Key ID `854Y5FY5F6`, Team `73J84HKXBC`); (2) `firebase deploy --only functions`; (3) create version 1.0.5 in App Store Connect.

---

## 2026-05-30 — APNs Key + UX Polish Pass

### Push notifications — root cause resolved
- **APNs Authentication Key (.p8) was the missing piece.** Nica created key `854Y5FY5F6` (Team `73J84HKXBC`, Production/Team-scoped) and is uploading it to Firebase Console → Cloud Messaging → Apple app config. With this + the `aps-environment=production` fix, the production push pipeline is complete.
- Key file lives only in `~/Downloads` (never in repo). Added `*.p8` / `AuthKey_*.p8` to `.gitignore` as a safety net.
- Committed the previously-uncommitted FCM token-ordering fix (set `Messaging.apnsToken` before fetching FCM token — required because `FirebaseAppDelegateProxyEnabled=false`). Commit `cd8e90c`.
- **Caveat:** the key is Production-scoped, so Debug-from-Xcode (sandbox APNs) test pushes may not deliver. Test via TestFlight/live build. The `#if DEBUG` "Send Test Push" button stays debug-only (Nica's choice).

### UX polish pass (commit `b570ede`)
- **Notification permission priming:** new `PBNotificationPrimerView` (soft pre-prompt) shown before the one-shot OS dialog when status is `.notDetermined`, wired through `ContentView.syncPushPipeline()` + `handleNotificationPrimerEnable/Skip`. Preserves the OS prompt and lifts opt-in.
- **Skeletons:** replaced genuine content-loading spinners with `PBSkeletonCard` in `ProfileTabView` and `UserProfileView`. NOTE: the other ~8 `ProgressView()` instances are correct inline action spinners (Submitting/Updating/Uploading) and were intentionally left.
- **Empty states:** new reusable `PBEmptyState` (icon + title + message + optional CTA), applied to the empty buddy list (`FriendsView`) and new-chat friend picker (`SocialView`). SocialView's main thread-list empty state was already polished.
- **Ad banner seams:** `PBAdBannerSlot` now has a shared top hairline + matched background so all 6 banners read as chrome.
- **Paywall copy:** History export + advanced-analytics messages now name the Pro gate clearly instead of "currently unavailable".
- **Token alignment:** exact-match cornerRadius/padding literals (18→radiusControl, 12→padSM, 24→padXL) mapped to `PBLayout` in Settings theme/font pickers. Non-token micro-spacing left untouched to avoid visual drift.
- Build: `BUILD SUCCEEDED`. New SharedUI files auto-compile via Xcode synchronized file groups (no pbxproj edit needed).

### Still uncommitted in the tree (NOT mine — pre-existing work from another session)
`PracticeBuddy.xcodeproj/project.pbxproj`, `Features/Journey/JourneyView.swift`, `Features/Studio/StudioHubView.swift`, `Services/JourneyProgressManager.swift`, `functions/index.js`. Review before archiving 1.0.3.

---

## 2026-05-22 — Notifications + Ads Hardening

### Push Notification Fix (root cause of "no notifications on live App Store build")
- **`aps-environment` flipped from `development` → `production`** in `PracticeBuddy/PracticeBuddy.entitlements`. The live App Store build was registering device tokens against the APNs sandbox while FCM was sending through the production gateway, causing every push to be silently dropped.
- Verified all backend push triggers are deployed in Firebase project `practicebuddytracker` (us-central1, nodejs22):
  - `onFriendInviteCreated` — friend request pushes
  - `onFriendChatMessageCreated` — DM pushes
  - `onStudioChatMessageCreated` — studio/group chat pushes
  - `duelInvite`, `duelRespond`, `duelQueueJoin`, `duelQueueCancel`, `duelSubmitAttempt`, `duelSettleSweep`
  - `pushTestNotification` — test endpoint
- Existing on-device pipeline already correct: APNs registration + FCM token sync in `PracticeBuddyApp.swift`, permission prompt in `ContentView.syncPushPipeline()`, route handling in `PBNotificationCenter.swift`.

### Post-update behavior to expect
- Users updating from the current live build will have stale sandbox APNs tokens in Firestore. The first push attempt per user will fail and the token will be auto-pruned by `pruneInvalidDeviceTokens` in `functions/index.js`. The app will register a fresh production token on first launch of the new build. From the second send onward, notifications flow normally.
- Users who don't update will continue to receive nothing (unchanged from before).

### Ad Placements Added
Banner ads now appear on three additional surfaces (all reuse the existing `playBottomBanner` placement → production banner unit `ca-app-pub-6233840432120177/8238699892`):
- **Practice tab** (Home) — `Features/Home/HomeView.swift`
- **Profile tab** — `Features/Profile/ProfileTabView.swift`
- **History screen** — `Features/History/HistoryView.swift`

Pattern used: `.safeAreaInset(edge: .bottom, spacing: 0) { PBAdBannerSlot(placement: .playBottomBanner) }`. Existing banners on Play (Journey), Social, and Friends are unchanged.

### Submission plan
Nica is uploading directly to the App Store as a `1.0.3` update (skipping isolated TestFlight verification) because the entitlement fix only takes effect once a production-signed build is live. Verification will happen post-release on real user devices.

### Known gaps NOT addressed this session (defer until needed)
- No `SKAdNetworkItems` in `Info.plist` — reduces ad fill rate / revenue but doesn't block display.
- No `NSUserTrackingUsageDescription` + ATT prompt — limits personalized ads, doesn't block display.
- No Google UMP consent flow — required for EEA/UK ad serving. Consider before international expansion.

---

## Current Product State

PractiQuest is live on the App Store and continuing through rapid post-launch updates. The public app name is `PractiQuest`; the internal Xcode project, bundle identifier, URL scheme, and repository still retain the original `PracticeBuddy` naming for continuity.

Current top tabs:
- Practice
- Play
- Social
- Profile
- Settings

---

## Latest Completed Work

### Massive Update Part 1
- Renamed the old Home tab to `Practice` and updated the tab identity.
- Added a Live Activity extension for active practice/session progress.
- Hardened notification routing and in-app notification badge behavior.
- Added custom profile photo upload/removal with Firebase Storage-backed profile images.
- Refined profile photo UX with a camera-button popover near the avatar and helper text.
- Fixed friend display-name handling so friends no longer incorrectly show as the current user.
- Added a redesigned Season Ladder with avatar-based player cards.
- Expanded the Liquid Glass design refresh across shared cards, backgrounds, shortcut chips, and tab chrome.

### Latest Release-Prep Patch
- Bumped app + Live Activity extension marketing version from `1.0.1` to `1.0.2` because App Store Connect closed the `1.0.1` pre-release train after approval.
- Kept build number at `27` for the new `1.0.2` train.
- Removed Season Ladder mini-stat text under player names (`Pts`, `W`, `M`) so rows now show avatar + aligned username + rating/action only.

### Memory Safety Cleanup
- Added defensive `deinit` cleanup for Firestore listeners and Combine subscriptions in:
  - `FriendRequestBadgeManager`
  - `JourneyProgressManager`
  - `DuelLeagueManager`
- This was intentionally narrow and additive. Existing explicit `stop()` / `pauseRealtime()` lifecycle paths remain the primary cleanup mechanism during normal app use.

---

## Current Build / App Store Notes

- Archive the main `PracticeBuddy` scheme; the Live Activity extension is embedded automatically.
- App Store Connect should use/create version `1.0.2` for the next upload.
- If App Store Connect rejects build number `27` under `1.0.2`, increment build to `28` and archive again.
- Third-party framework dSYM upload warnings for Firebase/Google frameworks are not the current blocker; they affect crash symbolication quality for those frameworks, not app binary validity.

---

## Important Systems

### Practice
- Practice Timer
- Verified Mode / Family Controls shielding
- Practice Session Builder with task progress
- Practice Tools: Metronome and Tuner
- Live Activity support for active practice/session state

### Play / Duels
- Level, XP, quests, rewards, duel league, queue, invites, active duel entry, match history, season ladder.
- Season Ladder now uses cleaner player rows without extra mini-stat clutter.

### Social / Chat
- Friends, requests, direct chat, unread state, notification routing, badge contribution.

### Profile
- Token-gated avatar/icon unlocks remain as fallback.
- Uploaded profile photo overrides avatar globally where supported.

### Monetization
- Ad-supported free app.
- Ad-Free monthly subscription product id: `com.alexmalaimare.practicebuddy.adfree.monthly`.
- Google Mobile Ads configured for banner/rewarded placements.

---

## Key Files

- `PracticeBuddy/App/ContentView.swift`
- `PracticeBuddy/Features/Home/HomeView.swift`
- `PracticeBuddy/Features/Journey/JourneyView.swift`
- `PracticeBuddy/Features/Profile/UserProfileView.swift`
- `PracticeBuddy/Features/Studio/StudioHubView.swift`
- `PracticeBuddy/Features/Social/StudioChatViewModel.swift`
- `PracticeBuddy/Services/PracticeLiveActivityManager.swift`
- `PracticeBuddyLiveActivity/PracticeTimerLiveActivityWidget.swift`
- `PracticeBuddy/Services/PBAdsManager.swift`
- `PracticeBuddy/Services/PurchaseManager.swift`
- `functions/index.js`
- `firestore.rules`

---

## Known Follow-Up Items

- Continue real-device verification for push banners, badges, sounds, and tap routing across foreground/background/terminated states.
- Consider cleanup of legacy Firestore rules paths only after confirming no deployed clients/functions still rely on them.
- If dSYM warnings become operationally important, investigate Firebase/Google SDK symbol upload workflow separately.
- Do not blindly apply the remaining optimization-audit ideas; Firestore query-level sorting should be verified against existing documents before replacing in-memory sorts.
