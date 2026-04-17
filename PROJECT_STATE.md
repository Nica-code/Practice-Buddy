# PractiQuest — Development State Snapshot

**Last Updated**: 2026-04-16  
**Current Version**: 1.0.0  
**Active Branch**: `codex/launch-hardening`  
**Build Status**: ✅ `BUILD SUCCEEDED` (Release configuration)

---

## ✅ Recently Completed (Session: 2026-04-16)

### App Store Launch Preparation
- **Added NSUserTrackingUsageDescription** to Info.plist (required for Google AdMob IDFA)
- **Created PrivacyInfo.xcprivacy** — Apple privacy manifest declaring Firebase & AdMob data tracking
- **Verified Rights & Certificates questionnaire** answers for App Store Connect submission

### Code Polish & Optimization (from prior session)
- **HistoryView.swift**: Replaced 5× silent `try? modelContext.save()` with logged `do/catch` error handling
- **SocialView.swift**: 
  - Updated skeleton card padding from magic number `10` → `PBLayout.padSM` (12)
  - Changed pin icon color from hardcoded `.orange` → `palette.accent.opacity(0.85)` for theme consistency
- **StudioHubView.swift**: Replaced magic number paddings (8, 4) with `PBLayout.padXS` constants
- **FirebaseBuddiesRepository.swift**: Eliminated unnecessary `getDocument()` read in `sendFriendMessage` — now uses `setData(merge: true)` upsert pattern
- **WarmUpGeneratorView.swift**: Added `.lineLimit(2)` guards to step title Text elements
- **JourneyProgressManager.swift**: Replaced crash-prone `Dictionary(uniqueKeysWithValues:)` with `reduce(into:)`, added error logging to Firestore inventory sync
- **StudioChatViewModel.swift**: Fixed two `Dictionary(uniqueKeysWithValues:)` crash risks with `reduce(into:)`

---

## 🚀 Next Steps: App Store Submission

### Immediate (You Must Do)
1. **Open App Store Connect** → Your PractiQuest app
2. **Build Selection**: Select the latest green build (1.0.0)
3. **Rights & Certificates** questionnaire:
   - Encryption: **YES** (Firebase/TLS)
   - IDFA: **YES** (Google AdMob)
   - Third-party content: **NO**
4. **Review Notes** (optional but helpful):
   ```
   PractiQuest is a music practice companion with gamified warm-up 
   routines, friend duels, and global leaderboards. Users track 
   practice sessions over time. The app uses an optional in-app 
   subscription to remove ads. No special demo account needed.
   ```
5. **Click "Add for Review"** → Submit

### App Review Timeline
- **Typical**: 24–48 hours for approval/rejection
- **If rejected**: Fix issues and resubmit new build (same process)
- **If approved**: Choose release date or immediate release

### Post-Approval (v1.0.1 Planning)
- Monitor analytics and user reviews
- Plan minor updates (bug fixes, performance tweaks)
- Consider features: push notifications, analytics dashboard

---

## 📋 Known Issues & Backlog

### Current (No Blockers)
- None identified

### Future Enhancements
- [ ] Push notifications for friend requests / duel invites
- [ ] User analytics dashboard
- [ ] Performance optimization (profile with Instruments if needed)
- [ ] Localization beyond English (if expanding to other markets)

---

## 🔑 Key File Locations

```
PracticeBuddy/
├── PracticeBuddy/                    # Main app target
│   ├── Info.plist                    # Config, privacy keys ✅ UPDATED
│   ├── PrivacyInfo.xcprivacy         # Apple privacy manifest ✅ NEW
│   ├── Features/
│   │   ├── Home/
│   │   │   └── WarmUpGeneratorView.swift
│   │   ├── Studio/
│   │   │   └── StudioHubView.swift
│   │   ├── Social/
│   │   │   ├── SocialView.swift
│   │   │   └── StudioChatViewModel.swift
│   │   ├── History/
│   │   │   └── HistoryView.swift
│   │   └── [other features]
│   ├── Services/
│   │   ├── Firebase/
│   │   │   ├── FirebaseBuddiesRepository.swift
│   │   │   └── [other Firebase services]
│   │   ├── JourneyProgressManager.swift
│   │   └── [other services]
│   └── Design System/
│       ├── PBLayout.swift
│       ├── PBTheme.swift
│       └── PBTypography.swift
├── CLAUDE.md                         # Claude instructions ✅ UPDATED
└── PROJECT_STATE.md                  # This file
```

---

## 💻 Build & Deployment

