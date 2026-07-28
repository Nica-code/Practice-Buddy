# PractiQuest Visual Product Audit — Phase E1

Date: 2026-07-28
Scope: Today, Journey, Community, You, the practice dock, the full practice
session, session setup, session completion, and major loading/empty/offline/
error states, evaluated against the target identity "a premium music-practice
platform with a subtle game layer" (60% premium native clarity / 25%
progression-and-feedback / 15% illustrated world).

## Method and honesty note

This audit combines two kinds of evidence:

- **Live-verified**: Today, Journey (Quest tab), and You were captured as
  screenshots from a real build running on the iPhone 17 Pro Max iOS 26.5
  simulator, launched directly into each destination via the app's own
  `--qa-destination` launch-argument harness (`AppLaunchConfiguration`) to
  avoid needing scripted touch input, which this session's tooling could not
  provide (the native simulator-control tool needs a one-time
  `sudo xcode-select` fix only the device owner can run, and Simulator
  accessibility automation was not authorized in this sandbox).
- **Code-verified**: Community's state handling, the Journey node rendering
  logic, and the practice-completion flow are assessed by reading the actual
  SwiftUI source rather than by driving the live states, since reaching them
  (empty feed, network error, mid-session completion) requires interaction
  this session couldn't script. Findings here are marked accordingly and
  should be spot-checked visually before being treated as final.

No screen was redesigned during this pass, per instruction.

---

## Today

**Primary user question:** "What should I practice now?"
**Primary action:** Start/resume practice.
**Current focal point:** Visually, the "Next practice" card is first and
largest, so it reads as dominant on first glance.

**Every major visual container** (source: `StudioQuestShell.swift`,
`StudioQuestTodayView`), in order:

1. Header row (title + date + token chip + notification bell) — not a card.
2. `nextPracticeHero` — `studioQuestSurface()` card (icon, task name,
   duration/verification line, Start/Resume button, setup button).
3. `dailyGoalSummary` — not a card; inline row with a ring + bottom hairline
   separator.
4. `smartCoachSuggestion` — `studioQuestSurface()` card.
5. `nextQuest` — `studioQuestSurface()` card.
6. `recentSession` — `studioQuestSurface()` card.
7. `communityPulse` — `studioQuestSurface()` card.

**Which containers are actually necessary:** the hero card, yes — it holds
the primary action. `dailyGoalSummary` is already correctly *not* a card
(inline row), which is good precedent already in the codebase. Smart Coach,
Next Quest, Recent Session, and Community Pulse do not need containment of
their own; they are single-line-of-information rows dressed as cards.

**Confirmed finding — competing/equally-weighted containers:** `nextQuest`,
`smartCoachSuggestion`, `recentSession`, and `communityPulse` all call the
identical `studioQuestSurface()` with default arguments (`.resting` elevation,
`.surface` radius) — the exact same visual weight as `nextPracticeHero`
(`StudioQuestShell.swift:664-666, 761, 807, 840, 919`). A screen meant to have
"one dominant hero" instead renders **five visually-equivalent white rounded
cards stacked vertically**, which is precisely the "long vertically stacked
dashboard" / "endless white rounded cards" pattern the product brief calls
out as an anti-pattern. This is a real, code-confirmed instance of "weak
hierarchy caused by how existing tokens are used" — the tokens are fine; the
composition applies them uniformly where the content is not uniform in
importance.

**Excessive elements:** none of these individual cards are overloaded, but
the *set* of them is the issue — four secondary sections all reaching for the
same "just add `studioQuestSurface()`" pattern rather than differentiated
treatments (e.g., plain rows, a horizontal strip, or a single combined
"today at a glance" section).

**Content that should be condensed/moved:** Smart Coach, Next Quest, and
Community Pulse are all single-line teasers pointing elsewhere; visually
distinguishing "this is the one thing you should do" (hero) from "here are
three pointers to other places" (the rest) would fix most of the hierarchy
complaint without removing any content.

