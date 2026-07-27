# PractiQuest Firebase Deployment Record — 2026-07-27

Project: `practicebuddytracker`  
Source branch: `codex/launch-hardening`  
Source commit: `3898fe90f44c7fda3a0d414af57744b6396424c9`  
Operator account: `contact@alexmalaimare.com`

## Pre-deployment inventory

- Project state: active.
- Production Functions: 12.
- Local Functions: 41.
- Existing Functions preserved: 12.
- Functions scheduled for deletion: 0.
- Production composite indexes: 0.
- Local composite indexes: 8.
- Hosting live release: 2026-02-21.
- Live AASA before deployment: `/join-studio` only.

## Deployment

The following stages completed successfully, in order:

1. `firestore:indexes`
2. `functions`
3. `hosting`
4. `storage`

The Storage rules were already current; Firebase compiled and re-released them.

`firestore:rules` was intentionally not deployed.

## Post-deployment verification

- Firestore indexes listed: 8.
- Functions active: 41.
- Functions in a non-active state: 0.
- Existing Function deletions: 0.
- V2 callables listed: 18.
- Scheduled Functions:
  - `cleanupExpiredPracticeMoments`
  - `duelSettleSweep`
- V2 callable without App Check/authentication: HTTP 401.
- Legacy entitlement endpoint without authentication: rejected.
- Hosting AASA: HTTP 200 and `Content-Type: application/json`.
- AASA routes:
  - `/invite?code=????-????`
  - `/join-studio?code=*`
- The initial invite fallback contained the incorrect App Store ID
  `6744359618`. App Store Connect and the public listing both confirm the
  PractiQuest record is `6759354312`; a corrective Hosting deployment is
  required before the invite fallback is release-ready.
- Invite fallback validates the `XXXX-XXXX` code and hides the app-open action
  for malformed codes.

## Deliberate hold

App Store build 1.0.5 (30) directly queries the `users` collection for social
and leaderboard data. The v2 Firestore rules make `users/{uid}` owner-only and
move those reads to server-owned `publicProfiles`.

Deploying the v2 rule before a v2 client is available would break the current
binary. The rule must be deployed during a coordinated v2 TestFlight/App Store
migration window after physical-device App Check and profile-projection checks
pass.

## Open release gates

- PractiQuest Pro product creation/verification in App Store Connect.
- DeviceCheck registration using the Apple `.p8` key and Key ID. App Attest is
  registered already.
- Physical-device App Check, audio, Live Activity, Family Controls, APNs,
  StoreKit, migration, and Universal Link tests.
- `appConfig/practiquestV2` production review.
- Firestore privacy-rule cutover.
- App Check metrics observation and broader product enforcement.
- Internal and focused external TestFlight.
- Final App Store metadata, screenshots, and submission.

## App Check console observation

Firebase Console inspection on 2026-07-27 confirmed:

- iOS app `com.alexmalaimare.practicebuddy` is registered with App Attest;
- DeviceCheck is not registered;
- Cloud Firestore and Authentication are in Monitoring;
- their current request metrics show 0% verified and 100% unverified;
- Storage enforcement is not enabled.

Callable enforcement remains active in the deployed V2 Functions. Broader
Firestore/Storage enforcement must wait for DeviceCheck registration and clean
physical-device/TestFlight metrics.
