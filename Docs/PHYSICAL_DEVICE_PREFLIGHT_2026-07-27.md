# PractiQuest 2.0 — Physical-Device Preflight

Date: 2026-07-27  
Release train: 2.0.0 (31)  
Device class: iPhone 17 Pro (`iPhone18,1`)  
OS: iOS 27.0 beta (`24A5390f`)  
Connection: paired, wired, Developer Mode enabled

This is a non-destructive launch/performance preflight. It does not replace the
interactive physical-device checklist.

## Verified

- CoreDevice discovered the paired production-fused iPhone and reported it
  available.
- The installed app is:
  - name: PractiQuest;
  - bundle: `com.alexmalaimare.practicebuddy`;
  - version: 2.0.0;
  - build: 31;
  - developer build: yes.
- An initial launch while the phone was locked was rejected by SpringBoard with
  the expected locked-device error.
- After unlock, the same installed build launched normally.
- Repeated terminate/relaunch checks succeeded.
- A console-attached normal launch remained alive for ten seconds without an
  immediate process failure. Ending the console session sent signal 2
  deliberately; that termination is not an application crash.
- CoreDevice subsequently listed the main PractiQuest process as resident.
- A ten-second Time Profiler recording targeted the exact main PractiQuest
  process on the physical device:
  `/private/tmp/PractiQuest-2.0.0-31-iPhone17Pro-main.trace`.
- The trace completed normally and the Instruments potential-hangs table
  contained no event over its 250 ms threshold during the measured idle
  interval.

Supporting transient evidence:

- `/private/tmp/practiquest-device-app.json`
- `/private/tmp/practiquest-device-processes-current.json`
- `/private/tmp/PractiQuest-2.0.0-31-iPhone17Pro-main-toc.xml`
- `/private/tmp/PractiQuest-2.0.0-31-iPhone17Pro-hangs.xml`

## Evidence limits

- The device is on an iOS 27 beta. It does not satisfy the separate requirement
  to test the current public iOS 26.x release.
- The trace measured an idle foreground interval. It does not prove
  60/120 Hz scrolling, long-session memory stability, avatar-cache behavior,
  tool switching, or active audio performance.
- No practice session, note, account, avatar, room arrangement, purchase, or
  social data was created or modified for this preflight.
- Microphone latency, audio routes, recording, interruptions, background
  timing, Family Controls, Live Activities, APNs, StoreKit, account migration,
  Universal Links, VoiceOver, and the complete practice-tool matrix remain
  interactive checklist work.
- The presence of the Live Activity extension process does not prove a complete
  ActivityKit start/update/end lifecycle.

## Independent TestFlight gate

The source-exact build-31 upload was retried after this device became available.
It failed before transfer with:

```text
App Store Connect Credentials Error
IDEDistribution.DistributionCredentialedProviderLocatorError.providerRequestFailed(
Unexpected nil property at path: 'Actor/relationships/providerId')
App Store Connect team IDs for account (null)
```

The archive was not rejected and no build was uploaded. Recovery still requires
Xcode Apple-ID reauthentication with valid App Store Connect provider access or
an App Store Connect API key ID, issuer ID, and private `.p8` key.
