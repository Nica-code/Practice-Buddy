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
- Google sign-in path added via Firebase OAuth provider flow (`google.com`) in onboarding
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

5.1) Practice Lab (MVP in Progress)
- New Home subsection: `Practice Lab` with tool entry points.
- Feature 1 complete: Smart Loop Timer
  - loop/rest cycles, target loops or until-stop, optional metronome integration, auto tempo progression
  - focus tags
  - SwiftData loop log persistence (`LoopPracticeLogModel`)
  - Pro gating for presets save/load
  - History integration including Pro tempo trend row
- Feature 2 complete: Plan -> Execute -> Reflect
  - guided plan goals + structure + target duration
  - execute block timer with tool launch shortcuts
  - reflection prompts + rating
  - SwiftData plan log persistence (`PracticePlanLogModel`)
  - Teacher Pro studio plan templates push/read in Firestore (`studios/{studioId}/planTemplates`)
  - History integration for guided logs
- Feature 3 complete: Pulse + Rhythm Accuracy
  - mic onset detection pipeline with live early/late indicator
  - free summary: average offset + groove score
  - Pro detailed window stats
  - SwiftData rhythm take persistence (`RhythmAccuracyTakeModel`)
  - History integration for rhythm takes
  - History deletion supported
- Feature 4 complete: Run-through Mode
  - one-take audio recording, optional no-pause mode, optional metronome click
  - end-of-take self rating + notes
  - SwiftData persistence with audio path (`RunThroughModel`)
  - free vs Pro history behavior in History (free shows latest 3, Pro unlimited list in-app)
  - History deletion supported (also removes local audio file)
- Feature 1 + Feature 2 history controls
  - Loop Sessions history deletion supported
  - Guided Practice history deletion supported
- Feature 5 complete: Assignment-aware practice linking
  - Home “Today’s Assignments” checklist for students
  - linked assignment context for starting Practice Lab tools
  - linked result submit from loop/plan/rhythm/run-through save flows
  - offline-safe submission queue + retry sync (`AssignmentLinkManager`)
  - submission payload supports optional practice note / attachment path / linked tool metadata
- Feature 6 complete: Warm-up Generator
  - generate timed warm-up routines by time/instrument/focus
  - run step-by-step timer and save outcome to session history
  - Teacher Pro can push “Warm-up of the Week” to studio (`studios/{studioId}/warmups/warmup_of_week`)
  - students can see warm-up of the week from Home and load it into generator

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
  - App-managed Pro trial implemented:
    - user-triggered one-time 7-day free trial (not auto-started)
    - effective Pro entitlement = lifetime purchase OR active trial
    - trial status/countdown and trial-ended messaging in Store screen
    - mirrored profile fields include:
      - `hasLifetimePro`
      - `trialUsed`
      - `trialStartedAt`
      - `trialEndsAt`
  - Launch entitlement policy implemented:
    - default launch users are no longer globally auto-unlocked
    - all-access is now granted only via explicit whitelist/admin assignment
    - master account policy supported:
      - detected by configured master email list (default includes `nicaviolin@icloud.com`)
      - optional strongest path: set explicit master UID in `PBMasterUIDs`
      - master account can switch freely between Student and Teacher in Settings
    - entitlement/profile fields mirrored to Firestore:
      - `entitlementTier`
      - `canSwitchRoleFreely`
      - `isMasterAccount`

8) Optimization / Cleanup Pass
- Full source review pass completed across app modules (UI, Firebase, StoreKit, audio/tools, settings).
- Safe optimization applied:
  - deduplicated initial notification-preference sync writes in Settings
    (`SettingsView` now performs one initial sync + explicit sync on toggle changes)
- Launch-path optimization applied:
  - bundled font registration now targets known font files directly instead of full bundle scan
- Runtime/log warning cleanup applied:
  - moved Firebase configure call into app delegate launch path to avoid startup initialization warning
  - removed custom-font `.weight(...)` chaining to avoid repeated SwiftUI font descriptor warnings
  - linked `AppIntents.framework` to suppress appintents metadata warning
- Firebase quota-safe pass applied:
  - non-critical realtime listeners are now paused when app leaves active state and resumed on foreground
  - implemented for:
    - `AssignmentLinkManager` (student assignment listeners)
    - `WarmupOfWeekManager` (studio warmup listeners)
  - this reduces background Firestore read churn on Spark while preserving foreground behavior
- No high-risk refactors were applied in this pass to preserve current UI/functionality stability.

9) Studio + Invite Flow (Teacher/Student)
- Home IA updated for teachers:
  - `Teacher Tools` section moved to Home (between Session Templates and Practice Tools)
  - Settings -> Pro -> Teacher Tools now redirects back to Home for studio workflow
- Studio creation permission fix:
  - Firestore rules updated to support owner+member creation in same batch using `getAfter(...)`
- Invite UX updated:
  - Studio Manager exposes `Copy Invite Link` and `Share` actions (full URL not displayed)
  - invite links now use HTTPS format:
    - `https://practicebuddytracker.web.app/join-studio?code=...`
  - app still supports custom scheme fallback:
    - `practicebuddy://join-studio?code=...`
- Deep-link join behavior:
  - app handles incoming invite links and auto-attempts studio join for signed-in users
  - shows clear success/failure/sign-in-required alert states
- Firebase Hosting prepared for Universal Links:
  - `hosting/apple-app-site-association`
  - `hosting/.well-known/apple-app-site-association`
  - `hosting/join-studio/index.html` fallback landing page
  - `firebase.json` updated with hosting config + AASA headers

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
- `PracticeBuddy/Docs/LAUNCH_RESET.md`
- `firebase/functions/README.md`
- `hosting/apple-app-site-association`
- `hosting/.well-known/apple-app-site-association`
- `scripts/all_access_whitelist.json`
- `functions/scripts/grant_all_access_from_whitelist.js`
- `functions/scripts/revoke_all_access_from_whitelist.js`

Known Notes
- TestFlight upload may show non-blocking symbol warnings for some Firebase dependency frameworks (`grpc`, `absl`, etc.); build upload still works.
- Clearing DerivedData can require re-resolving Swift packages before build.
- StoreKit 2 is now wired in-app, but requires App Store Connect product setup and sandbox test accounts for full end-to-end validation.
- Cloud Functions/APNs server push for assignments is scaffolded in repo but requires Blaze before deploy; app currently uses free-tier local assignment notification fallback.
- Firestore rules now also include:
  - `studios/{studioId}/planTemplates/{templateId}`
  - `studios/{studioId}/warmups/{warmupId}`
  - studio member create path compatibility for batch create (`getAfter` owner check)
- Universal Links require Associated Domains capability + deployed AASA files on hosted domain.
- Launch reset tooling added:
  - Firestore reset script: `scripts/firestore_launch_reset.sh`
  - Auth user deletion remains a Firebase Console step.

Where We Are Now
- App is in a significantly more complete state than the older “Day 8” snapshot.
- Firebase auth + buddies + tuner + journal UX + font palette overhaul are all implemented and compiling.
- Pro model, StoreKit foundation, and first gated features are now implemented and compiling; ready for iterative expansion.
- History now supports deletion across all Practice Lab log types shown in History (Loop Sessions, Guided Practice, Rhythm Accuracy, Run-throughs).

What Is Next
- Add optional delete confirmation UI for History rows to reduce accidental removals.
- Expand Pro analytics visualizations for Loop/Rhythm trends in History.
- Finish live server push (FCM/Functions) path once Blaze is enabled, then remove local notification fallback.
