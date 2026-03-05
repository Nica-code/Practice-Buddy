PracticeBuddy — Project Snapshot (Current)

Purpose

PracticeBuddy is a SwiftUI iOS/iPadOS practice companion app focused on session tracking, reflection, social accountability (buddies), and practice tools.

Environment
- Platform: iOS + iPadOS (universal)
- Language/UI: Swift + SwiftUI
- Persistence: SwiftData (sessions/journal) + Firebase (social/auth)
- Backend: Firebase Auth + Cloud Firestore
- Build status: project builds successfully in Xcode (latest local build succeeded)

Latest Updates (2026-03-05)
- Playful font sizing now matches the visual scale of other font themes by applying a calibrated size multiplier across SwiftUI and UIKit bridge paths.
- Pro product naming updated in UI from `Practice Buddy Pro` to `PractiQuest Pro` (Shop + Settings Store).
- Home > Studio view UX refinement:
  - `Studio Manager` and `Studio Planner` are now split into two separate Teacher Tools cards.
  - Studio-related section cards were normalized to full-width card sizing for consistent alignment in:
    - Teacher Tools
    - Student Tools
    - Today’s Assignments
    - Warm-up of the Week

Current Product Areas

1) Core App Structure
- Tab-based app: Home, Play, Social, Profile, Settings
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

Localization Workflow Guardrails (New)
- Added script: `/Users/nica/Downloads/Apps/PracticeBuddy/PracticeBuddy/scripts/localization_audit.js`
- Purpose:
  - scans SwiftUI/localized string usage in code
  - compares against locale files
  - reports missing keys per locale
  - fails with non-zero exit when missing keys exist
- Command (strict):
  - `node /Users/nica/Downloads/Apps/PracticeBuddy/PracticeBuddy/scripts/localization_audit.js`
- Command (warning-only, does not fail):
  - `node /Users/nica/Downloads/Apps/PracticeBuddy/PracticeBuddy/scripts/localization_audit.js --allow-missing`
- Optional locale subset:
  - `node /Users/nica/Downloads/Apps/PracticeBuddy/PracticeBuddy/scripts/localization_audit.js --locales=ro,ko`

Recommended workflow before TestFlight upload
1. Implement feature text/labels in English first.
2. Run localization audit script.
3. Fill missing keys in `ro.lproj` and `ko.lproj`.
4. Re-run script until strict pass is clean.
5. Run app build.
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

10) Social / Studio Chat (MVP)
- Added text-only Studio Chat (Firestore-backed) with realtime updates.
- New `Studio` hub tab merges:
  - Buddies management
  - Studio Chat
- Studio Chat UI includes:
  - message stream
  - sender bubbles
  - composer with send
  - empty/loading states
- Keyboard UX improvements:
  - composer behaves like messaging apps (send dismisses keyboard)
  - tap outside composer dismisses keyboard
  - Studio Manager supports interactive keyboard dismissal while editing forms
- Firestore rules extended for studio chat messages:
  - `studios/{studioId}/messages/{messageId}`
  - read: studio members
  - create: studio members with sender UID bound to auth UID
  - update/delete: studio owner or sender

11) Journey (Levels + XP + Quests) Phase 1+2
- Added `Journey` tab as a dedicated gamification surface.
- XP rule implemented:
  - `1 minute practiced = 1 XP`
  - XP awarded only from completed/saved sessions
- Level progression implemented with quadratic scaling:
  - `xpToNext(level) = 50 + 10 * level^2`
- Session de-duplication implemented via processed session ID tracking.
- Existing users are seeded once from existing session history.
- Daily/weekly quest scaffolding implemented and live:
  - Daily: minutes, session count, reflection
  - Weekly: total minutes, active practice days
- Home includes a Journey chip (level + XP to next) for always-visible motivation.
- End-session save alert now shows earned XP for that session.

12) Recent UX + Appearance Updates
- Onboarding:
  - Google sign-in is now marked as `Coming Soon` and disabled in account setup UI.