**Navigation depth:** Start practice is one tap from Today (good). Each
secondary section is a `NavigationLink`/`Button` one tap away from its
destination — shallow, no complaints here.

**States:** `PracticeQuestProgressStore`/`SessionStore` drive real data; no
loading/offline/error state was found specific to Today itself — Today reads
from already-loaded local stores (`SessionStore`, `JourneyProgressManager`),
so it doesn't have its own network-dependent loading state the way Community
does. This should be verified against actual first-launch behavior (cold
Firebase bootstrap) rather than assumed complete.

**Accessibility/Dynamic Type risk:** the `dailyGoalSummary` ring is a fixed
54×54 with percentage text inside — at accessibility-large Dynamic Type
sizes this is a likely truncation/overlap risk (not verified live this pass).

**Feel:** premium — yes, clean typography and restrained color, matches the
rest of the app. Musical/serious — yes. Motivating — yes, visible next-quest
teaser. Visually connected to other tabs — yes, consistent token usage.
**Verdict: composition problem, not a token or navigation problem.**

---

## Journey (Quest tab — user-facing label now "Journey" after Phase C)

**Primary user question:** "How am I developing?"
**Primary action:** open/continue the current quest, or start practice via
the dock.

**Screenshot-verified layout** (live capture, iPhone 17 Pro Max iOS 26.5):

1. Page header ("Journey" / "Your path. Your music.") + token chip.
2. Level + XP progress bar (thin, compact — not a large ring, good).
3. Segmented control: "Journey" / "Duels & Leagues".
4. The illustrated path (`Image("StudioQuestQuestPath")`) with avatar and
   quest nodes overlaid, inside one rounded, bordered container.
5. `RewardUnlockedView` when a claimable reward exists (only conditionally
   present — good, not a permanent empty slot).

**What's already working well (do not disturb):** the illustration itself
reads as premium and distinct — genuinely one of the app's strongest visual
assets, exactly as the brief says to preserve. Completed nodes show a
checkmark against a colored ring; the avatar is positioned on the path
itself rather than floating separately. This is a stronger execution than
the brief's "static image with floating buttons" worry assumes.

**Confirmed finding — labels are permanent, not contextual:**
`StudioQuestDestinationViews.swift:187-210` (`questNode`) renders every
node's title as an always-visible capsule label beneath its circle,
unconditionally, for every node in `featuredQuests`. The brief specifically
asks: "Labels may appear contextually when selecting a node" and "reduce
floating labels that obscure the artwork." Currently there is no
selected/unselected label state at all — all labels show at all times. With
only 4 nodes this is legible today, but it does not scale, and it's a
direct, concrete gap against the brief's stated Journey requirement.

**Unverified/worth checking finding — no explicit "locked" node state:**
reading `questNode`, `nodeColor(for:)`, and `nodePosition(for:)`, node
styling branches only on `quest.isComplete` (checkmark vs. category icon) and
a per-quest fixed `nodeColor` from `StudioQuestCatalog`. No branch for
"locked because a prerequisite isn't met yet" was found in this file. It's
possible locking is enforced elsewhere (e.g., inside `QuestDetailSheet` when
tapped, or nodes for locked quests are simply excluded from
`featuredQuests`), but as composed here, nothing in the node's own visual
treatment communicates "available" vs. "locked" vs. "current" beyond
complete/incomplete — this needs a direct check against
`StudioQuestCatalog`/`JourneyProgressManager` before deciding whether it's a
real gap or already handled upstream.

**Segmented control:** "Duels & Leagues" lives in the same screen as
"Journey" behind a segmented control. The brief explicitly asks to evaluate
whether this belongs together or should be a secondary destination, and not
to keep it merely because it exists. Given competitive/duel content
(`competitionSummary`, `liveQuests`, `duelArenaLink`) is conceptually
distinct from personal skill progression, and the illustrated path is meant
to be the hero of this tab, a case exists for moving Duels & Leagues to its
own destination (reachable from a link, similar to how Shop was already
pulled out from Avatar Studio per the existing code comment at
`AppNavigation.swift:108-110`). Recommend deciding this in the redesign spec
rather than in this audit.

