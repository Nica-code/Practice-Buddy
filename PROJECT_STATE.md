# PractiQuest — Development State Snapshot

**Last Updated**: 2026-05-22
**Current App Version**: 1.0.2 (next archive should bump to 1.0.3)
**Current Build Number**: 27 (next archive should bump to 28+)
**Active Branch**: `codex/launch-hardening`
**Build Status**: `BUILD SUCCEEDED` via simulator build check

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
