#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

function argValue(name) {
  const idx = process.argv.indexOf(name);
  if (idx === -1) return null;
  return process.argv[idx + 1] || null;
}

async function main() {
  const serviceAccountPath = argValue('--service-account');
  const projectId = argValue('--project') || 'practicebuddytracker';
  const filePath = argValue('--file') || path.resolve(process.cwd(), '../scripts/all_access_whitelist.json');

  if (!serviceAccountPath) {
    console.error('Missing --service-account <path-to-service-account.json>');
    process.exit(1);
  }

  const whitelistRaw = fs.readFileSync(filePath, 'utf8');
  const whitelist = JSON.parse(whitelistRaw);

  const uids = new Set(Array.isArray(whitelist.uids) ? whitelist.uids.filter(Boolean) : []);
  const emails = Array.isArray(whitelist.emails) ? whitelist.emails.filter(Boolean) : [];
  const restoreAccountType = whitelist.restoreAccountType || null; // optional: student/teacher

  admin.initializeApp({
    credential: admin.credential.cert(require(path.resolve(serviceAccountPath))),
    projectId
  });

  const auth = admin.auth();
  const db = admin.firestore();

  for (const email of emails) {
    try {
      const user = await auth.getUserByEmail(email);
      uids.add(user.uid);
      console.log(`Resolved ${email} -> ${user.uid}`);
    } catch (err) {
      console.warn(`Could not resolve email ${email}: ${err.message}`);
    }
  }

  if (uids.size === 0) {
    console.log('No target UIDs found. Nothing to update.');
    return;
  }

  const batch = db.batch();
  const now = admin.firestore.FieldValue.serverTimestamp();

  for (const uid of uids) {
    const userRef = db.collection('users').doc(uid);
    const payload = {
      entitlementTier: 'free',
      isPro: false,
      hasLifetimePro: false,
      canSwitchRoleFreely: false,
      isMasterAccount: false,
      allAccessRevokedBy: 'whitelist_script',
      allAccessRevokedAt: now,
      updatedAt: now
    };

    if (restoreAccountType === 'student' || restoreAccountType === 'teacher') {
      payload.accountType = restoreAccountType;
      payload.accountTypeSet = true;
      payload.accountTypeChangeUsed = false;
    }

    batch.set(userRef, payload, { merge: true });
  }

  await batch.commit();
  console.log(`Revoked all_access for ${uids.size} users.`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
