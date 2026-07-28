# PractiQuest 2.0 — Physical-Device Release Checklist

Status: automated/archive prerequisites are complete for build 31; physical
device execution is still required.

Release source:

- commit `e6b3b354af607602a6c3b0d0eefaf944be84402b`;
- archive `/private/tmp/PractiQuest-2.0.0-31-e6b3b35.xcarchive`;
- IPA `/private/tmp/PractiQuest-2.0.0-31-e6b3b35-export/PracticeBuddy.ipa`;
- IPA SHA-256
  `fff0be53382872d71444ba02cce2835a241f6f4c7f450bdc6441c24a6e7cf5c8`.

Record device model, iOS version, build, tester, date, network condition, audio
route, and account type for every run. A release candidate fails if any P0, P1,
or P2 item remains open.

## Device matrix

- [ ] compact supported iPhone
- [ ] iPhone 17 Pro
- [ ] Pro Max
- [ ] at least one non-ProMotion device
- [ ] current iOS 26.x release
- [ ] light and dark
- [ ] standard and accessibility Dynamic Type
- [ ] Reduce Motion, Reduce Transparency, Increased Contrast
- [ ] English, Korean, Romanian

## Install and migration

- [ ] clean install creates anonymous practice-first state
- [ ] update over current App Store build preserves SwiftData sessions and notes
- [ ] XP, league, tokens, inventory, quests, avatar, friends, messages, duels,
      notifications, and purchases remain
- [ ] legacy avatar maps to loadout and empty-room composition
- [ ] generated legacy profile completes schema-v2 upgrade
- [ ] legitimate legacy name is presented for review
- [ ] offline first launch still allows private Today/Practice
- [ ] partial/corrupt migration fails safely without deleting data

## App Check

- [x] App Attest registered in Firebase Console
- [ ] DeviceCheck registered with Apple `.p8` key and Key ID
- [ ] production build obtains accepted App Attest token on physical device
- [ ] DeviceCheck fallback is exercised on a compatible fallback path
- [ ] valid V2 callable succeeds and invalid token is rejected
- [ ] Firestore/Authentication monitoring shows verified device traffic
- [ ] broader Firestore/Storage enforcement remains off until metrics are clean

## Practice lifecycle

- [ ] Quick Start begins in one tap
- [ ] planned session starts correctly
- [ ] Dock and Studio show one synchronized timer
- [ ] pause/resume/finish synchronize
- [ ] force quit offers correct recovery
- [ ] background/foreground duration remains accurate
- [ ] screen lock duration remains accurate
- [ ] phone call/Siri/audio interruption pauses or recovers correctly
- [ ] save retry preserves the result after network/persistence failure
- [ ] discard removes recovery state and temporary files
- [ ] Quest and Smart Coach attribution is correct
- [ ] eligible Moment appears only after committed save

## Audio ownership and routes

Test built-in microphone/speaker, wired headphones if available, Bluetooth
headphones, and route changes during activity.

- [ ] only one audio owner is active
- [ ] Metronome starts/stops and releases session
- [ ] Tuner listening/reference tone acquires/releases correctly
- [ ] opening an incompatible tool shows replace/cancel
- [ ] removing headphones during a tool produces a safe state
- [ ] Bluetooth route latency/fallback is understandable
- [ ] silent/haptic Rhythm is default
- [ ] audible Rhythm scoring is offered only on a compatible headphone route
- [ ] Rhythm click does not contaminate microphone scoring
- [ ] Intonation waits for listening-ready before timing
- [ ] Intonation no-signal and reference-frequency variants are correct
- [ ] Run-through requests permission before countdown/metronome/recording
- [ ] recording level/input state is accurate
- [ ] cancelled/failed/discarded recordings leave no orphan file
- [ ] saved recording can be replayed/recovered as intended

## Practice tools

For Warm-up, Smart Loop, Plan–Execute–Reflect, Run-through, Rhythm, Intonation,
Metronome, and Tuner:

- [ ] setup
- [ ] start
- [ ] pause/resume
- [ ] background/foreground
- [ ] interruption
- [ ] contextual launch from active session
- [ ] finish/result
- [ ] successful save
- [ ] failed save/retry
- [ ] discard
- [ ] force-quit recovery
- [ ] VoiceOver operation
- [ ] final controls remain above Dock

