# Practice Buddy Firebase Functions

This folder contains server-side Firebase Cloud Functions used by the iOS app.

## Current Function

- `notifyAssignmentCreated`
  - Trigger: `studios/{studioId}/assignments/{assignmentId}` document create
  - Behavior:
    - If `target == "studio"`: notifies all student members of the studio.
    - If `target == "individual"`: notifies only `targetStudentUid`.
    - Respects each user flag `users/{uid}.notificationAssignments` (default on when field is missing).
    - Reads FCM tokens from `users/{uid}/devices/{deviceId}.token`.
    - Deletes invalid tokens returned by FCM.

## Prerequisites

- Firebase project already created.
- Firebase CLI installed and authenticated (`firebase login`).
- Blaze plan enabled (required for Cloud Functions deployment).

## Deploy

From this folder:

```bash
npm install
firebase use <your-project-id>
firebase deploy --only functions
```

## Local Emulator (Optional)

```bash
npm install
firebase emulators:start --only functions
```

## App-side Notes

- iOS app must have:
  - Push Notifications capability enabled.
  - APNs key uploaded in Firebase Console -> Project Settings -> Cloud Messaging.
  - `GoogleService-Info.plist` from the same Firebase project.
- App writes FCM token documents to:
  - `users/{uid}/devices/{sha256Token}`