### Current Build
- **Version**: 1.0.0
- **Build Number**: (latest from Xcode — check App Store Connect)
- **Configuration**: Release
- **Status**: ✅ Compiles without warnings or errors
- **Bundle ID**: `com.alexmalaimare.practicebuddy`
- **Team ID**: Apple Development team (Z8P96233CK)

### Git Status
```
Branch: codex/launch-hardening
Last commit: Polish pass: error logging, UI consistency, sendFriendMessage optimization
  (7 files changed: HistoryView, SocialView, StudioHubView, 
   FirebaseBuddiesRepository, WarmUpGeneratorView, JourneyProgressManager, 
   StudioChatViewModel)
```

---

## 🏗️ Architecture Overview

### Tech Stack
- **iOS**: SwiftUI, SwiftData (local persistence)
- **Backend**: Firebase Firestore (user accounts, social, leaderboards)
- **Auth**: Firebase Auth + Google Sign-In
- **Ads**: Google AdMob (Google Mobile Ads SDK)
- **Subscription**: App Store In-App Purchase (handled by iOS)

### Key Features
1. **Warm-up Generator**: Customizable practice routines
2. **Duel Ladder**: Real-time competitive practice sessions
3. **Leaderboard**: Global rankings
4. **Social**: Friend requests, direct messaging, challenge invites
5. **Practice Tracking**: Session history with metrics
6. **Subscription**: Ad-free experience ($X.99/month)

### Design System
- **PBTheme**: Color palette, theme support (light/dark)
- **PBLayout**: Spacing constants (`padXS`, `padSM`, `padMD`, `radiusCard`, etc.)
- **PBTypography**: Font styles (`body`, `sectionTitle`, `button`, etc.)
- **PBHaptics**: Haptic feedback system

---

## 🔗 Important URLs & IDs

```
GitHub: https://github.com/Nica-code/Practice-Buddy.git
Branch: codex/launch-hardening

App Store Connect:
  - Bundle ID: com.alexmalaimare.practicebuddy
  - App Name: PractiQuest
  - Category: Music

Firebase:
  - Project ID: practice-buddy-xyz (verify in Google Cloud Console)
  - Firestore: Enabled
  - Authentication: Email + Google Sign-In enabled

Google AdMob:
  - Publisher ID: ca-app-pub-6233840432120177~4024122715
  - Banner Unit: ca-app-pub-6233840432120177/8238699892
  - Rewarded Unit: ca-app-pub-6233840432120177/3504547263

Invites:
  - Deep Link Base URL: https://practicebuddytracker.web.app
```

---

## 💡 Design Decisions & Gotchas

### Intentional Patterns (Don't Change)
- **`ITSAppUsesNonExemptEncryption: false`** — Correct because encryption is TLS/HTTPS only (not app-level crypto APIs)
- **Green dot for "online" status** — Intentionally semantic (not `palette.accent`) to match universal "online" color
- **Orange for warnings** — Intentional semantic color, kept separate from theme accent
- **`setData(merge: true)` in Firestore** — Chosen over read-before-write for performance
- **`try?` in fire-and-forget tasks** — Intentional pattern; errors are logged separately

### Recent Crash Fixes
- **Dictionary(uniqueKeysWithValues:)** → Replaced with `reduce(into:)` in 3 places to prevent runtime crashes on duplicate keys
- **Silent error swallowing** → Added `PBLog` calls to 6 locations where errors were previously ignored

### Known Complexity Areas
- **TunerEngine** uses `Task { @MainActor in }` wrapper — NOT removable; runs on AVAudio callback thread (not main actor)
- **Large view files** (HomeView 1500+, JourneyView 2000+, HistoryView 2000+) — Do NOT decompose without testing; complex state management
- **Firebase initialization** — Uses `didInit` flags and `currentUID == uid` guards to prevent double-init; changing to `.task` is risky

---

## 📝 Session Notes

- **App Store submission** now unblocked with Info.plist + PrivacyInfo.xcprivacy fixes
- **No functional changes** in this session — only App Store compliance + minor UI polish
- **All 7 prior polish tasks** (from previous session) were completed and merged
- **Build is green** and ready for upload to App Store Connect
- **No known issues** blocking submission

---

## 🎯 For Next Session

When you start a new chat:
1. ✅ Read this PROJECT_STATE.md first
2. ✅ Refer to memory files (user profile, project overview, launch status)
3. ✅ Check if you want to submit to App Store, or if you have new feature requests
4. ✅ Ask Claude if any context is stale or needs updating

If you're **continuing development** (post-launch):
- Reference the **"Next Steps"** section above
- Check **"Known Issues & Backlog"** for what to work on next
- Refer to **"Design Decisions & Gotchas"** to avoid breaking intentional patterns