## Verification and shielding

- [ ] microphone verification is factual and stable
- [ ] verified/unverified accounting survives backgrounding
- [ ] check-ins appear and resolve correctly
- [ ] Family Controls authorization flow works
- [ ] selected shielding activates only during intended practice
- [ ] shielding releases on finish/discard/recovery
- [ ] denied/revoked Family Controls permission has clear recovery

## Live Activities and Dynamic Island

- [ ] activity starts with the session
- [ ] timer/task/verification updates
- [ ] pause/resume updates
- [ ] background and lock-screen state remains synchronized
- [ ] tapping restores exact active session/tool
- [ ] finish and discard end the activity
- [ ] stale activity is cleaned after crash/recovery
- [ ] no duplicate activities can exist

## Accounts and identity

- [ ] anonymous first practice is under 45 seconds
- [ ] anonymous → Apple link
- [ ] anonymous → Google link
- [ ] anonymous → email link
- [ ] permanent identity setup validates name/handle/date/instrument/privacy
- [ ] handle collision/cooldown/redirect behavior
- [ ] under-13 social restrictions
- [ ] teen private/approval behavior
- [ ] adult private default
- [ ] offline profile-upgrade exception
- [ ] sign out consequence and confirmation
- [ ] account deletion consequence, reauthentication, and cleanup

## Community and links

- [ ] custom `practicebuddy://practice`
- [ ] custom friend invite
- [ ] HTTPS Universal friend invite from Messages/Mail/Safari
- [ ] anonymous invite retained through account linking
- [ ] untrusted/malformed link ignored
- [ ] native friend-invite share sheet uses full URL
- [ ] Search, Connections, Messages, exact thread routes
- [ ] every relationship state/action
- [ ] accepted-friends-only messaging
- [ ] block/report/mute/remove
- [ ] Moment publish/react/expire/delete
- [ ] no private reflection or media appears in a Moment
- [ ] Public Explore remains off

## Notifications and APNs

- [ ] notification permission primer and system prompt
- [ ] production APNs token registration
- [ ] foreground notification presentation
- [ ] badge counts
- [ ] friend/follow request route
- [ ] exact chat route
- [ ] exact duel route
- [ ] exact Moment/profile route
- [ ] cold-launch and warm-launch handling
- [ ] repeated foregrounding does not duplicate path

## StoreKit and Pro

- [ ] current Pro product loads with correct price/terms
- [ ] purchase
- [ ] pending purchase
- [ ] user cancellation
- [ ] restore
- [ ] expiration/revocation
- [ ] family/account changes if applicable
- [ ] legacy Ad-Free subscriber is Pro
- [ ] stale local Pro cache cannot grant access
- [ ] trial claim requires permanent account
- [ ] trial cannot be claimed twice
- [ ] server/client product-ID spoof cannot grant access
- [ ] Pro feature locks and unlocked states refresh without relaunch

## Performance and accessibility

- [ ] cold launch measured against current App Store build
- [ ] 60/120 Hz scrolling is smooth
- [ ] avatar composite cache prevents repeated expensive work
- [ ] no continuous offscreen animation
- [ ] memory remains stable across long practice and tool switching
- [ ] feed requests/pagination remain bounded
- [ ] VoiceOver completes onboarding, practice, save, duel, request, message,
      profile edit, room placement, and Settings
- [ ] every visible control is at least 44×44 points
- [ ] no horizontal overflow or Dock obstruction
- [ ] important state is not color-only
- [ ] Reduce Motion removes continuous/depth motion

## Final sign-off

- [ ] all findings have severity and owner
- [ ] all P0/P1/P2 findings are closed and retested
- [x] exact release commit and build recorded
- [x] Firebase deployed commit recorded
- [ ] App Check metrics reviewed
- [x] final automated suite rerun: 61/61 unit and 30/30 UI
- [x] clean build-31 App Store archive/export contains no repository Markdown
      resources
- [ ] final App Store screenshots captured
- [ ] release owner approves archive from `PracticeBuddy`