- Appearance mode policy:
  - removed Auto/Light/Dark mode toggle from Settings -> Appearance.
  - app now runs in light mode only (`preferredColorScheme(.light)`), while theme palettes remain fully active.
- About section:
  - removed personal name block and replaced with `Contact Information`.
- Theme naming refresh (music-oriented):
  - `Classic` -> `Sonata`
  - `Mint` -> `Legato`
  - `Pink Neon` -> `Cantabile`
  - theme list is ordered alphabetically by display name:
    - Cantabile, Concert Hall, Legato, Luthier, Sonata

13) Journey Rewards MVP (Inside Journey Tab)
- Added a new in-tab Journey section switcher:
  - `Overview` (existing level + quests)
  - `Rewards` (new token/reward catalog view)
- Added quest reward claim flow:
  - completed daily/weekly quests can be claimed once per period
  - daily claims reset by day
  - weekly claims reset by ISO week
- Added token economy state in `JourneyProgressManager`:
  - persistent token balance
  - persistent claimed quest reward keys
  - persistent owned reward IDs
- Added Rewards catalog MVP:
  - claimable reward items with token costs
  - owned state tracking
  - claim actions deduct tokens and mark item as owned
- Rewards remain inside Journey (no extra top-level tab), aligned with the 5-tab navigation strategy.

14) Verified Practice (Presence Check-ins) V1
- Implemented a new accountability layer for Home session timer:
  - random in-app check-ins during active practice
  - check-in overlay with one-tap confirm (`I’m Here`) and optional focus tag chips
  - missed check-in auto-pauses session (Gentle mode behavior)
- Implemented foreground requirement:
  - if app leaves foreground while practice timer is running, session auto-pauses
- Added persisted verification data to `PracticeSessionModel`:
  - `verifiedSeconds`
  - `unverifiedSeconds`
  - `checkInCount`
  - `missedCheckInCount`
  - `checkInLogJSON`
- Home session save flow now stores verification metrics and check-in log JSON.
- History now shows verification summary for regular sessions:
  - verified duration
  - missed check-in count
  - Session Journal header also displays verification totals when available.
- Settings added `Practice Verification` control:
  - `Practice Check-ins (Gentle Mode)` toggle.
- Journey XP logic updated to use verified minutes for sessions that have verification data.
  - Legacy sessions without verification data still use total duration for XP compatibility.
- Export service updated:
  - CSV/JSON now include verification + check-in counters.

Current V1 behavior notes:
- Check-ins are in-app/foreground only (no background random prompt enforcement).
- Strict mode (end session on missed check-in) is not implemented yet.

15) Multi-Role Account Access (Student + Teacher on one account)
- Added multi-role support in `PurchaseManager`:
  - new persisted/synced `enabledRoles` set
  - existing `accountType` continues as current active mode
  - backward-compatible migration from legacy single `accountType`
- Role behavior:
  - users can enable both Student and Teacher toolsets on the same account
  - active mode can switch between enabled roles without creating a second account
  - at least one role must always remain enabled
- Master account policy:
  - master accounts now auto-enable both roles
  - default active mode remains Teacher for master accounts
- Store screen updated:
  - role toggles (`Student tools`, `Teacher tools`)
  - current mode picker when both roles are enabled
- Home gating updated to role membership (`hasRole`) for:
  - Teacher Tools section
  - Student Pro section
  - assignment-linked and warm-up student surfaces
- Studio Manager updated:
  - supports a local mode switch (Student/Teacher) when both roles are enabled
  - allows dual-role users to access both studio experiences from one account.

16) Pro Student Phase Pack (A.1 / A.2 / B.3 / B.4 / C.5)
- Phase A.1 Run-through Pro Upgrade
  - run-through now supports inline mistake markers during recording (`shift`, `rhythm`, `intonation`, `bow`, `memory`, `other`)
  - finish sheet now includes optional piece/passage name
  - markers + piece name are persisted in SwiftData (`RunThroughModel.markerJSON`, `RunThroughModel.pieceName`)
  - History run-through rows now surface piece name + marker summary
  - History includes Pro A/B compare workflow for two run-through takes (duration/rating/marker deltas)
