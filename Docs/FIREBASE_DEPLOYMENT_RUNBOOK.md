# PractiQuest 2.0 — Firebase Deployment Runbook

Project: `practicebuddytracker`  
Current deployment status for `codex/launch-hardening`:

- indexes: deployed from `3898fe9` on 2026-07-27;
- Functions: 41/41 active from `3898fe9`; `syncEntitlements` corrected from
  `bd88167`;
- Hosting: corrected from `bd88167` and HTTPS-verified;
- Storage rules: current/released;
- Firestore rules: held for coordinated v2 client cutover.

This order preserves compatibility with the currently shipped App Store client
while introducing V2 callables and rules.

## 1. Preconditions

- [ ] Worktree and intended commit are identified.
- [ ] `firebase login` is active for the correct account.
- [ ] `.firebaserc` resolves `default` to `practicebuddytracker`.
- [ ] `firebase projects:list --json` succeeds and the active account can see
      `practicebuddytracker`.
- [ ] `firebase functions:list --project practicebuddytracker --json` is saved
      or reviewed as the pre-deployment production inventory.
- [ ] A recent production backup/export exists.
- [ ] The current App Store client's Firebase behavior is understood.
- [ ] `publicExplore` will remain false.
- [ ] No production reset script will be run as part of deployment.

Run:

```text
git status -sb
node --check functions/index.js
cd functions
npm run test:functions
npm run test:rules
```

Expected: 3 Function contracts and 10 rules tests passing.

Run the exact iOS suite from the repository root:

```text
xcodebuild test \
  -project PracticeBuddy.xcodeproj \
  -scheme PracticeBuddy \
  -destination 'platform=iOS Simulator,id=54EC2207-327E-4262-AE90-3A31D022F394' \
  -parallel-testing-enabled NO
```

Expected: 59 unit and 30 UI tests.

Run a signed generic-device build:

```text
xcodebuild build -quiet \
  -project PracticeBuddy.xcodeproj \
  -scheme PracticeBuddy \
  -destination 'generic/platform=iOS'
```

Expected: exit code 0 for the app and Live Activity extension.

## 2. Review the production diff

Review all of:

- `firestore.indexes.json`
- `firestore.rules`
- `storage.rules`
- `functions/index.js`
- `hosting/apple-app-site-association`
- `hosting/.well-known/apple-app-site-association`
- `hosting/invite/index.html`

Confirm:

- old HTTP endpoints remain for existing-client compatibility;
- V2 callables enforce App Check;
- the entitlement HTTP endpoint does not trust client product IDs;
- server-owned fields cannot be written directly;
- `/invite` is included in both AASA files;
- `/join-studio` remains only as a compatibility path;
- Function `maxInstances` and scheduled jobs are bounded.

## 3. Deploy indexes

```text
firebase deploy \
  --project practicebuddytracker \
  --only firestore:indexes
```

- [ ] Wait until all indexes report ready in Firebase Console.
- [ ] Do not deploy clients that require a building index.

## 4. Deploy backward-compatible Functions

```text
firebase deploy \
  --project practicebuddytracker \
  --only functions
```

Smoke-test:

- [ ] old App Store client can still read/practice/sign in;
- [ ] legacy HTTP endpoints return expected compatibility responses;
- [ ] V2 callable requests without valid App Check fail;
- [ ] authenticated V2 callable requests succeed;
- [ ] trial claim cannot be used by an anonymous account;
- [ ] client-supplied product IDs cannot grant paid access;
- [ ] scheduled cleanup and duel settlement logs show no error loop.

Do not remove compatibility HTTP endpoints in this release.

## 5. Deploy hosting

```text
firebase deploy \
  --project practicebuddytracker \
  --only hosting
```

Verify over HTTPS:

- [ ] `/apple-app-site-association` returns JSON with no redirect;
- [ ] `/.well-known/apple-app-site-association` returns JSON with no redirect;
- [ ] both use `Content-Type: application/json`;
- [ ] `/invite?code=AB12-CD34` renders the PractiQuest invite fallback;
- [ ] invalid code hides the Open PractiQuest action;
- [ ] App Store action targets ID `6759354312`.

## 6. Firestore privacy cutover gate

Do **not** deploy the owner-only Firestore rules merely because Functions and
Hosting are live.

