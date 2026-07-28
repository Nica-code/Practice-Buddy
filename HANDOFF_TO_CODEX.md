# PractiQuest 2.0 — Codex/Claude Handoff

Read first:

1. `PROJECT_STATE.md`
2. this file
3. `Docs/FIREBASE_DEPLOYMENT_RUNBOOK.md` before any Firebase action
4. `Docs/PHYSICAL_DEVICE_RELEASE_CHECKLIST.md` before calling the client ready

Branch: `codex/launch-hardening`
Version: 2.0.0 (build 31)
Firebase deployed from this branch: **Partially — see rollout state below**

## Verified baseline

The latest exact run passed:

- 61/61 unit tests
- 30/30 UI tests
- 10/10 Firebase emulator/rules tests
- 3/3 Function contract tests
- signed generic iOS build passed for the app and Live Activity extension
- clean App Store archive/export passed; exported IPA contains no repository
  Markdown or internal planning documents
- current source-exact archive:
  `/private/tmp/PractiQuest-2.0.0-31-e6b3b35.xcarchive`
- current source-exact IPA:
  `/private/tmp/PractiQuest-2.0.0-31-e6b3b35-export/PracticeBuddy.ipa`
- IPA SHA-256:
  `fff0be53382872d71444ba02cce2835a241f6f4c7f450bdc6441c24a6e7cf5c8`

Simulator:
`54EC2207-327E-4262-AE90-3A31D022F394` (iPhone 17 Pro Max, iOS 26.5)

The latest UI target passed 30/30 on that simulator. The unit target passed
61/61 on the alternate iPhone 17 Pro Max iOS 26.4.1 simulator
`9D737516-088B-44FD-906D-38375549A920`. This is recorded in `PROJECT_STATE.md`;
use the alternate simulator if Xcode 26.5 cannot connect the unit-test host.

Run:

```text
xcodebuild test \
  -project PracticeBuddy.xcodeproj \
  -scheme PracticeBuddy \
  -destination 'platform=iOS Simulator,id=54EC2207-327E-4262-AE90-3A31D022F394' \
  -parallel-testing-enabled NO
```

Rules:

```text
cd functions
npm run test:rules
```

Function contracts:

```text
cd functions
npm run test:functions
```

## Do not reverse

- v1 UI was intentionally deleted. There is no `practiquestV2UI` flag.
- One Studio Quest theme; do not restore theme/font pickers.
- SwiftUI only; no Rive/Lottie.
- Space Grotesk uses explicit `Face` values. Do not apply `.weight()` to it.
- System body/control type is intentional for Korean glyph coverage.
- Keep `Features/Home/HomeViewComponents.swift`; active engines depend on it.
- Room composition is:
  `empty room → placed decorations → avatar → foreground/lighting`.
- No room artwork may bake in a user/avatar or optional decoration.
- No ads. Do not restore banners, rewarded ads, UMP, or duel ad logic.
- Public Explore stays off for initial production.
- App Store paid access must come from verified StoreKit transactions, never
  client-submitted product identifiers.

## Work completed since the original handoff

The launch-hardening commits after the design handoff:

- removed the deterministic launch/navigation race;
- unified practice timing, audio ownership, recovery, and persistence;
- rebuilt every practice tool one at a time;
- polished Today, Quest, Community, You, and secondary destinations;
- made profiles relationship-aware;
- added App Check V2 callables for identity, social, friends, Moments, deletion,
  notifications, duels, and trial claiming;
- added production feature flags and Firestore indexes;
- removed all ad infrastructure;
- retired PBTheme/PBLayout/PBTypography compatibility;
- closed remaining interaction seams;
- hardened StoreKit/trial trust;
- added validated custom/Universal friend links and full-surface sharing.

Latest commits:

