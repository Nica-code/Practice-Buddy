# PractiQuest 2.0 — Firebase Deployment Runbook

Project: `practicebuddytracker`  
Current deployment status for `codex/launch-hardening`: **not deployed**

This order preserves compatibility with the currently shipped App Store client
while introducing V2 callables and rules.

## 1. Preconditions

- [ ] Worktree and intended commit are identified.
- [ ] `firebase login` is active for the correct account.
- [ ] `.firebaserc` resolves `default` to `practicebuddytracker`.
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

Expected: 58 unit and 30 UI tests.

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
- [ ] App Store action targets ID `6744359618`.

## 6. Deploy Firestore and Storage rules

Deploy rules only after Functions are live:

```text
firebase deploy \
  --project practicebuddytracker \
  --only firestore:rules,storage
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

## 7. Feature configuration

Create/review `appConfig/practiquestV2`:

```text
practiceMoments: true
publicExplore: false
identityUpgradeRequired: true
smartCoach: true
newAvatarRenderer: true
```

Do not create a `practiquestV2UI` flag.

## 8. App Check rollout

Client provider behavior:

- simulator Debug: Firebase debug provider;
- production-capable device: App Attest;
- fallback: DeviceCheck.

Rollout:

1. [ ] Register App Attest and DeviceCheck for the iOS app in Firebase Console.
2. [ ] Add only required simulator/CI debug tokens.
3. [ ] Run internal builds and inspect App Check request metrics.
4. [ ] Confirm V2 callable valid/invalid traffic is expected.
5. [ ] Keep already-coded callable enforcement enabled.
6. [ ] Enable Firestore/Storage enforcement only after metrics show legitimate
       production/TestFlight clients are accepted.
7. [ ] Monitor errors and support signals during staged rollout.

Never commit debug tokens.

## 9. Operational safeguards

- [ ] Configure Firebase/Google Cloud budget alerts.
- [ ] Review Function invocation, error, latency, and instance dashboards.
- [ ] Confirm cleanup query volume is bounded.
- [ ] Confirm Moment feed pages remain 15–20 items and no realtime feed listener
      was introduced.
- [ ] Confirm App Check rejection counts are monitored.
- [ ] Confirm logs contain no notes, messages, handles, date of birth, audio, or
      payment identifiers.
- [ ] Record deployed commit SHA and timestamp.

## 10. Client/TestFlight sequence

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