- Phase A.2 Session Summary
  - saved session notes now append an automatic Pro summary block with:
    - total/verified/unverified time
    - check-ins/missed check-ins
    - earned XP
    - active tools used
- Phase B.3 Tempo Ladder
  - Smart Loop Timer now includes Pro tempo-ladder mode:
    - clean-loop threshold configuration
    - manual `Mark Loop Clean` flow during work phase
    - tempo increments only after required clean loops
  - loop logs persist ladder settings (`tempoLadderEnabled`, `ladderCleanLoopsRequired`)
- Phase B.4 Skill Trends
  - Journey Overview now includes trends for:
    - rhythm groove score
    - intonation score
    - loop tempo trend
  - History session rows now show earned XP per saved session
- Phase C.5 Piece Dashboard
  - Journey Overview now includes a Piece Dashboard section (student workspace MVP)
  - dashboard derives per-piece stats from existing run-through/session data (no migration required):
    - total practice minutes
    - run-through count
    - best self-rating
    - last practiced date
    - inferred latest tempo when available
  - currently keyed by run-through `pieceName` and session `noteTitle` labels

17) Romanian Localization Deep Pass (Screen-by-Screen)
- Completed a broad Romanian localization sweep across Home, History, Buddies/Studio, Journey, Settings, Store, onboarding/account flows, and Practice Lab tools.
- Added/updated localization for dynamic strings previously left in English:
  - XP/level counters (`Lv`, `XP to next`, token counts)
  - assignment/date/status rows (`Due`, `Linked assignment`, `Older assignments`)
  - check-in/verification text (`Verified`, `Unverified`, check-in summaries)
  - loop/rhythm/run-through/intonation formatted summaries
  - Store trial/purchase dynamic labels and status lines
  - runtime status/error messages from Firebase auth, tuner, recorder, rhythm engine, and Game Center submission paths
- Added shared formatting helper:
  - `PracticeBuddy/SharedUI/L10n.swift`
  - used to localize formatted text keys safely (`L10n.f(...)`) instead of hardcoded English interpolation.
- Ensured dynamic status/error strings use localized format keys where needed (especially interpolation-based messages), so Romanian now applies to runtime feedback as well.
- Build validation:

18) Launch Hardening + Notification Routing Pass
- Added centralized notification routing (`PBNotificationCenter`) for:
  - duel challenge taps
  - friend request taps
  - chat message taps
  - studio invite taps
  - goal reached taps
- Added deep-link handoff keys in app state:
  - Play can open a specific duel challenge by ID.
  - Social Chat can open a friend thread by UID and/or thread ID.
- Settings Notifications now include category toggles for:
  - duels, messages, goals, friend requests, studio invites, assignments, buddies
  - plus “Enable iOS Notifications” and “Open iOS Notification Settings”.
- Removed in-app **Launch Prep** surface from Settings (master policy remains enforced in entitlement logic).
- Firestore rules hardened for `/users/{uid}`:
  - restricted privileged fields (`entitlementTier`, `isPro`, `hasLifetimePro`, `isMasterAccount`, etc.) are no longer client-writable.
  - client now syncs only non-privileged role/tool-visibility fields.
  - iOS Simulator build succeeds after localization pass (`BUILD SUCCEEDED`).

18) Korean Localization Deep Pass (Screen-by-Screen)
- Performed a full Korean localization audit against current UI keys (static + dynamic + status/error).
- Expanded `ko.lproj/Localizable.strings` from a small baseline to broad app coverage across:
  - Home / Practice / Practice Lab
  - History / Session Journal
  - Buddies / Studio Manager / Studio Chat
  - Journey (levels, quests, rewards)
  - Settings / Store / onboarding/account flows
  - runtime status messages (auth, recorder, tuner, rhythm, leaderboard, studio/assignment flows)
