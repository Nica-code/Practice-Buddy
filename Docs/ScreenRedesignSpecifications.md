# PractiQuest Screen Redesign Specifications — Phase E2

Date: 2026-07-28
Companion to `Docs/VisualProductAudit.md`. This document specifies concrete
composition and behavior, not adjectives. Today is specified in full detail
because Phase E3 implements it next; Journey, Community, You, and practice
completion are specified at the level needed to guide their eventual
redesign, informed by what the audit confirmed is already working (do not
re-spec what isn't broken).

Existing components referenced below (do not recreate):
`StudioQuestScrollPage`, `studioQuestSurface()`, `StudioQuestSection`,
`StudioQuestRowSurface`, `StudioQuestEyebrow`, `StudioQuestPrimaryButtonStyle`,
`StudioQuestSecondaryButtonStyle`, `StudioQuestLoadingState`,
`StudioQuestEmptyState`, `StudioQuestErrorState`, `StudioQuestInlineStatus`,
`StudioQuestTokens` (Spacing/Radius/Typography/ColorRole/Elevation).

---

## Today

### Information hierarchy (top to bottom)

1. Compact context header — unchanged from current: title + date, token
   chip, notification bell. Not a card. No change needed.
2. **One hero** — the next-practice / active-session state. This is the only
   element on the screen that gets `studioQuestSurface()` treatment (or an
   even more distinct treatment — see below). Everything else on the screen
   must be visually subordinate to it.
3. Daily goal — stays as the existing inline row with ring + hairline
   separator (`dailyGoalSummary` is already correct; do not wrap it in a
   card).
4. **One combined "next steps" section** replacing the current three
   separate cards (Smart Coach, Next Quest, Recent Session): a single
   un-carded list of plain rows, each following the existing
   `dailyGoalSummary` pattern (icon + two lines of text + trailing
   affordance, separated by hairlines, no individual surface fill). This
   directly answers the audit's "five equally-weighted cards" finding by
   giving the page exactly one surfaced container and demoting the rest to
   rows.
5. Community pulse — folds into the same plain-row list as its own row
   (avatar stack + one line of copy), not a separate card.
6. Recent activity — only rendered when `store.sessions` is non-empty; when
   empty, this row and its section header are omitted entirely rather than
   showing empty-state copy in a card (per brief: "do not reserve a large
   empty area for nonexistent content").

### Primary and secondary actions

- Primary: "Start practice" / "Resume" button inside the hero. Exactly one
  button of `StudioQuestPrimaryButtonStyle` visible on the screen at a time.
- Secondary: the small setup/sliders icon next to the hero button (unchanged
  — it's already visually subordinate, correctly).
- Every row below the hero (Smart Coach, Next Quest, Recent session,
  Community pulse) is a tap target that navigates, but none of them render
  as a `Button`-styled CTA — they're rows, not buttons, matching the "one
  primary action per viewport" principle.

### Full-width vs. contained elements

- Full-width, surfaced: the hero only.
- Full-width, uncontained: header, daily goal row, the combined next-steps
  row list (each row full-width with horizontal page margin, separated by
  `StudioQuestTokens.ColorRole.separator` hairlines — same visual language
  already used by `dailyGoalSummary`'s bottom rule).
- Nothing else should introduce a new visual container type.

### Typography roles

- Page title: `StudioQuestTokens.Typography.pageTitle` (unchanged).
- Hero task name: `sectionTitle` (unchanged).
- Row titles (Smart Coach / Next Quest / Recent session / Community pulse):
  `.headline` for the primary line, `.caption`/`.subheadline` +
  `.foregroundStyle(.secondary)` for the supporting line — same type ramp
  already used inside each of today's cards, just without the surrounding
  card.
- Section eyebrow ("Next steps" or similar) using `StudioQuestEyebrow`,
  appearing once above the combined row list rather than once per card.

### Spacing rhythm

- Outer page rhythm stays `StudioQuestTokens.Spacing.lg` (20pt) between major
  blocks (header → hero → daily goal → next-steps list), matching the
  existing `VStack(spacing: 20)` skeleton in `StudioQuestTodayView.body`.
- Inside the next-steps row list, rows are separated by hairlines with
  `StudioQuestTokens.Spacing.md` (16pt) vertical padding per row — denser
  than full cards, appropriately, since these are secondary content.

### Empty/loading/error behavior

- No active session + no recommendation data yet: hero shows a loading
  skeleton (reuse `StudioQuestLoadingState`, sized to the hero's frame)
  rather than blocking the whole screen.
- No quest available (`nextQuestPresentation == nil`): omit that specific row
  from the next-steps list entirely (already the current `@ViewBuilder`
  behavior for `nextQuest` — preserve it, just move the content into the row
  list rather than a standalone card).
- No recent session: omit the row (see hierarchy §6).
- Offline: not currently modeled for Today (per audit) — out of scope for
  this redesign unless a real network dependency is added to Today later.

### Active-session behavior

- When `coordinator.elapsedSeconds > 0` or a session is running/paused, the
  hero's copy switches from "Start practicing" framing to "Continue [task]" /
  "[N] minutes remaining" framing, exactly per the brief's example copy,
  driven by existing `coordinator.state`/`currentTask`/`plannedMinutes` —
  no new data plumbing required, this is a copy/layout change inside the
  existing hero, not new state.
- The practice dock (`tabViewBottomAccessory`) already mirrors this via
  `coordinator.state` — the hero and dock will show consistent, not
  duplicate-for-no-reason, information: the hero is the actionable summary,
  the dock is the always-visible resume affordance while on other tabs.

### Interaction transitions

- No new transition types. Content-transition on numeric text
  (`.contentTransition(.numericText())`) already used for the goal ring stays.
- Row list uses the same `NavigationLink`/`Button` push behavior already in
  place — no new animation vocabulary.

### What is removed from the current design

- Three of the five `studioQuestSurface()` cards (Smart Coach, Next Quest,
  Recent Session) as standalone surfaced containers — their *content* is
  preserved, just re-hosted as rows in one list. Community Pulse's card is
  also removed the same way.
- No data, service, or business logic is removed — this is purely a
  composition change.

### What existing components are reused

- `StudioQuestScrollPage` (page shell — unchanged).
- `studioQuestSurface()` — used once, for the hero.
- `StudioQuestEyebrow`, `StudioQuestPrimaryButtonStyle` — unchanged.
- The hairline-separator row pattern already proven by `dailyGoalSummary`.

### What is genuinely new

- One small reusable row component (e.g. `StudioQuestPlainRow`) that
  formalizes the icon + two-line-text + trailing-affordance + hairline
  pattern currently hand-rolled inside `dailyGoalSummary`, so Smart Coach,
  Next Quest, Recent Session, and Community Pulse can each become a single
  call site instead of four bespoke `HStack`s. This is a small extraction,
  not a new design system — it names a pattern that already exists once and
  reuses it three more times.

---

## Journey

Not implemented this phase (Phase E3 covers Today only) — specified here for
when Journey is next.

- **Preserve entirely:** the illustrated path, avatar placement, node
  checkmark/color treatment, level/XP bar, the always-visible dock. The audit
  found this screen closer to "done" than any other.
- **Change:** node title labels move from permanent capsules to
  selection-triggered labels — tapping/selecting a node shows its label (and
  opens `QuestDetailSheet` as today); unselected nodes show only their
  icon+ring. This directly answers the audit's confirmed finding.
- **Decide before building:** whether "Duels & Leagues" stays as a segmented
  control on this screen or becomes its own destination reachable from a
  link inside Journey (matching how Shop was already pulled out of Avatar
  Studio). Recommend the latter, since duels/leagues content is
  competition-oriented and visually/conceptually distinct from the personal
  skill-progression path — but this is a product decision, not purely a
  visual one, and should be confirmed with you before implementation.
- **Verify before building:** whether a genuine "locked" node visual state
  exists upstream in `StudioQuestCatalog`/`JourneyProgressManager` — if not,
  add one (distinct from complete/available) per the brief's explicit
  requirement that locked nodes be visually and accessibly distinct.

---

## Community

Not implemented this phase — specified here for when Community is next.

- **Preserve:** the anonymous-user gate, the loading state, the
  search/messages header pattern, the connections-summary row — audit found
  these already close to the brief's intent.
- **Change:** split `statusMessage: String?` into a typed state (e.g.,
  `enum CommunityFeedError { case offline, network, auth, server }`) in
  `CommunityCoordinator`, and route each case to the existing
  `StudioQuestErrorState` component (which already has title/message/retry)
  instead of the generic inline warning banner. Reserve
  `StudioQuestEmptyState` strictly for the *valid* empty case (no error, just
  genuinely no Moments) — never render it at the same time as an error state.
- **Add:** a distinct "no connections yet" variant of the empty state (richer
  than generic empty-feed copy) surfacing suggested musicians/teachers/
  instrument communities, per the brief — this likely needs new data (a
  "suggested accounts" query) rather than being purely a UI change, so it
  should be scoped as its own slice once the error/empty split above lands.

---

## You

Not implemented this phase — specified here for when You is next.

- **Preserve:** hero sizing (already reasonably short per the audit), the
  "This week" card, the plain "Recent activity" list, Settings as a separate
  destination, the data-driven avatar/instrument rendering.
- **Change:** either remove `StudioQuestVerifiedLabel(isVerified:
  !firebase.isAnonymousUser)` from the identity header entirely, or replace
  it with copy that means what it actually reflects (account status, not
  practice verification) — do not ship the same "Verified"/shield visual
  language for two unrelated concepts. This is a small, contained change
  (one call site) with no data-model impact.

---

## Practice completion

Not implemented this phase — specified here since the audit ranked it #1.

- **Preserve:** the single `PracticeSessionCoordinator` as the state owner,
  the metrics already computed (verified/unverified seconds, check-in count),
  save/discard logic, Moment-eligibility logic.
- **Change:** collapse the two sequential sheets into one. Concretely:
  - The reflection form's optional fields (mood, title, focus, "what
    clicked," notes, detailed per-piece journal) become genuinely optional —
    remove `.interactiveDismissDisabled()` and allow saving with defaults if
    the user simply taps "Done"/"Save" without filling anything in.
  - The one summary screen leads with the celebration/metrics content
    (minutes, verified time, streak, XP/quest progress if applicable) as the
    primary focal content — reflection fields become a secondary, clearly
    optional section below it, not the entire screen.
  - Moment publishing becomes an inline option *within this same screen*
    (e.g., a "Share this session as a Moment" toggle/button) rather than a
    second sheet presented after this one closes. If `momentPrompt`
    eligibility logic needs to stay server-driven, it can still gate whether
    the option appears, but it should not open a second modal sheet.
  - This preserves all existing data flow (`completeAfterSave`,
    `savePracticeCompletion`, `momentPrompt`) — only the presentation
    structure (two sheets → one) changes.
