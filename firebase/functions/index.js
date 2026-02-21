const {onDocumentCreated} = require('firebase-functions/v2/firestore');
const {logger} = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();

exports.notifyAssignmentCreated = onDocumentCreated(
  {
    document: 'studios/{studioId}/assignments/{assignmentId}',
    region: 'us-central1'
  },
  async (event) => {
    const assignmentSnap = event.data;
    if (!assignmentSnap) return;

    const studioId = event.params.studioId;
    const assignmentId = event.params.assignmentId;
    const assignment = assignmentSnap.data() || {};

    const target = assignment.target || 'studio';
    const targetStudentUid = assignment.targetStudentUid || null;
    const title = assignment.title || 'New Assignment';
    const dueAt = assignment.dueAt ? assignment.dueAt.toDate() : null;

    let recipientUids = [];

    if (target === 'individual' && targetStudentUid) {
      recipientUids = [targetStudentUid];
    } else {
      const membersSnap = await db
        .collection('studios')
        .doc(studioId)
        .collection('members')
        .where('role', '==', 'student')
        .get();

      recipientUids = membersSnap.docs.map((doc) => doc.id);
    }

    if (!recipientUids.length) return;

    const usersSnaps = await Promise.all(
      recipientUids.map((uid) => db.collection('users').doc(uid).get())
    );

    const allowedUids = usersSnaps
      .filter((snap) => {
        if (!snap.exists) return false;
        const data = snap.data() || {};
        return data.notificationAssignments !== false;
      })
      .map((snap) => snap.id);

    if (!allowedUids.length) return;

    const tokenRows = await Promise.all(
      allowedUids.map(async (uid) => {
        const devicesSnap = await db.collection('users').doc(uid).collection('devices').get();
        return devicesSnap.docs.map((doc) => ({
          uid,
          deviceDocRef: doc.ref,
          token: (doc.data() || {}).token
        }));
      })
    );

    const tokens = tokenRows
      .flat()
      .filter((row) => typeof row.token === 'string' && row.token.length > 0);

    if (!tokens.length) return;

    const body = target === 'individual'
      ? `You received an individual assignment: ${title}`
      : `New studio assignment: ${title}`;

    const dataPayload = {
      type: 'assignment_new',
      studioId,
      assignmentId,
      target,
      dueAt: dueAt ? dueAt.toISOString() : ''
    };

    const chunks = chunk(tokens, 500);
    for (const chunkRows of chunks) {
      const response = await messaging.sendEachForMulticast({
        tokens: chunkRows.map((row) => row.token),
        notification: {
          title: 'New Assignment',
          body
        },
        data: dataPayload,
        apns: {
          payload: {
            aps: {
              sound: 'default'
            }
          }
        }
      });

      await cleanupInvalidTokens(chunkRows, response.responses);
    }

    logger.info('Assignment notifications dispatched', {
      studioId,
      assignmentId,
      recipientCount: allowedUids.length,
      tokenCount: tokens.length
    });
  }
);

async function cleanupInvalidTokens(rows, responses) {
  const deletions = [];

  responses.forEach((res, index) => {
    if (res.success) return;

    const code = res.error && res.error.code;
    if (
      code === 'messaging/registration-token-not-registered' ||
      code === 'messaging/invalid-registration-token'
    ) {
      deletions.push(rows[index].deviceDocRef.delete());
    }
  });

  if (deletions.length) {
    await Promise.allSettled(deletions);
  }
}

function chunk(items, size) {
  const out = [];
  for (let i = 0; i < items.length; i += size) {
    out.push(items.slice(i, i + size));
  }
  return out;
}