- Localized formatted runtime strings used by `L10n.f(...)` keys so dynamic lines render in Korean (XP, levels, due dates, check-ins, counts, tempo summaries, etc.).
- Remaining audit “misses” are non-translatable artifacts/constants only (numeric literals/symbols and parser artifacts such as interpolation-only strings), not user-facing untranslated phrases.
- Build validation:
  - iOS Simulator build succeeds after Korean pass (`BUILD SUCCEEDED`).

19) Navigation Restructure (5-tab model) + Home-History integration
- Top-level tab model was restructured to:
  - Home
  - Play (formerly Journey/Progress destination)
  - Social (Studio hub)
  - Profile (new dedicated tab)
  - Settings
- Legacy tab index migration added so existing users are remapped safely on first launch after update.
- History is no longer a top-level tab:
  - Home now includes a `Recent History` section in `Today`
  - a `View Full History` navigation path opens full History screen from Home
- Social tab naming cleanup:
  - tab label changed from Buddies/Studio to `Social`
  - in hub, `Buddies` section renamed to `Friends`
  - Friends screen labels updated (`Studio Friends`, friend empty-state copy)
- Tab-jump remaps were updated for the new indices (Open Pro, Unlock Pro, level chip jumps).

20) UX Polish Pass (Play / Social / Profile)
- Added root context headers to reduce cognitive load and improve section clarity:
  - Play: title + dynamic subtitle by segment
  - Social: title + dynamic subtitle by Friends/Chat
  - Profile: concise explanatory line at top
- Reduced vertical scrolling density in Play and Profile:
  - Play:
    - merged header + segment picker
    - merged daily/weekly quest sections into a single `Quests` section with subheaders
    - compact section spacing applied
  - Profile:
    - merged Details + Avatar + Save into one `Personalize` section
    - compact section spacing applied
- Behavior and data model were intentionally unchanged during this pass.

21) Practice Timer / Check-in / Metronome Improvements (Student feedback pass)
- Practice timer background behavior changed:
  - removed auto-pause when app leaves foreground/phone locks
  - session timer continues while screen is off
- Accountability preserved:
  - when check-ins are enabled, background elapsed time is counted as `unverified` on return
  - this avoids inflating verified minutes while app is not foregrounded
- Check-in frequency made configurable:
  - new in-session `Check-in interval` selector:
    - 10–20 min
    - 20–35 min
    - 30–50 min (default)
  - old hardcoded 3–7 min behavior removed
- Lock-screen check-in alerts added:
  - new toggle `Lock-screen check-in alerts`
  - app schedules local notification prompts while backgrounded during active checked-in sessions
  - note: iOS does not support forced full-screen in-app check-in modal while app is backgrounded; user must open app from notification to confirm
- Metronome subdivision wording updated:
  - label changed from `Quarter` to `1/4`
- Validation after this pass:
  - localization audit passes for `ko` and `ro` with zero missing keys
  - simulator build succeeds (`BUILD SUCCEEDED`)

22) Async Duels + League Ladder (Play MVP, Phase 1)
- Added a new async competition layer in Play (`Duels & League`) with Firebase-backed state.
- Implemented `DuelLeagueManager`:
  - open duel queue/create flow (`Queue Async Scale Duel`)
  - async open-challenge match flow (join first available open challenge)
  - active duel score submission (0-100)
  - transaction-safe completion when both players submit
  - rating updates + league tier updates persisted to `users/{uid}`:
    - `duelRating`
    - `duelLeague` (`bronze` / `silver` / `gold`)
    - `duelWins`, `duelLosses`, `duelDraws`
- Play UI now shows:
  - league tier + rating + W/L/D
  - queue/cancel open duel actions
  - active duel cards with derived-score preview + submit action
  - recent duel result rows with rating delta
- Firestore rules extended for:
  - `duelChallenges/{challengeId}` read/create/update permissions for async duel lifecycle