The currently shipped App Store build 1.0.5 (30) performs collection queries
against `users` for social and leaderboard features. The v2 rules correctly
make `users/{uid}` private and move social reads to `publicProfiles`, but
Firestore cannot redact private fields or transparently redirect the old query.
Deploying that rule before a v2 client is available would break the shipped
binary.

Before the rule cutover:

- [ ] a v2 internal TestFlight build is available;
- [ ] App Check succeeds on a physical device;
- [ ] new-account and legacy profile-upgrade paths create `publicProfiles`;
- [ ] friends, messages, duels, search, and leaderboards read public projections;
- [ ] current sessions, inventory, entitlements, and private practice still load;
- [ ] support/rollback owners agree on the cutover window;
- [ ] the previous Firestore rules release is identifiable for rollback.

Storage rules are independently backward-compatible and may be deployed earlier:

```text
firebase deploy \
  --project practicebuddytracker \
  --only storage
```

## 7. Deploy Firestore rules at the coordinated cutover

Only after every gate above passes:

```text
firebase deploy \
  --project practicebuddytracker \
  --only firestore:rules
```

Production smoke matrix:

- [ ] owner can read private user data;
- [ ] another user cannot read it;
- [ ] public profile exposes only approved projection fields;
- [ ] non-friends cannot message;
- [ ] blocked users cannot read/interact;
- [ ] minor restrictions apply;
- [ ] private follows require approval;
- [ ] Moment audience and expiry apply;
- [ ] reports remain server/private;
- [ ] friend invite/accept/decline/cancel/remove works through callables;
- [ ] existing friends/messages/duels remain reachable.

## 8. Feature configuration

Create/review `appConfig/practiquestV2`:

```text
practiceMoments: true
publicExplore: false
identityUpgradeRequired: true
smartCoach: true
newAvatarRenderer: true
```

Do not create a `practiquestV2UI` flag.

## 9. App Check rollout

Client provider behavior:

- simulator Debug: Firebase debug provider;
- production-capable device: App Attest;
- fallback: DeviceCheck.

Rollout:

1. [x] Register App Attest for the iOS app in Firebase Console.
2. [ ] Register DeviceCheck using an Apple DeviceCheck `.p8` private key and its
       Key ID. Team ID is `73J84HKXBC`; never commit the private key.
3. [ ] Add only required simulator/CI debug tokens.
4. [ ] Run internal builds and inspect App Check request metrics.
5. [ ] Confirm V2 callable valid/invalid traffic is expected.
6. [ ] Keep already-coded callable enforcement enabled.
7. [ ] Enable Firestore/Storage enforcement only after metrics show legitimate
       production/TestFlight clients are accepted.
8. [ ] Monitor errors and support signals during staged rollout.

Observed on 2026-07-27:

- App Attest registered for `com.alexmalaimare.practicebuddy`;
- DeviceCheck not registered;
- Cloud Firestore and Authentication in Monitoring;
- both currently show 0% verified / 100% unverified traffic;
- Storage product enforcement is not enabled.

Never commit debug tokens.

## 10. Operational safeguards

- [ ] Configure Firebase/Google Cloud budget alerts.
- [ ] Review Function invocation, error, latency, and instance dashboards.
- [ ] Confirm cleanup query volume is bounded.
- [ ] Confirm Moment feed pages remain 15–20 items and no realtime feed listener
      was introduced.
- [ ] Confirm App Check rejection counts are monitored.
- [ ] Confirm logs contain no notes, messages, handles, date of birth, audio, or
      payment identifiers.
- [ ] Record deployed commit SHA and timestamp.

## 11. Client/TestFlight sequence

Only after backend smoke tests:

1. distribute an internal TestFlight build;
2. run the physical-device checklist;
3. test migration from current App Store data;
4. observe App Check and Functions;
5. run a focused external beta;
6. fix all P0–P2 issues;
7. submit production build.

## Rollback

If a deployment causes material breakage:

- Functions: redeploy the last known compatible commit; do not delete endpoints.
- Rules: redeploy the last known rules file immediately.
- Flags: disable the affected optional feature; keep private practice available.
- App Check: relax the newly enabled product enforcement while investigating,
  without disabling authorization/rules.
- Client: stop TestFlight rollout or App Store phased release.

Record the incident, affected versions, timestamps, and corrective commit.
