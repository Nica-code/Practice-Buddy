# PractiQuest 2.0 — App Store Release Metadata

Status: prepared locally; not yet saved or submitted in App Store Connect.

App record:

- App: PractiQuest
- Apple ID: `6759354312`
- Version: `2.0.0`
- Build: `31`
- Bundle ID: `com.alexmalaimare.practicebuddy`
- Archive scheme: `PracticeBuddy`

## Product-page copy

### Subtitle

Practice with purpose

### Promotional text

Start meaningful practice in one tap, stay focused with verified tools, follow
real progress, and connect with musicians you trust.

### Description

PractiQuest is a focused practice studio for musicians who want their daily work
to lead somewhere.

Start quickly, follow a clear plan, use purpose-built musical tools, and review
the progress that matters. PractiQuest combines serious practice workflows with
an expressive progression system—without turning your session into a crowded
dashboard.

PRACTICE WITH FOCUS

• Start or resume from the Practice Dock anywhere in the app
• Build a session from pieces, tasks, and time goals
• Keep one synchronized timer across Practice Studio and every tool
• Use optional verification, check-ins, distraction shielding, and Live
Activities
• Finish with a private reflection and a clear next step

MUSICAL TOOLS THAT WORK TOGETHER

• Metronome and tuner
• Warm-up Generator
• Smart Loop
• Plan–Execute–Reflect
• Rhythm Accuracy
• Intonation practice
• Run-through recording
• Smart Coach practice planning

SEE REAL PROGRESS

• Daily and weekly goals
• Practice history and session details
• Verified and unverified practice totals
• Trends, achievements, quests, XP, rewards, duels, and leagues
• Export and advanced insights with PractiQuest Pro

YOUR MUSICIAN IDENTITY

Create a musician avatar, unlock collections, choose a studio room, and arrange
decorations yourself. Your social profile photo remains separate from your
in-app avatar.

PRACTICE WITH PEOPLE YOU TRUST

Connect with friends, follow approved musicians, send private messages, react to
generated Practice Moments, and challenge friends to fair practice duels.
Privacy and age-based protections are built into social access.

CORE PRACTICE STAYS FREE

PractiQuest Pro adds ongoing Smart Coach generation, unlimited saved plans and
presets, advanced insights, export, and premium avatar and studio collections.
Existing eligible Ad-Free and Pro Lifetime purchases remain recognized.

PractiQuest does not sell personal data or track you across other companies’
apps and websites.

Terms of Use: https://practiquest.app/terms
Privacy Policy: https://practiquest.app/privacy

### What’s New

PractiQuest 2.0 is a complete rebuild of the practice experience.

• Start or resume practice from the new Practice Dock
• Use a calmer, synchronized Practice Studio and rebuilt tool library
• Train with redesigned Warm-up, Smart Loop, guided practice, Run-through,
Rhythm, and Intonation tools
• Follow a new Quest journey and compete in Duels & Leagues
• Connect through profiles, friends, follows, messages, and generated Practice
Moments
• Build an avatar and arrange your own studio room
• Explore dedicated Goals, History, achievements, Pro, and Settings screens
• Enjoy true light and dark appearances, improved accessibility, and complete
Korean and Romanian localization

Existing sessions, notes, goals, XP, rating, tokens, inventory, purchases,
friends, messages, preferences, and avatar identity are preserved.

## App Review notes

PractiQuest 2.0 allows a new user to begin private practice anonymously without
creating a permanent account.

Recommended review path:

1. Complete the short instrument/goal onboarding.
2. Start practice from Today or the persistent Practice Dock.
3. Open the Practice Library from setup or an active session to test Metronome,
   Tuner, Warm-up, Smart Loop, Plan–Execute–Reflect, Rhythm, Intonation, and
   Run-through.
4. Finish and save the session to see reflection, History, quest attribution,
   and the optional generated Practice Moment offer.
5. Use the supplied review account only when testing Community, messaging,
   duels, cloud identity, and profile functionality.

Important implementation details:

- Microphone access is requested only when a tuner, pitch/rhythm analysis,
  run-through recording, or duel attempt needs it.
- Run-through recordings stay local. PractiQuest does not upload practice audio.
- Profile photos are selected through the system photo picker and uploaded only
  after the user chooses one.
- Practice Moments contain generated app artwork and preset fields only—no
  photos, audio, video, captions, comments, notes, or reflections.
- Direct messages are restricted to accepted friends.
- Users under 13 cannot access social features. Teen accounts remain private.
- Public Explore is disabled for this release.
- Family Controls is optional and used only for user-requested distraction
  shielding during practice.
- Live Activities show the active session timer/task and end on finish or
  discard.
- PractiQuest Pro uses StoreKit 2 verified current entitlements. Existing
  approved Ad-Free and Pro Lifetime products are grandfathered.
- There are no advertisements or rewarded-ad flows.
- Account deletion is available in Settings and explains its consequences
  before confirmation.