- Phase 2A implemented:
  - friend-targeted duel invitations
  - studio-targeted duel invitations
  - incoming invite accept/decline
  - outgoing invite cancel
  - open queue option remains available
- Phase 2B implemented:
  - self-reported duel slider score removed from active duel submit flow
  - duel submit now uses app-derived metrics from latest Intonation + Rhythm takes:
    - intonation score
    - rhythm score
    - consistency score
    - note/beat counts
  - local-only adjudication path is active in iOS:
    - stores per-player attempt payload in Firestore
    - finalizes duel when both attempts are present
    - computes winner + rating deltas client-side via transaction
    - updates duel W/L/D + league tier on `users/{uid}`
- Phase 2C implemented:
  - weekly season model (`YYYY-Www`) with season points/matches/wins/rating-delta fields on users
  - Play now includes a `Season Ladder` view with scopes:
    - Global
    - Friends
    - Studio
  - ladder rows show rank + player + season points
- Matchmaking quality pass implemented:
  - open queue now prefers same league tier and closest rating before widening selection
  - open queue fallback behavior preserved

MVP scope notes:
- This is asynchronous challenge competition (not live realtime head-to-head).
- Scoring is app-derived from analysis metrics; manual self-report slider is removed.
- Matchmaking supports open queue + friend/studio invitations.

23) Account/Role Model Simplification + Tool Access
- Account type hard split was replaced by a single-account capability model.
- Added `Primary Focus` in Settings:
  - `Student`
  - `Teacher`
  - `Both`
- Added explicit tool visibility toggles in Settings:
  - `Student Tools`
  - `Teacher Tools`
- Home `Studio` section now renders based on enabled tool capabilities:
  - Teacher-only users: teacher tools only
  - Student-only users: student tools only
  - Both: teacher + student blocks
- `Studio Manager` remains Pro-gated and is now entered in explicit mode:
  - teacher entry mode
  - student entry mode

24) Shop + Shortcut Navigation Pass
- Added a reusable shortcut chip row component:
  - `PracticeBuddy/SharedUI/PBShortcutBar.swift`
- Added top shortcut rows on all root tabs:
  - Home, Play, Social, Profile, Settings
- Shortcut rows were moved out of header cards and placed above cards.
- Shop routing updated:
  - `Shop` shortcut now opens a dedicated modal Shop page (not Settings tab jump).
  - new `PracticeBuddy/Features/Shop/ShopView.swift`
  - Shop includes:
    - Pro purchase/trial/restore section
    - Cosmetics (Coming soon)
    - Expressive (Coming soon)
    - Bundles (Coming soon)
- Social shortcut behavior updated:
  - `Requests` scrolls to pending requests area
  - `Leaderboard` shortcut scrolls to leaderboard area
- Play shortcut behavior updated:
  - `Leaderboard` shortcut scrolls directly to `Season Ladder`
- Profile UX updated:
  - save actions now dismiss keyboard reliably.

25) Teacher Tools: Studio Planner (Phase 1 + Enhancements)
- Added `Studio Planner` under Home -> Studio -> Teacher Tools.
- New planner module:
  - `PracticeBuddy/Features/Friends/StudioPlannerView.swift`
  - supports event types:
    - Lesson
    - Studio Class
    - Recital
  - event create flow:
    - title, notes, location, start/end
    - roster student assignment with optional piece + duration
    - optional Apple Calendar sync (EventKit)
  - event list actions:
    - Add to Calendar
    - Edit
    - Delete
- Added planner filters:
  - type filter (`All`, `Lesson`, `Studio Class`, `Recital`)
  - date filter (`Upcoming`, `Next 7 Days`, `This Month`, `All Dates`)
- Added recurring lesson templates:
  - save template from composer
  - use template to prefill composer
  - schedule next lesson from template
  - delete template
- Firebase repository expanded for planner domain:
  - planner events read/create/update/delete
  - lesson template read/create/delete
  - external calendar event ID persistence
