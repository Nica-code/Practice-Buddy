const fs = require("node:fs");
const path = require("node:path");
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const {
  doc,
  getDoc,
  serverTimestamp,
  setDoc,
  Timestamp,
} = require("firebase/firestore");

const projectID = "demo-practiquest";
let testEnvironment;

function rulesPath() {
  return path.resolve(__dirname, "../../firestore.rules");
}

function firestoreFor(uid, claims = {}) {
  return testEnvironment.authenticatedContext(uid, claims).firestore();
}

async function seed(writer) {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await writer(context.firestore());
  });
}

async function seedAcceptedFriends(uidA, uidB) {
  await seed(async (firestore) => {
    await setDoc(doc(firestore, `friendships/${uidA}/buddies/${uidB}`), {
      buddyUid: uidB,
    });
    await setDoc(doc(firestore, `friendships/${uidB}/buddies/${uidA}`), {
      buddyUid: uidA,
    });
  });
}

describe("PractiQuest Firestore security rules", () => {
  before(async () => {
    testEnvironment = await initializeTestEnvironment({
      projectId: projectID,
      firestore: {
        rules: fs.readFileSync(rulesPath(), "utf8"),
      },
    });
  });

  beforeEach(async () => {
    await testEnvironment.clearFirestore();
  });

  after(async () => {
    await testEnvironment.cleanup();
  });

  it("keeps private account documents owner-only", async () => {
    await seed(async (firestore) => {
      await setDoc(doc(firestore, "users/alice"), {
        displayName: "Alice",
        email: "alice@example.com",
      });
    });

    await assertSucceeds(getDoc(doc(firestoreFor("alice"), "users/alice")));
    await assertFails(getDoc(doc(firestoreFor("bob"), "users/alice")));
    await assertFails(
        getDoc(doc(testEnvironment.unauthenticatedContext().firestore(), "users/alice")),
    );
  });

  it("allows read-only production feature flags without exposing a write path", async () => {
    await seed(async (firestore) => {
      await setDoc(doc(firestore, "appConfig/practiquestV2"), {
        practiceMoments: true,
        publicExplore: false,
      });
    });

    await assertSucceeds(
        getDoc(doc(testEnvironment.unauthenticatedContext().firestore(), "appConfig/practiquestV2")),
    );
    await assertFails(setDoc(doc(firestoreFor("alice"), "appConfig/practiquestV2"), {
      publicExplore: true,
    }, {merge: true}));
  });

  it("prevents clients from granting themselves entitlements", async () => {
    await assertSucceeds(setDoc(doc(firestoreFor("alice"), "users/alice"), {
      displayName: "Alice",
    }));
    await assertFails(setDoc(doc(firestoreFor("alice"), "users/alice"), {
      displayName: "Alice",
      isPro: true,
    }, {merge: true}));
  });

  it("exposes only server-owned public profile projections", async () => {
    await seed(async (firestore) => {
      await setDoc(doc(firestore, "publicProfiles/alice"), {
        displayName: "Alice",
        handle: "alice.music",
        instrument: "Violin",
      });
    });

    await assertSucceeds(getDoc(doc(firestoreFor("bob"), "publicProfiles/alice")));
    await assertFails(setDoc(doc(firestoreFor("alice"), "publicProfiles/alice"), {
      displayName: "Impersonated",
    }, {merge: true}));
  });

  it("allows accepted friends to create a chat and send a message", async () => {
    await seedAcceptedFriends("alice", "bob");
    const alice = firestoreFor("alice");
    const thread = doc(alice, "friendChats/alice__bob");

    await assertSucceeds(setDoc(thread, {
      participants: ["alice", "bob"],
      createdAt: serverTimestamp(),
      lastMessageText: "",
    }));
    await assertSucceeds(setDoc(doc(alice, "friendChats/alice__bob/messages/message-1"), {
      senderUid: "alice",
      text: "Ready to practice?",
      createdAt: serverTimestamp(),
    }));
  });

  it("limits legacy invite and friendship compatibility writes to participants", async () => {
    await seed(async (firestore) => {
      await setDoc(doc(firestore, "invites/invite-alice-bob"), {
        fromUid: "alice",
        toUid: "bob",
        status: "pending",
      });
      await setDoc(doc(firestore, "friendships/alice/buddies/bob"), {
        buddyUid: "bob",
      });
    });

    await assertSucceeds(getDoc(doc(firestoreFor("alice"), "invites/invite-alice-bob")));
    await assertSucceeds(getDoc(doc(firestoreFor("bob"), "invites/invite-alice-bob")));
    await assertFails(getDoc(doc(firestoreFor("mallory"), "invites/invite-alice-bob")));
    await assertFails(setDoc(doc(firestoreFor("mallory"), "invites/forged"), {
      fromUid: "alice",
      toUid: "bob",
      status: "pending",
    }));
    await assertFails(setDoc(
        doc(firestoreFor("mallory"), "friendships/alice/buddies/bob"),
        {buddyUid: "bob", displayName: "Forged"},
        {merge: true},
    ));
  });

  it("rejects non-friend, self-pair, and impersonated chat writes", async () => {
    const alice = firestoreFor("alice");
    await assertFails(setDoc(doc(alice, "friendChats/alice__mallory"), {
      participants: ["alice", "mallory"],
      createdAt: serverTimestamp(),
    }));
    await assertFails(setDoc(doc(alice, "friendChats/alice__alice"), {
      participants: ["alice", "alice"],
      createdAt: serverTimestamp(),
    }));

    await seedAcceptedFriends("alice", "bob");
    await seed(async (firestore) => {
      await setDoc(doc(firestore, "friendChats/alice__bob"), {
        participants: ["alice", "bob"],
      });
    });
    await assertFails(setDoc(doc(alice, "friendChats/alice__bob/messages/message-1"), {
      senderUid: "bob",
      text: "Forged sender",
      createdAt: serverTimestamp(),
    }));
  });

  it("allows an inbox-authorized active Moment and denies expired Moments", async () => {
    const now = Date.now();
    await seed(async (firestore) => {
      await setDoc(doc(firestore, "practiceMoments/active"), {
        authorUID: "alice",
        expiresAt: Timestamp.fromMillis(now + 60 * 60 * 1000),
      });
      await setDoc(doc(firestore, "practiceMoments/expired"), {
        authorUID: "alice",
        expiresAt: Timestamp.fromMillis(now - 60 * 1000),
      });
      await setDoc(doc(firestore, "feedInboxes/bob/items/active"), {
        momentID: "active",
      });
      await setDoc(doc(firestore, "feedInboxes/bob/items/expired"), {
        momentID: "expired",
      });
    });

    await assertSucceeds(getDoc(doc(firestoreFor("bob"), "practiceMoments/active")));
    await assertFails(getDoc(doc(firestoreFor("bob"), "practiceMoments/expired")));
    await assertFails(getDoc(doc(firestoreFor("mallory"), "practiceMoments/active")));
  });

  it("keeps reactions, reports, blocks, follows, and handles server-authoritative", async () => {
    const alice = firestoreFor("alice");
    const writes = [
      () => setDoc(doc(alice, "practiceMoments/moment/reactions/alice"), {reaction: "bravo"}),
      () => setDoc(doc(alice, "contentReports/report"), {targetID: "moment"}),
      () => setDoc(doc(alice, "socialBlocks/alice_bob"), {blockerUID: "alice"}),
      () => setDoc(doc(alice, "socialFollows/alice_bob"), {fromUID: "alice", toUID: "bob"}),
      () => setDoc(doc(alice, "handles/alice"), {uid: "alice"}),
      () => setDoc(doc(alice, "rateLimits/alice_friend_invite"), {count: 0}),
    ];

    for (const makeWrite of writes) {
      await assertFails(makeWrite());
    }
  });

  it("does not let a minor bypass server-owned social writes", async () => {
    const minor = firestoreFor("minor", {ageBand: "under13"});
    await assertFails(setDoc(doc(minor, "practiceMoments/minor-moment"), {
      authorUID: "minor",
      expiresAt: Timestamp.fromMillis(Date.now() + 60_000),
    }));
    await assertFails(setDoc(doc(minor, "followRequests/minor_adult"), {
      fromUID: "minor",
      toUID: "adult",
    }));
  });
});
