# PractiQuest 2.0 — Studio Quest

## App Store release notes

PractiQuest has been rebuilt around one simple idea: start meaningful practice faster.

- A new Today experience with one-tap Quick Start and a persistent Practice Dock.
- A focused Practice Studio with tasks, verified practice, metronome, tuner, reflection, and your complete Practice Library.
- A visual Quest path with progression, rewards, duels, leagues, and musician identity.
- A redesigned Community with Practice Moments, friends, follows, activity status, requests, and direct messages.
- A new You space for goals, insights, history, an editable musician profile, Avatar Studio, Pro, and settings.
- Empty, customizable studio rooms: your avatar is rendered separately, and decorations are placed from your collection.
- A unified premium visual system in true light and dark appearances.
- Improved accessibility, compact-device layouts, Korean and Romanian localization, and reduced-motion support.

Existing practice history, XP, rating, tokens, inventory, purchases, notification preferences, and avatar identity are preserved.

## Internal release handoff

- Marketing version: 2.0.0
- Build: 31
- Bundle identifier: `com.alexmalaimare.practicebuddy`
- UI rollback boundary: `practiquestV2UI`
- Minimum migration behavior:
  - map old tab selection into Today, Quest, Community, or You;
  - migrate legacy avatar ID into the versioned `AvatarLoadout`;
  - keep writing the compatibility avatar ID during the transition;
  - recognize both the legacy Ad-Free and new Pro subscription products;
  - preserve all SwiftData practice sessions and existing Firebase documents.
- Privacy:
  - analytics are anonymous, bounded, and content-free;
  - friend activity shares only a coarse timestamp with accepted friends;
  - no notes, messages, audio, pieces, duration, friend codes, or profile content are recorded.
- Monetization:
  - no persistent banner ads are used in the v2 shell or v2 destinations;
  - optional rewarded ads remain cosmetic-only;
  - core practice, verification, messaging, fair duels, and progression remain free;
  - existing Ad-Free subscribers are grandfathered into Pro.
- Localization:
  - `PracticeBuddy/Localizable.xcstrings` is the source of truth;
  - Korean and Romanian have no missing keys or placeholder mismatches;
  - regenerate with `scripts/generate_string_catalog.mjs` when localized copy changes.
- QA:
  - review `design-qa.md`;
  - inspect the boards under `Design/StudioQuest2/QA`;
  - rerun the foundation and Studio Quest navigation suites before every release candidate.

## Submission checklist

- Create the new Pro monthly product in App Store Connect using `com.alexmalaimare.practiquest.pro.monthly`.
- Keep `com.alexmalaimare.practicebuddy.adfree.monthly` available for legacy entitlement recognition.
- Deploy the updated Firebase `syncEntitlements` allowlist before the 2.0 rollout.
- Validate anonymous-to-Apple/Google/email upgrade on a physical device.
- Validate APNs, Live Activity, Family Controls shielding, audio session behavior, StoreKit sandbox purchasing, restore, and grandfathered entitlements in TestFlight.
- Capture final App Store screenshots from the release configuration after live backend configuration is available.