- Firestore rules extended:
  - `studios/{studioId}/events/{eventId}`
  - `studios/{studioId}/lessonTemplates/{templateId}`
- iOS permissions updated:
  - `NSCalendarsUsageDescription` added to `Info.plist`

26) Top Safe Area Visual Fix
- Root tab screens had a visible top-area mismatch near the Dynamic Island due to navigation bar background layering.
- Updated root screens to hide navigation bar background so app backdrop visually fills to top safe area:
  - Home, Play, Social, Profile, Settings root views.

27) Leaderboard Cost-Reduction + Ranking Model Update
- Social leaderboard ranking was switched from minutes-based to:
  - Level (desc)
  - Duel Rating (desc)
  - Name (asc)
- Social leaderboard labels and chips were aligned to use `Level` wording consistently.
- Play `Season Ladder` and Social leaderboard refresh logic now use long cache windows (24h) to minimize read volume.
- Frequent force-refresh calls were removed in UI flows so cache is respected.
- Social/Play duel leaderboard UI was simplified:
  - removed octave segment controls from these list views
  - removed manual refresh controls
  - queue/invite actions use fixed one-octave default in current UX pass.

28) Studio Manager + Teacher Navigation Adjustment
- In Home -> Studio -> Teacher Tools, tapping `Studio Manager` now routes directly to `Studio Planner`.
- In Studio Manager header, redundant `Copy Invite Link` was removed; `Share` remains as the single invite action.

29) Social Chat System Overhaul (Studio + Friend DMs)
- Replaced old studio-only chat surface with a conversation-thread model:
  - Studio chat threads (supports multi-studio users cleanly)
  - Friend 1:1 chat threads
- Added new Firestore domain for friend DMs:
  - `friendChats/{threadId}`
  - `friendChats/{threadId}/messages/{messageId}`
- Added repository support for:
  - studio latest-message listener (for thread list previews)
  - friend thread listeners
  - friend message listeners
  - friend thread bootstrap + send flow
- Social badge behavior now composes:
  - incoming friend requests + unread chat threads on bottom `Social` tab
  - chat unread count badge text in Social segmented header (`Chat (N)`).

30) Chat UX Pass (WhatsApp-style)
- Chat screen now opens as a conversation list first (instead of inbox button flow).
- Thread view opens on tap with message feed + composer.
- Added `New Chat` action (top-right pencil icon) for starting friend DMs.
- Added conversation list quality-of-life:
  - search bar
  - pinned threads
  - mute/unmute
  - mark read
  - local hide/delete thread
- Added swipe actions:
  - leading: pin/unpin, mark read
  - trailing: mute/unmute, delete local
- Thread state is persisted per signed-in user (read, pinned, muted, hidden).

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
- `PracticeBuddy/Docs/AVATAR_ASSET_SPEC.md`
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
  - script now preserves configured master account(s) by email/UID while deleting test data.
  - Auth user deletion remains a Firebase Console step (delete test users only, keep master account).
- After chat/rules changes, deploy latest Firestore rules before device testing:
  - `firebase deploy --only firestore:rules`

Where We Are Now
- App is in a significantly more complete state than the older “Day 8” snapshot.
- Firebase auth + buddies + tuner + journal UX + font palette overhaul are all implemented and compiling.
- Pro model, StoreKit foundation, and first gated features are now implemented and compiling; ready for iterative expansion.
- History now supports deletion across all Practice Lab log types shown in History (Loop Sessions, Guided Practice, Rhythm Accuracy, Run-throughs).
- Pro Student roadmap phases requested for this sprint (A.1/A.2/B.3/B.4/C.5) are implemented in-app and compile successfully.
- Avatar system Phase 1 is now expanded to character-style presets in Profile (male/female-themed instrument/persona options) with a stable shared avatar component.

