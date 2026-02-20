# Firestore Rules For Buddies MVP

Paste this into Firebase Console -> Firestore Database -> Rules.

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    function isSignedIn() {
      return request.auth != null;
    }

    function isSelf(uid) {
      return isSignedIn() && request.auth.uid == uid;
    }

    match /users/{uid} {
      allow read: if isSignedIn();
      allow create, update: if isSelf(uid);
      allow delete: if false;
    }

    match /invites/{inviteId} {
      allow read: if isSignedIn() &&
        (resource.data.fromUid == request.auth.uid || resource.data.toUid == request.auth.uid);

      // Only sender can create an invite from themselves.
      allow create: if isSignedIn()
        && request.resource.data.fromUid == request.auth.uid
        && request.resource.data.toUid is string
        && request.resource.data.status == "pending";

      // Sender or recipient can update invite status.
      allow update: if isSignedIn() &&
        (resource.data.fromUid == request.auth.uid || resource.data.toUid == request.auth.uid);

      allow delete: if isSignedIn() &&
        (resource.data.fromUid == request.auth.uid || resource.data.toUid == request.auth.uid);
    }

    match /friendships/{uid}/buddies/{buddyUid} {
      allow read: if isSelf(uid);
      allow create, update: if isSelf(uid) || request.auth.uid == buddyUid;
      allow delete: if isSelf(uid) || request.auth.uid == buddyUid;
    }
  }
}
```

## Notes

- This is an MVP rule set and intentionally simple.
- The app currently writes invite acceptance from the recipient device, including both friendship docs.
- Later hardening step: move invite acceptance to Cloud Functions and tighten direct write permissions.