Terms of Use: https://practiquest.app/terms
Privacy Policy: https://practiquest.app/privacy
Support: https://practiquest.app/support

## App Privacy answers

The current public listing contains obsolete advertising disclosures from v1.
They must be replaced with the following v2 representation.

Tracking:

- Tracking across other companies’ apps/websites: No
- Tracking domains: None
- Third-party advertising: None
- Developer advertising/marketing data use: None

Data linked to the user and used only for App Functionality:

| App Store category | PractiQuest use |
| --- | --- |
| Name | Display name and profile identity |
| Email Address | Permanent-account authentication |
| Photos or Videos | Optional profile photo selected by the user |
| Emails or Text Messages | Accepted-friend direct messages |
| Other User Content | Bio, moderation reports, and profile/social fields |
| Gameplay Content | Quests, XP, inventory, duel and league state |
| User ID | Firebase UID and public handle |
| Device ID | APNs/FCM installation token associated with notification settings |
| Purchase History | Verified StoreKit entitlement and restoration |
| Other Data | Private date of birth/age band, privacy settings, blocks,
  relationships, coarse presence/activity, and server-owned safety state |

Data not linked to the user:

| App Store category | Purpose |
| --- | --- |
| Other Diagnostic Data | Firebase SDK reliability and app functionality |

Do not declare:

- Advertising Data
- Product Interaction for analytics
- Crash Data
- Performance Data
- Audio Data
- Calendar data
- Contacts
- Location
- Browsing History

Reasoning:

- PractiQuest’s product events are counted locally in `UserDefaults`; they are
  not uploaded to an analytics provider.
- Run-through and practice audio remain on-device.
- Firebase SDK privacy manifests may independently contribute unlinked
  diagnostic and identifier declarations to Apple’s aggregate privacy report.

## Age-rating and social-capability review

Answer the current App Store Connect questionnaire from the implemented
behavior, not the old 9+ result:

- User-generated content: Yes
- Messaging/chat: Yes, accepted friends only
- Social networking or follower relationships: Yes
- Contests/competitive activities: Duels and leagues are present
- Public user media: No
- Unrestricted web access: No
- Advertising: No
- Loot boxes/random paid items: No
- Gambling or simulated gambling: No
- Mature, sexual, violent, drug, medical, or horror content: None
- Parental/age protections: under-13 social lockout; teens private by default
- Reporting and blocking: available for profiles, Moments, and messages

Do not preserve the current 9+ rating merely for continuity. Save the rating
produced by truthful answers to Apple’s current questionnaire.

Apple added explicit social-media capability questions in July 2026. Answer
that PractiQuest has a social-media capability because users can redistribute,
amplify, and react to generated Practice Moments in a feed. Also declare that
this capability is disabled for users under 13.

## Accessibility declarations

Declare only after the physical-device checklist confirms the complete flows:

- VoiceOver
- Voice Control
- Larger Text
- Dark Interface
- Differentiate Without Color
- Sufficient Contrast
- Reduced Motion
- Reduced Transparency

Do not claim an accessibility feature solely because standard SwiftUI controls
are present; verify the acceptance flows listed in
`Docs/PHYSICAL_DEVICE_RELEASE_CHECKLIST.md`.

## Subscription configuration

Prepared product:

- Reference name: `PractiQuest Pro Monthly`
- Product ID: `com.alexmalaimare.practiquest.pro.monthly`
- Duration: one month
- Recommended United States price: USD 4.99/month

Required after product creation:

1. Rename the subscription-group reference and customer-facing English display
   name from Ad-Free to PractiQuest Pro.
2. Add customer-facing name and description localizations.
3. Configure availability and pricing.
4. Add the App Review screenshot and review notes.
5. Keep the approved Ad-Free subscription and Pro Lifetime purchase recognized
   as Pro.
6. Decide whether the legacy Ad-Free monthly product remains available to new
   customers after the new product is approved.

## Submission blockers

- The live privacy, terms, and support pages must be replaced with v2-accurate
  language described in `Docs/LEGAL_SITE_V2_UPDATE.md`.
- The prepared Pro product must be created and configured in App Store Connect.
- App Privacy answers and the current age-rating/social questionnaire must be
  published from an authorized App Store Connect account.
- Accessibility declarations must wait for the physical-device checklist.
- Firestore privacy rules must wait for the coordinated v2 migration cutover.
7. Submit the new subscription with the 2.0 app version.

## Final metadata gate

- [ ] Pro product created and configured
- [ ] Subscription group renamed/localized
- [ ] Version 2.0.0 record created
- [ ] Build 31 uploaded and processed
- [ ] Description and What’s New saved
- [ ] Privacy answers updated; all advertising disclosures removed
- [ ] Current social-media age-rating questions answered
- [ ] Accessibility claims physically verified before selection
- [ ] Custom EULA and URLs confirmed
- [ ] Review account confirmed without placing credentials in source control
- [ ] App Review notes saved
- [ ] Final deterministic screenshots uploaded
- [ ] Build and subscription added to the same review submission
