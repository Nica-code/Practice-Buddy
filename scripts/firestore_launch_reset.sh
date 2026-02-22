#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="practicebuddytracker"

# Deletes test Firestore collections used by the app.
# Run from repo root: ./scripts/firestore_launch_reset.sh

collections=(
  users
  studios
  friendships
  invites
)

for col in "${collections[@]}"; do
  echo "Deleting collection: ${col}"
  firebase firestore:delete "${col}" --project "${PROJECT_ID}" --recursive --force
  echo "Deleted: ${col}"
done

echo "Firestore reset complete for ${PROJECT_ID}."
echo "Next: delete Authentication test users from Firebase Console (Auth -> Users)."