What Is Next
- Expand A/B compare into waveform/timing drift visuals.
- Add richer Skill Trends charts (weekly and monthly) behind Pro.
- Finish live server push (FCM/Functions) path once Blaze is enabled, then remove local notification fallback.
- Avatar customization roadmap:
  - Phase 2: layered avatar builder (base, hair, outfit, accessory, instrument)
  - Phase 3: unlock economy hooks (free, token unlocks, Pro-only, Shop bundles)
  - Phase 4: seasonal cosmetics + limited drops
- Duel roadmap:
  - dedicated duel recording UI (record/done flow from duel entry sheet)
  - push notification events for invite/accepted/ready states
  - stronger anti-abuse and adjudication refinements

31) Duel League Expansion + Requirement Enforcement
- League tiers expanded from 3 to 8:
  - Bronze, Silver, Gold, Platinum, Emerald, Diamond, Master, Grandmaster
- Difficulty requirements now scale by league:
  - Bronze: 1 octave
  - Silver: 2 octaves
  - Gold: 3 octaves
  - Platinum: 3 octaves + 88+ BPM
  - Emerald: 3 octaves + 104+ BPM
  - Diamond: 3 octaves + 116+ BPM
  - Master: 3 octaves + 126+ BPM
  - Grandmaster: 3 octaves + 136+ BPM
- iOS UI now displays active league requirement in Play -> Duels & League.
- Queue/Invite requests now use league requirement defaults instead of fixed one-octave.
- Backend (`functions/index.js`) now enforces:
  - required octaves and tempo floor on active duels
  - stricter capture quality thresholds at higher leagues
  - expanded `duelLeagueForRating` mapping for all new leagues

32) Duel Recorder/Submission Refinements
- Dedicated duel submission payload now includes `tempoBPM`.
- Duel capture strictness now aligns to challenge league, not only local rating.
- Recorder rhythm BPM control now respects required minimum tempo when present.
- Submission validation rejects under-tempo takes for tempo-gated leagues.

33) Play Quests Overhaul (Duel-First + Weekly Rotation)
- Replaced fixed basic quest list with duel-focused quest engine.
- Added event telemetry for duel quest progress:
  - queue joined
  - invite sent
  - accept entered
  - take submitted
  - high-score submission (80+)
  - tempo-qualified submission
- New daily quests are duel-centric (token rewards in 4-10 range).
- Weekly quests now rotate from a duel-focused pool (4 active/week), deterministic by week key and seed.
- Weekly rotation includes diversity-aware category selection and persisted weekly plan.
- Added duel baselines (daily/weekly) for win/rating/league-climb deltas.
- Play now syncs duel snapshot stats into quest manager for real-time quest progress updates.

34) Rewards + Inventory Phase A (Functional Unlocks)
- Reward model upgraded from simple owned flags to:
  - category (`Cosmetics`, `Tools`)
  - slot-based equip model
  - equipped state persistence
- Added Inventory screen:
  - `PracticeBuddy/Features/Journey/InventoryView.swift`
  - category segmented view, Equip/Unequip actions, owned-item browsing
- Added real functional reward items:
  - Studio Frame (profile frame slot)
  - Concert Banner (profile banner slot)
  - Soft Profile Glow (profile glow slot)
  - Classic Confetti / Spark Confetti (confetti style slot)
  - Metronome Pack: Studio (tool slot)
- Profile visuals now react to equipped cosmetics (frame/banner/glow) on top profile card.
- Reward claim/quest claim celebrations now render style-aware confetti overlay.
- Metronome pack now applies audio-style override across practice tools using metronome start paths.

35) Build/Verification
- Latest iOS compile pass: `BUILD SUCCEEDED` after quest/inventory/reward integration.

36) Component Refactor Pass (Maintainability)
- Extracted large view/component chunks into dedicated files across Home, Journey, History, Practice, Profile, Social, Friends, and Studio.
- Added reusable component files such as:
  - `HomeViewComponents.swift`, `HomeViewSubcomponents.swift`
  - `JourneyViewComponents.swift`, `JourneyDuelRecordingCaptureView.swift`
  - `HistoryViewComponents.swift`, `PracticeViewComponents.swift`
  - `ProfileComponents.swift`, `SocialViewComponents.swift`, `FriendsViewComponents.swift`, `StudioHubComponents.swift`