**Reduce Motion:** confirmed respected — `StudioQuestDestinationViews.swift`
reads `@Environment(\.accessibilityReduceMotion)` and the parallax/reward
animations already branch on it elsewhere in the app (per Phase 0 audit).

**Feel:** premium — yes. Musical — yes, the strongest asset in the app.
Motivating — yes. Serious — mostly, though "Warm-up warrior" style naming
leans a little playful/game-y versus the brief's target tone for serious
adult/conservatory users; worth a copy pass, not urgent.

---

## Community

**Primary user question:** "Who am I practicing alongside?"
**Primary action:** open a Moment, follow a musician, or (new user) set up a
profile / find people.

**Code-verified state handling** (`StudioQuestCommunityFeedViews.swift`,
`PracticeMomentRepository.swift`, not screenshot-verified this pass):

- **Anonymous/no-account gate**: distinct and correct — shows a dedicated
  "Practice privately, then join your community" section with a clear "Set
  up profile" action (`feedContent`, `showsAccountGate` branch). This is a
  legitimately good new-user path, close to what the brief asks for.
- **Loading**: `community.isLoading && community.moments.isEmpty` →
  `StudioQuestLoadingState`. Distinct and correct.
- **Empty vs. error — confirmed ambiguity**: `community.statusMessage` (set
  from `error.localizedDescription` or the generic string "We couldn't
  refresh Moments. Pull to try again." in `CommunityCoordinator.refresh()`)
  renders as an inline warning banner *above* the feed content, while
  `community.moments.isEmpty` *simultaneously* renders the generic
  `StudioQuestEmptyState` ("No Moments yet... Follow a musician...") *below*
  it, whenever both are true — which they will be on any first-load network
  failure. A user would see a network-error banner and an empty-state message
  suggesting they "follow a musician" at the same time, for what is actually
  one problem (the refresh failed), described two different ways. This is
  exactly the pattern the brief names directly: "Do not show a network error
  and generic empty state simultaneously unless both conditions truly apply
  and the relationship is clear." Here it doesn't apply cleanly — the copy
  doesn't acknowledge the relationship between the two.
- **No distinct offline/auth/server-failure states**: every error path
  (network, server, decode failure) sets the same `statusMessage: String?`
  with either a generic string or `error.localizedDescription` — there is no
  code path that distinguishes "you're offline" from "the server is down"
  from "your session expired." The app's own `StudioQuestErrorState`
  component (with a proper title/message/retry button) exists elsewhere in
  the design system but is **not used here at all** — Community only ever
  uses the lighter-weight inline warning banner, never the dedicated error
  state with retry.
- **New-user-with-no-connections vs. valid-empty-feed**: not distinguished —
  both produce the same `StudioQuestEmptyState` copy regardless of whether
  the user has zero friends or has friends who simply haven't posted. The
  brief asks for "new user with no follows or content" to be a distinct,
  richer state (suggested musicians, teachers, instrument communities,
  "share your first Moment") — currently it's one generic empty state with a
  single "explore community" action.

**Search/Messages/connections integration:** already reasonably close to the
brief's ask — `header` puts Search and Messages as toolbar-style icon
buttons next to the page title (not "three detached oversized floating
circles"), and `connectionsSummary` is a single row, not three separate
circles. This part of Community is in better shape than the brief assumed.

**Feel:** the account-gate and loading states feel calm and on-brand; the
error/empty conflation is the main thing undermining "visually connected,
credible" community feel — a user hitting a real network failure gets mixed
signals about whether the product works.

---

## You

**Primary user question:** "Who am I becoming as a musician?"
**Primary action:** not a single dominant action — this screen is
identity/progress-oriented, which is appropriate for its purpose, but there
is no clear primary action at all (edit profile is a small pencil icon over
the hero; everything else is passive reading). That itself may be correct
for an identity tab, but worth confirming intentionally rather than by
default.

**Screenshot-verified layout** (live capture):

1. Cinematic avatar-room hero (parallax, ~42% of screen height, clamped
   300–420pt) with an edit-profile pencil button top-right.
2. "Your studio" / "Level N musician" + a "Standard"/"Verified" pill.
3. "This week" card: minutes practiced, sessions recorded, a percent ring,
   and a 7-day bar chart — one dense, well-organized card, not several.
4. "Recent activity" — a plain list (not cards), correctly not padded out
   with empty space when short.
5. Secondary links (Goals, History, etc.) below the fold, confirmed via the
   You-tab screenshot to sit right at the safe-area boundary, visible via
   the tab bar's native blur.

**Confirmed finding — hero sizing already reasonably short:** at 300–420pt
clamped and capped to 42% of screen height, the hero is not the "long
cinematic area that pushes everything below the fold" the brief worries
about in the abstract — on the iPhone 17 Pro Max capture, "This week" and
"Recent activity" were both visible without scrolling. This part of the
brief's worry does not hold up against the current implementation.

**Confirmed finding — "Verified" badge has no coherent meaning here:**
`StudioQuestDestinationViews.swift:657`:
`StudioQuestVerifiedLabel(isVerified: !firebase.isAnonymousUser)`. The same
`StudioQuestVerifiedLabel` component is used elsewhere
(`StudioQuestShell.swift:448-452`) to mean "this practice session used
microphone-based verification" (`coordinator.isVerified`) — a real,
practice-specific concept with its own accessibility copy ("Practice
verification active/inactive"). On the You screen, the identical
visual/copy ("Verified"/"Standard", shield icon) is reused to mean something
unrelated: whether the user has created a permanent account versus using the
app anonymously. A user reading "Standard" or "Verified" on their own
identity header would reasonably assume it relates to practice authenticity
or a credential, not anonymous-vs-signed-in auth state. This is exactly the
brief's own instruction: "Verification must have a real product meaning or
be hidden." As currently wired, it's a plausible source of user confusion,
and should either be renamed/re-copied for this context (e.g., "Guest" vs.
account status wording unrelated to "verification") or removed from the You
header entirely.

**Instrument/avatar accuracy:** the captured screenshot shows a violin avatar
consistent with the fixture data used; loadout is decoded from
`AvatarLoadout`/`buddies.myProfile?.avatarID` with a `.starter(for:)`
fallback — this is genuinely data-driven, not a hardcoded cello, contradicting
the brief's generic worry. Not fully verified across every instrument option,
but the mechanism itself is correct.

**Settings:** confirmed as its own destination (`AppRoute.settings`,
separate from the You body) — already matches the brief's ask.

---

## Practice dock (`StudioQuestPracticeDock`)

Fixed via Phase A this session (see below). Beyond clearance: the dock's
own content composition is sound — icon, title/subtitle (subtitle suppressed
in the Today-idle compact state), a verification-shield glyph while running,
and a play/pause-styled action button. No competing visual weight issues
found. It always renders (idle "Start practice" through active states)
rather than appearing/disappearing, which is a deliberate, reasonable
design choice for this app (it's the app's persistent primary CTA, not a
transient mini-player), but is worth confirming is the intended product
decision rather than an oversight, since the brief's mini-player language
assumes it appears only when a session is resumable.

---

## Full practice session / session setup / session completion

**Session setup** (`PracticeSetupView`, not screenshot-verified this pass):
not deeply audited in this session; flagged for a follow-up pass if the
redesign proceeds past Today.

**Practice completion — confirmed two-step modal chain:**
`PracticeSessionCoordinator.complete()` sets `reflectionPresented = true`,
presenting `PracticeReflectionView` as a sheet with
`.interactiveDismissDisabled()` (`PracticeStudioView.swift:50-52`). This view
is a **mandatory reflection form** — mood picker, four text fields (title,
focus, "what clicked," notes), an optional detailed per-piece journal
disclosure group, then Save/Discard — gating the session from being recorded
at all until submitted. It does show session metrics (verified/unverified
seconds, check-in count) via one `StudioQuestSection`, which is good, but
that's a small element inside a much longer mandatory form, not the
"cohesive completion summary" the brief asks for.

After a successful save, `completeAfterSave` clears `reflectionPresented` and
*separately* may set `momentPrompt`, which triggers a second, different sheet
(the Moment composer) from `StudioQuestShell.swift`'s
`.sheet(item: momentPromptBinding)`. This is a confirmed two-sheet sequential
chain (reflection form → completeAfterSave → possible Moment-composer sheet),
which is exactly what the brief says to avoid: "Do not chain several
completion modals," "Provide one cohesive completion summary," and "Allow
reflection or publishing a Moment without forcing it" (currently reflection
is mandatory and blocks completion; Moment-publishing is a second, separate
step rather than an option offered within one summary).

This is the single most concrete, high-value target in the whole audit for
the "session is the central product, should be the most refined experience"
principle — the mechanism (one clock, one coordinator, timestamp-based, no
duplicate session state) is already correct per the Phase 0 audit; the
*presentation* of completion is where the brief's concerns are real.

---

## Screen-state matrix

| Screen | Loading | Populated | Empty (valid) | New user / no content | Offline | Network error | Auth error | Server error |
|---|---|---|---|---|---|---|---|---|
| Today | not found as a distinct state (reads local stores) | ✅ verified live | recentSession has its own inline empty text (not a full-screen state) | n/a | not found | not found | not found | not found |
| Journey | not found as a distinct state | ✅ verified live | n/a (catalog-driven, always populated) | n/a | not found | not found | not found | not found |
| Community | ✅ `StudioQuestLoadingState` | not screenshot-verified | ✅ `StudioQuestEmptyState`, but **conflated with error** (see above) | ✅ distinct anonymous-user gate | not distinguished from network error | ✅ but only as inline warning, not `StudioQuestErrorState` | not distinguished | not distinguished |
| You | not found as a distinct state | ✅ verified live | "Recent activity" empty handled inline | n/a | not found | not found | not found | not found |
| Practice completion | `isSaving` spinner on Save button | ✅ (reflection form) | n/a | n/a | not verified | `saveError` shown via `StudioQuestInlineStatus` | not verified | not verified |

Cells marked "not found"/"not verified" are not confirmed absent — they were
not exercised or located in this pass and should be checked directly (ideally
by running the app with airplane mode / a forced Firebase error) before
concluding whether Today/Journey/You need offline handling at all, given they
mostly read from already-synced local stores rather than making their own
network calls on appearance.

---

## Summary ranking for the redesign spec (Phase E2)

1. **Practice completion modal chain** — highest-value fix; directly
   contradicts the brief's "session is the central product" principle and is
   fully confirmed in code.
2. **Today's five equally-weighted cards** — second highest value; confirmed
   in code, directly explains "weak hierarchy" and "excessive containment."
3. **Community's error/empty conflation and missing distinct
   offline/auth/server states** — confirmed in code; a real trust/clarity gap
   for a feature this app leans on for retention.
4. **You's "Verified" badge semantic mismatch** — confirmed in code; a small,
   contained, high-clarity fix (rename/recontextualize or hide it here).
5. **Journey's permanent node labels and the Duels & Leagues segmented
   control question** — confirmed (labels) / worth a product decision
   (segmented control); lower urgency since the current execution already
   reads as premium and the illustration itself should not be touched.