```text
f699bca Refresh release handoff checkpoints
43e68b8 Record legal site review branch
d79152a Pin physical release checklist to current artifact
5a924e7 Record source-exact release archive
e6b3b35 Record launch hardening verification
5a5827d Harden deterministic launch and Apple sign-in
852697e Record privacy release hardening
c152689 Prepare PractiQuest 2.0 release metadata
50fdb9b Complete App Store privacy declarations
bd88167 Correct App Store identity and legacy Pro access
43e54b0 Harden App Store export contents
8b0e6c2 Record staged Firebase production rollout
4d0955a Enforce callable rate limits
ee26541 Refresh launch state and release runbooks
d3bd68a Complete secure musician invite links
99e4ae6 Harden StoreKit and trial entitlement trust
0cd093d Protect friend mutations with App Check callables
d8d82b0 Retire legacy theme compatibility and expand launch QA
8e402c5 Polish deterministic root experiences
40a40e9 Polish deterministic launch states
```

The separate website repository now has a complete v2 legal/support review
branch:

```text
repository: Nica-code/PractiQuest-Website
branch: codex/practiquest-v2-legal
commit: 8788602
review: https://github.com/Nica-code/PractiQuest-Website/pull/new/codex/practiquest-v2-legal
```

It replaces v1 privacy, terms, and support copy and adds a responsive semantic
light/dark system. Real-browser QA covered desktop, 390-point mobile, dark
appearance, Reduce Motion, keyboard skip-link focus, 44-point navigation, and
horizontal overflow. The branch is pushed but not merged or deployed. Confirm
the published contact email is actively monitored and obtain final legal review
before merging; merging `main` may deploy the live site.

## Current priority

The simulator implementation is past the main functional rewrite. The
source-exact TestFlight upload is currently blocked by the Xcode account's
missing App Store Connect provider relationship. Resolve that credential gate
first; then continue release operations in this order:

1. reauthenticate the Apple ID in Xcode Settings → Accounts and confirm App
   Store Connect provider access, or supply an App Store Connect API key ID,
   issuer ID, and `.p8` private key;
2. upload build 31 from
   `/private/tmp/PractiQuest-2.0.0-31-e6b3b35.xcarchive`;
3. review, merge, and deploy website branch
   `codex/practiquest-v2-legal` (`8788602`) using
   `Docs/LEGAL_SITE_V2_UPDATE.md`;
4. publish the prepared App Store privacy/age/social answers and create/verify
   the Pro product;
5. register DeviceCheck in Firebase Console using the Apple `.p8` key and Key
   ID; App Attest is already registered;
6. verify App Check and migration behavior on a physical device;
7. coordinate the owner-only Firestore-rule cutover with the v2 client;
8. execute the complete physical-device checklist;
9. fix any device-only defects;
10. recapture final App Store screenshots and finish metadata.

Do not deploy Firebase casually. Legacy HTTP endpoints remain intentionally for
old App Store clients, and App Check enforcement is staged to avoid locking out
legitimate builds.

Release metadata is prepared in `Docs/APP_STORE_RELEASE_METADATA_2.0.md`.
The live privacy, terms, and support pages remain a blocker; the prepared
website branch must be reviewed, merged, deployed, and verified before
submission.

## Firebase rollout state — 2026-07-27

Deployed from `3898fe9` to `practicebuddytracker`:

- 8 additive Firestore indexes;
- 41 active Functions (12 preserved production exports, 29 additive exports);
- Hosting with `/invite`, current AASA files, and the invite fallback;
- Storage rules, which were already current.

Verified:

- no Function was removed;
- unauthenticated V2 callable request returns 401;
- unauthenticated legacy entitlement request cannot grant access;
- AASA is HTTP 200 JSON and contains `/invite` plus `/join-studio`.

Not deployed:

- `firestore.rules`.

This hold is deliberate. App Store build 1.0.5 (30) directly queries the
`users` collection for social/leaderboard features. The v2 rule makes
`users/{uid}` owner-only. Deploying it before a v2 client is available would
break the shipped binary. Coordinate the rule change with TestFlight/App Store
migration; do not deploy it casually or fold it into an unrelated Firebase
command.

## Release archive and App Check state

The source-exact build-31 release artifacts from verified commit `e6b3b35` are:

```text
/private/tmp/PractiQuest-2.0.0-31-e6b3b35.xcarchive
/private/tmp/PractiQuest-2.0.0-31-e6b3b35-export/PracticeBuddy.ipa
```

The first export exposed a filesystem-synchronized-target packaging defect:
seven repository Markdown files were copied into the app bundle. The app-target
membership exceptions now exclude them. A fresh signed generic build, archive,
export, and 91-test suite all passed, and the current IPA contains no `.md`
files, retired ad symbols/frameworks, stale App Store ID, Calendar permission,
or Google Play reference. Its SHA-256 is
`fff0be53382872d71444ba02cce2835a241f6f4c7f450bdc6441c24a6e7cf5c8`.
Do not remove those membership exceptions as “unused.”

Firebase Console inspection confirmed:

- App Attest is registered for `com.alexmalaimare.practicebuddy`;
- DeviceCheck is not registered because its Apple `.p8` private key and Key ID
  are external credentials, not repository data;
- Cloud Firestore and Authentication App Check are in Monitoring and currently
  show 0% verified traffic;
- Storage enforcement is not enabled.

Do not describe DeviceCheck fallback as operational or enable broader product
enforcement until the credential is registered and valid TestFlight/device
traffic appears in metrics.

App Store Connect content can be browsed in Xcode. The existing account
contains an approved monthly Ad-Free subscription and an approved
`practicebuddy.pro.lifetime` non-consumable. Both are now recognized as Pro from
verified StoreKit transactions. The new Pro monthly creation dialog is filled
but not submitted; creating it requires action-time user confirmation.

The 2026-07-27 upload attempt failed before any transfer with exit 70:

```text
IDEDistribution.DistributionCredentialedProviderLocatorError.providerRequestFailed(
Unexpected nil property at path: 'Actor/relationships/providerId')
```

Xcode also logged `App Store Connect team IDs for account (null)`. This is an
account/provider credential failure, not an archive rejection. No standard
local App Store Connect API-key directory or `.p8` credential was found.
Reauthenticate Xcode Settings → Accounts and confirm provider access, or use an
App Store Connect API key ID, issuer ID, and `.p8` with Xcode's authentication
key arguments. Never print or commit the private key.

The connected iPhone is currently offline in Xcode, so no physical-device
checklist item is verified.

The public PractiQuest App Store ID is `6759354312`. The prior in-app and Hosting
value `6744359618` was wrong. The app and invite fallback are corrected and
covered by a unit assertion. Hosting and `syncEntitlements` were redeployed from
`bd88167`. The live invite contains the correct link, and the legacy endpoint
still rejects unauthenticated product assertions.

## Landmines

- CoreSimulator may hang after compiling. Use the reset sequence in
  `PROJECT_STATE.md`; do not misreport a cancelled run.
- `GoogleAdsOnDeviceConversion` may still appear transitively through Firebase
  measurement packages. Google Mobile Ads/UMP and PractiQuest ad code are
  removed; do not confuse a transitive measurement library with an ad placement.
- The older selected visual board contains a baked-in person. That single detail
  is superseded by the empty-room decision.
- Legacy HTTP endpoints, legacy Ad-Free SKU handling, legacy avatar ID, and
  `/join-studio` are compatibility seams, not accidental dead code.
- The Pro product does not exist merely because its identifier is in code.
- The development-signed archive is not itself distribution proof. The
  successful `app-store-connect` export is the distribution packaging check.
- Do not describe build 31 as uploaded. The provider-credential failure happened
  before transfer and App Store Connect did not receive the archive.
- Do not say Firebase is deployed, App Check enforcement is observed, or
  physical-device behavior is verified until those steps actually occur.

## End-of-session protocol

Before handing back:

1. run both app test targets;
2. run rules tests if Firebase/rules/Functions changed;
3. update `PROJECT_STATE.md`;
4. state the branch and immediate `git status`;
5. list commits created;
6. record migrations/interfaces/risks and exact results;
7. provide a ready-to-paste handoff prompt;
8. never claim the tree is clean without checking it immediately.
