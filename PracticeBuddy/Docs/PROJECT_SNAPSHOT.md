PracticeBuddy — Project Snapshot (Current)

Purpose

PracticeBuddy is a SwiftUI iOS/iPadOS practice companion app focused on session tracking, reflection, social accountability (buddies), and practice tools.

Environment
- Platform: iOS + iPadOS (universal)
- Language/UI: Swift + SwiftUI
- Persistence: SwiftData (sessions/journal) + Firebase (social/auth)
- Backend: Firebase Auth + Cloud Firestore
- Build status: project builds successfully in Xcode (latest local build succeeded)

Current Product Areas

1) Core App Structure
- Tab-based app: Home, History, Buddies, Settings
- NavigationStack per tab
- Shared theme and typography systems via environment

2) Firebase + Auth
- Firebase integrated and initialized in app lifecycle
- Apple Sign In enabled and working with Firebase Auth
- Session persists across relaunches (user remains signed in)
- Anonymous bootstrap path used during initial setup flow where needed
- First-launch account setup gate added:
  - user must complete Apple sign-in
  - user must choose account type (`Student` or `Teacher`) before entering app tabs

3) Buddies (Your Studio)
- Friend-code based buddy system implemented in Firestore
- User profile document creation with generated friend code
- Invite flow:
  - Send invite by code
  - Receive pending invites
  - Accept/decline invites
- Friendship materialization writes both-direction buddy records
- Permissions/rules adjusted and validated so accept flow succeeds
- “Studio buddies” behavior simplified so buddy actions map into top-level studio usage

4) Home + Practice
- Practice session flow active
- End-session note/journal experience improved
- Discard session confirmation added to prevent accidental data loss
- “Share” moved out of Buddies context and aligned with Home/practice context

5) Practice Tools
- Metronome implemented in Home practice tools
- Metronome background continuity enabled:
  - metronome no longer auto-stops when Home view disappears
  - with Background Modes (`Audio, AirPlay, and Picture in Picture`) enabled, playback can continue through lock/background
- Tuner v1 implemented:
  - Reference pitch options include 440 Hz / 442 Hz / 415 Hz (baroque)
  - Microphone input + pitch detection pipeline
  - Needle-style UI feedback for tuning accuracy
- iOS 17 deprecation handled in recorder permission path

6) Typography / Appearance
- Font system overhauled from similar system styles to distinct palettes
- 4 Google-font palettes now wired:
  - Elegant
  - Minimalistic
  - Modern
  - Playful
- Runtime bundled font registration added
- Robust font-name resolution added (including PostScript-name lookup from bundled files)
- Fallback behavior preserved if a font is missing
- Palettes now visibly switch in-app and persist via AppStorage
- Theme propagation fixes completed:
  - Settings appearance/store row icons now follow active theme palette
  - Tab bar icon/text colors now refresh on theme switch and follow theme accent (selected + unselected variants)

7) Monetization Foundation (Pro Model)
- Strategy agreed:
  - One-time unlock: `Practice Buddy Pro`
  - Account type layer: `Teacher` or `Student`
  - Pro is split into:
    - Pro Core (everyone)
    - Teacher extras
    - Student extras
- Step 1 implemented:
  - Added Pro/account-type state manager (`PurchaseManager`) with local persistence
  - Added Firebase user profile mirror fields:
    - `isPro`
    - `accountType`
    - `proSince` (set when Pro is enabled)
    - `accountTypeSet`
    - `accountTypeChangeUsed`
  - Wired manager to authenticated Firebase user lifecycle
  - Replaced Store placeholder with a real Pro screen:
    - status
    - account-type selector
    - feature buckets
    - unlock/restore actions
  - Step 2 implemented:
  - StoreKit 2 purchase foundation wired:
    - product loading
    - purchase flow
    - restore (`AppStore.sync`)
    - entitlement refresh (`Transaction.currentEntitlements`)
    - transaction updates listener (`Transaction.updates`)
  - First Pro feature gating now active:
    - History export (CSV/JSON) gated behind Pro
    - History analytics section (total/average/longest) gated behind Pro
    - Home session templates section gated behind Pro
  - Free users get inline unlock CTAs that route to Settings -> Pro screen
  - Account type change policy enforced:
    - role is chosen during setup
    - one role change allowed later from Settings
  - Studio MVP (teacher side) step 1+2 implemented:
    - create studio (name + invite code)
    - teacher roster list (members)
    - teacher access via Pro -> Teacher Tools -> Studio Manager
  - Student studio join implemented:
    - join studio by invite code
    - read joined studio card + roster
    - access via Pro -> Student Tools -> Join Studio
  - Assignments v1 implemented:
    - teacher can create assignments as:
      - whole studio assignment
      - individual assignment (targeted per student)
    - teacher can edit/delete assignments and filter by target type
    - student sees assignment checklist and marks completion
    - student assignment list includes due status highlighting (Due Today / Overdue)
    - teacher sees per-assignment completion counts
    - student gets local app notifications for newly posted relevant assignments (free-tier fallback)
  - Push notifications foundation implemented:
    - Firebase Messaging integrated in iOS app
    - APNs registration and FCM token capture wired in app delegate
    - per-user device token storage at `users/{uid}/devices/{tokenHash}`
    - notification preference flags mirrored to Firestore:
      - `notificationAssignments`
      - `notificationBuddies`
    - Cloud Function scaffold added for assignment-created push fanout
    - Firebase Functions deployment is optional and deferred until Blaze plan is enabled

8) Optimization / Cleanup Pass
- Full source review pass completed across app modules (UI, Firebase, StoreKit, audio/tools, settings).
- Safe optimization applied:
  - deduplicated initial notification-preference sync writes in Settings
    (`SettingsView` now performs one initial sync + explicit sync on toggle changes)
- No high-risk refactors were applied in this pass to preserve current UI/functionality stability.

Included Local Font Files
- PlayfairDisplay-Regular.ttf
- Lora-Regular.ttf
- IBMPlexMono-Regular.ttf
- Manrope-Regular.ttf
- RobotoMono-Regular.ttf
- SpaceGrotesk-Regular.ttf
- Outfit-Regular.ttf
- SpaceMono-Regular.ttf
- Fredoka-Regular.ttf
- Quicksand-Regular.ttf
- NunitoSans-VariableFont_YTLC,opsz,wdth,wght.ttf

Supporting Docs
- `PracticeBuddy/Docs/FIRESTORE_RULES_BUDDIES.md`
- `PracticeBuddy/Docs/GOOGLE_FONTS_PALETTES.md`
- `firebase/functions/README.md`

Known Notes
- TestFlight upload may show non-blocking symbol warnings for some Firebase dependency frameworks (`grpc`, `absl`, etc.); build upload still works.
- Clearing DerivedData can require re-resolving Swift packages before build.
- StoreKit 2 is now wired in-app, but requires App Store Connect product setup and sandbox test accounts for full end-to-end validation.
- Cloud Functions/APNs server push for assignments is scaffolded in repo but requires Blaze before deploy; app currently uses free-tier local assignment notification fallback.

Where We Are Now
- App is in a significantly more complete state than the older “Day 8” snapshot.
- Firebase auth + buddies + tuner + journal UX + font palette overhaul are all implemented and compiling.
- Pro model, StoreKit foundation, and first gated features are now implemented and compiling; ready for iterative expansion.
