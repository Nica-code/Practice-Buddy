#!/usr/bin/env node

const path = require('path');
const admin = require('firebase-admin');

function argValue(name) {
  const index = process.argv.indexOf(name);
  if (index === -1) return null;
  return process.argv[index + 1] || null;
}

function parseList(raw) {
  if (!raw) return [];
  return raw
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean);
}

async function resolvePreservedUIDs({ auth, preserveUIDs, preserveEmails }) {
  const output = new Set(preserveUIDs);

  for (const email of preserveEmails) {
    try {
      const user = await auth.getUserByEmail(email);
      output.add(user.uid);
      console.log(`Preserving email ${email} -> uid ${user.uid}`);
    } catch (error) {
      console.warn(`Could not resolve preserved email ${email}: ${error.message}`);
    }
  }

  return output;
}

async function deleteCollections(db, collectionIDs) {
  for (const id of collectionIDs) {
    console.log(`Deleting collection: ${id}`);
    await db.recursiveDelete(db.collection(id));
    console.log(`Deleted collection: ${id}`);
  }
}

async function deleteUsersExcept(db, preservedUIDs) {
  const userRefs = await db.collection('users').listDocuments();
  let deleted = 0;
  let kept = 0;

  for (const ref of userRefs) {
    if (preservedUIDs.has(ref.id)) {
      kept += 1;
      console.log(`Keeping users/${ref.id}`);
      continue;
    }
    await db.recursiveDelete(ref);
    deleted += 1;
  }

  return { deleted, kept };
}

async function main() {
  const serviceAccountPath = argValue('--service-account');
  const projectId = argValue('--project') || 'practicebuddytracker';
  const preserveUIDs = parseList(argValue('--preserve-uids'));
  const preserveEmails = parseList(argValue('--preserve-emails'));

  if (serviceAccountPath) {
    admin.initializeApp({
      credential: admin.credential.cert(require(path.resolve(serviceAccountPath))),
      projectId
    });
  } else {
    admin.initializeApp({
      credential: admin.credential.applicationDefault(),
      projectId
    });
  }

  const db = admin.firestore();
  const auth = admin.auth();

  const preservedUIDs = await resolvePreservedUIDs({
    auth,
    preserveUIDs,
    preserveEmails
  });

  if (preservedUIDs.size === 0) {
    console.warn('No preserved UIDs resolved. All user docs will be deleted.');
  } else {
    console.log(`Preserved user UID count: ${preservedUIDs.size}`);
  }

  await deleteCollections(db, ['studios', 'friendships', 'invites']);
  const userResult = await deleteUsersExcept(db, preservedUIDs);

  console.log('Launch reset complete.');
  console.log(`Users deleted: ${userResult.deleted}`);
  console.log(`Users kept: ${userResult.kept}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
