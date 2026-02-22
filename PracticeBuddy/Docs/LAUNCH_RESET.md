Practice Buddy Launch Reset (Firebase)

Purpose
- Wipe test Firebase data before production launch.
- Keep default users on normal/free entitlements.
- Grant `all_access` only to whitelisted students.

Project
- Firebase Project ID: practicebuddytracker

1) Deploy latest rules + hosting (if needed)
- firebase deploy --only firestore:rules
- firebase deploy --only hosting

2) Reset Firestore test data
- From repo root:
  - ./scripts/firestore_launch_reset.sh

This deletes these collections recursively:
- users
- studios
- friendships
- invites

3) Delete Firebase Auth test users
- Firebase Console -> Authentication -> Users
- Select all test users -> Delete

4) Verify default launch policy (first sign in)
After a fresh sign in, user docs should include:
- entitlementTier
- canSwitchRoleFreely
- isMasterAccount
- accountType
- hasLifetimePro

Policy in current app build
- Default users: standard entitlements (no global auto-unlock)
- Master account: detected by email list in Info.plist (`nicaviolin@icloud.com`) and can switch roles freely with all access

5) Grant all_access to selected students (whitelist)
A) Edit whitelist file:
- scripts/all_access_whitelist.json

B) Run grant script:
- cd functions
- node scripts/grant_all_access_from_whitelist.js \
  --service-account /absolute/path/to/service-account.json \
  --project practicebuddytracker \
  --file ../scripts/all_access_whitelist.json

6) Revoke all_access for selected users (whitelist)
- cd functions
- node scripts/revoke_all_access_from_whitelist.js \
  --service-account /absolute/path/to/service-account.json \
  --project practicebuddytracker \
  --file ../scripts/all_access_whitelist.json

Whitelist file format:
{
  "uids": ["firebaseUid1", "firebaseUid2"],
  "emails": ["student1@example.com"],
  "forceStudentRole": true,
  "restoreAccountType": "student"
}

Notes:
- `uids` is preferred.
- `emails` are resolved to UIDs through Firebase Auth.
- `forceStudentRole: true` in grant script sets granted users to Student and locks role changes.
- `restoreAccountType` in revoke script is optional (`student` or `teacher`).

Optional harden for master account
- Add your final Firebase UID to Info.plist key PBMasterUIDs for strongest identification.