- Updated call sites to consume shared components and removed duplicated local helper views.
- Purpose: improve readability, reduce merge risk, and make future UI iteration faster without changing product behavior.

37) Firestore Write Hardening (Race/Mismatch Guard)
- Added auth UID guardrails before profile writes in:
  - `FirebasePresenceManager`
  - `PurchaseManager`
- Writes to `users/{uid}` are now skipped when runtime auth UID does not match expected UID.
- Added structured warning logs for UID mismatch cases to simplify diagnosis.
- Result: previously observed intermittent `Missing or insufficient permissions` profile-write bursts were eliminated in latest device validation.

38) Server-Authoritative Entitlement/Trial Sync
- Added Cloud Function endpoint: `syncEntitlements` (Node 22, 2nd gen).
- iOS `PurchaseManager` now performs server sync of active subscription product IDs and optional trial request.
- Backend now authoritatively writes/returns entitlement fields:
  - `subscriptionActive`, `subscriptionProductIDs`
  - `entitlementTier`, `isPro`, `proSince`
  - `trialUsed`, `trialStartedAt`, `trialEndsAt`
- Sensitive entitlement fields remain protected by Firestore rules (client cannot self-escalate access).
- Local fallback behavior remains for resilience when function sync is temporarily unavailable.

39) Cloud Push Notification Path (Production Wiring)
- Added Firebase Messaging integration in app target and app delegate flow.
- Implemented full token capture/storage:
  - APNs token registration
  - FCM registration token
  - token persistence under `users/{uid}/devices/{tokenHash}` with `tokenType`.
- Added Cloud Functions:
  - `onFriendInviteCreated`
  - `onFriendChatMessageCreated`
  - `pushTestNotification`
- Server push sender now filters non-FCM/APNs-only token entries and sends only valid FCM targets.
- Chat push payload copy is generic/privacy-preserving (no message body exposure).
- Settings includes in-app “Send Test Push” trigger for device validation.
- Device verification status (latest test):
  - `APNs registration succeeded`
  - APNs token stored
  - FCM token stored

40) iOS Capability/Runtime Notes (Current)
- Push is now working with:
  - Push Notifications capability
  - Background Modes -> `remote-notification`
- Background Modes extras (fetch/processing/location) are intentionally not enabled to avoid unnecessary power/review overhead.
- App remains portrait-primary in current UX policy.

41) Branding Name Update (Launch Identity)
- User-facing app branding has been renamed to `PractiQuest`:
  - iOS Home Screen display name (`CFBundleDisplayName`) updated to `PractiQuest`
  - App Store Connect app name updated to `PractiQuest`
- Internal technical identity is intentionally unchanged for continuity:
  - Xcode project name remains `PracticeBuddy`
  - repository/workspace naming remains `PracticeBuddy`
  - bundle identifier remains `com.alexmalaimare.practicebuddy`
- This preserves update continuity, backend bindings, and existing app listing identity while applying new public branding.

41) Buddy Invite Deep-Link Loop (Viral Growth Slice)
- Added a one-tap invite entry point in Social -> Friends -> Account:
  - `Invite` action now sits next to `Copy` for friend code sharing.
- Invite share payload now includes:
  - sender friend code
  - custom-scheme deep link: `practicebuddy://add-buddy?code=...`
- Added app deep-link handling for buddy invites:
  - `ContentView` now parses `add-buddy` links
  - signed-in users auto-send a pending friend invite through existing `FirebaseBuddiesRepository` flow
  - success state routes user to Social -> Friends pending area with confirmation alert
  - existing sign-in-required and error alert patterns are reused
- Added lightweight growth metrics (local counters + logs):
  - `buddy_invite_share_clicked`
  - `buddy_invite_auto_sent`
- Validation:
  - latest iOS Simulator compile pass after this feature: `BUILD SUCCEEDED`
