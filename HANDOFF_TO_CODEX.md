# Handoff — PractiQuest, Studio Quest 2.0 design pass

You are picking up PractiQuest (internal target name `PracticeBuddy`) mid-stream.
Another agent (Claude) just completed a large design and cleanup pass on branch
`codex/launch-hardening`. **Read `PROJECT_STATE.md` first** — it is current as of
2026-07-26 and is the authoritative snapshot. This file explains the *direction*
and the rules that keep our work consistent.

Everything below is committed. Nothing is pushed. Working tree is clean.
Version is **2.0.0 (build 31)**. Build is green on simulator and on a signed
`generic/platform=iOS`. Tests: **10/10 unit, 6/6 UI**.

---

## 1. The design direction

PractiQuest should feel **inspired by Instagram, Duolingo and Tonic Music — but
better**. Concretely:

- **Instagram** — profile-header structure, social density, real activity signal.
- **Duolingo** — an always-visible currency that is always one tap from being
  spent; progression that feels earned.
- **Tonic** — photographic calm, restraint, letting commissioned art breathe.

Four decisions the app owner (Nica) made explicitly. **Do not reverse these
without asking:**

1. **Full scope** — foundation, shop surfacing, You redesign, Studio Edit,
   Today/Community density, motion.
2. **The v1 UI is deleted**, not flagged off. Rollback is a git revert.
3. **Shop is reached from a global token chip**, not a fifth tab.
4. **No Rive/Lottie.** SwiftUI-only motion. Revisit animated avatars as a
   possible v2.1 feature.

---

## 2. What the previous session found

Three defects that had shipped unnoticed. Context matters because they explain
several of the rules in §4.

**Every heading in the app was rendering fake bold.**
`StudioQuestTokens.Typography` called `.weight(.bold)` on `SpaceGrotesk-Regular`
— a 400-only face with no variable axis — so CoreText synthesized the weight by
smearing the outline on every page, section and card title. `PBFontChoice` had
the same class of bug independently: once it resolved a custom family it
returned `.custom(name:size:)` and silently dropped the requested weight, so
every headline in the practice tools rendered at Regular.

**The Shop was unreachable by route.** `AppRoute.avatarStudio(section: .shop)`
was never constructed anywhere in the codebase.

**The implementation had drifted below its own approved design.** Comparing
`Design/StudioQuest2/QA/selected-direction.png` against what shipped: Today had
lost its cards, thumbnails and friend-activity count; Community had lost its
activity detail; You had shrunk a full-bleed hero into a small inset card. The
existing `design-qa.md` reported "P0: none, P1: none, P2: none" — but it graded
the build against itself, not against the reference board. **Do not treat that
document as evidence of design fidelity.**

---

## 3. What changed (11 commits, in order)

```
f008bab  [Checkpoint] Studio Quest 2.0 working tree + real Space Grotesk weights
51194d0  [Refactor] Delete the v1 UI layer and the practiquestV2UI flag
7bb29b4  [Feature] Give the Shop a real destination and a global token chip
42b6644  [Design] Rebuild the You tab around a full-bleed hero
936dada  [Design] Rebuild Studio Edit as an immersive full-screen editor
d542364  [Design] Restore Today and Community density
2f34cc5  [Polish] Motion pass, weekly insight fix, and testable scheme
39aad7b  [Fix] Restore the PracticeBuddy scheme to launch the app
635ca15  [Design] Port the practice tools onto the Studio Quest system
bfb96b2  [Refactor] Give featured quests a single source of truth
543986d  [Docs] Refresh PROJECT_STATE.md for Studio Quest 2.0
```

`f008bab` is a checkpoint of the previous session's uncommitted work, so the
whole pass is revertible.

**Swift LOC 39,994 → 29,449. Bundled fonts 1.6 MB → 352 KB.**

### Typography
Ships Regular / Medium / SemiBold / Bold instanced from the official OFL
variable Space Grotesk. Each display role names the file genuinely cut at that
weight via `StudioQuestTokens.Typography.Face`. Body copy stays on the system
font **deliberately — Space Grotesk has no Hangul and this app ships Korean.**

### v1 deletion
~11,300 lines removed: HomeView, JourneyView, StudioHubView, ProfileTabView,
SettingsView, ShopView, InventoryView, StoreView, PracticeView, HistoryView,
SocialView, FriendsView, the onboarding tutorial, their component files, and the
`practiquestV2UI` flag. Also `StudioQuestCommunityView` (624 lines) — a
superseded first-pass Community screen inside the *v2* layer that nothing
referenced. `SocialChatThreadView` and `PublicUserProfileView` were extracted to
their own files first because v2 routes to them.

### Shop
`AppRoute.shop` + `StudioQuestShopView` (balance card, featured item chosen as
the cheapest affordable unowned decoration, decoration grid using art already in
the asset catalogue, reward sections, Pro upsell). `StudioQuestTokenChip` sits
in the Today and Quest headers. The Shop segment was removed from Avatar Studio
and `.shop` dropped from `AvatarStudioSection`, so exactly one shop exists.

### You tab and Studio Edit
You opens on an edge-to-edge hero at 52% of screen height with parallax
(disabled under Reduce Motion); the avatar renders at 66% width instead of 46%.
`StudioQuestAvatarScene` gained a `Presentation` enum (`.card` / `.hero`). The
overlaid "You" title was removed — the tab bar already names the tab and the
display name sits directly below, and it was unreadable against the daylight
room.

Studio Edit became a full-screen editor (`StudioQuestRoomEditorView`) presented
as a `fullScreenCover`. **A pushed view kept the practice dock on screen,
because the dock is a `tabViewBottomAccessory` and survives
`.toolbar(.hidden, for: .tabBar)`.** Only escaping the TabView removes it.

### Practice tools
The six tools reached from Quest nodes (warm-up, rhythm, intonation, smart loop,
run-through, plan/execute/reflect) rendered through the v1 `PBTheme` palette.
Ported by making `PBTheme` resolve to `StudioQuestTokens`, **not** by rewriting
call sites — no tool's layout or logic was touched. Verified by sampling the
modal canvas colour of every tool against Today: exact match in light and dark.

This fixed a live upgrade bug: `ThemeManager` still read the saved
`pb.settings.colorThemeID`, but the theme picker was deleted in 2.0, so anyone
who picked Cantabile or Concert Hall in v1 was stuck with pink or gold practice
tools inside a cobalt app. `PBTheme.byID` now deliberately ignores the stored ID.

### Quest content
`StudioQuestCatalog` (`PracticeBuddy/Models/`) is the single source of truth for
featured quest content, map placement and node colour. Previously the list was
inline in `StudioQuestQuestView` with a second hand-written copy of "Dynamic
control" in Today that had already drifted in both subtitle and launched task.
Today's "Next quest" now surfaces the first *outstanding* quest instead of
hard-coding one that may already be complete.

### Other
- Elevation scale (`StudioQuestTokens.Elevation` + `.studioQuestSurface()`):
  cast shadow in light, strengthening border in dark, because a shadow does not
  read on a dark canvas.
- Swift Charts replaced the hand-stacked capsule week bars (first-party, brings
  axis handling and VoiceOver audio graphs).
- You's weekly ring was filling by minutes while printing session count — two
  metrics in one control. Fixed.
- Motion pass: scroll transitions, symbol effects, `PhaseAnimator` reward pulse.
  All gated on Reduce Motion.
- Removed a duplicate You row where "Activity" and "History" both routed to
  `.history`.

### Build/test infrastructure
- The `PracticeBuddy` scheme's Launch action had been switched into widget
  debugging mode (`askForAppToLaunch="Yes"`,
  `launchAutomaticallySubstyle="2"`, `<RemoteRunnable com.apple.springboard>`),
  which produced a "Choose an app to run" prompt instead of running the app.
  Restored to a normal `BuildableProductRunnable`.
- The shared scheme had no `<Testables>`, so `xcodebuild test` failed outright.
  Both test targets are now wired in.
- Two UI tests were **already failing before this session** (proven against a
  reconstructed baseline worktree — same tests, same line numbers). Fixed:
  `BuddiesViewModel.applyStudioQuestDebugFixtures()` was never called from
  anywhere so friend fixtures could not appear; and the tests reached for
  `app.navigationBars`, which iOS 26's floating circular back button does not
  expose.
- Added `--qa-route` cases for the six practice tools, `shop`, `roomEditor` and
  `communityFriends`.

---

## 4. Rules — please follow these so our work stays consistent

**Design system**
- Cards use `.studioQuestSurface(_:)`. Do not hand-roll fill + hairline.
- Section labels use `StudioQuestEyebrow`. Do not re-declare local
  `sectionLabel` helpers — that is how tracking and colour drifted before.
- Display type uses `StudioQuestTokens.Typography`. **Never call `.weight()` on
  a Space Grotesk font** — pick the `Face` instead, or you reintroduce synthetic
  bold.
- **Body copy stays on the system font.** Space Grotesk has no Hangul.
- Colours come from `StudioQuestTokens.ColorRole`. Do not reintroduce the
  multi-theme `PBTheme` catalogue; there is one palette now and it resolves to
  Studio Quest values.
- Every animation must respect `@Environment(\.accessibilityReduceMotion)`.

**Structure**
- Quest content goes in `StudioQuestCatalog`. Do not build quests inline in a
  view again.
- **Do not delete `Features/Home/HomeViewComponents.swift`.** Despite the name
  and location it is not v1 — it holds `MetronomeEngine`,
  `PracticeAppShieldManager`, `SoundStyle`, `Subdivision`, `TunerNeedleGauge`,
  which `PracticeStudioView` and `PracticeSessionCoordinator` depend on.
- Prefer first-party frameworks. Swift Charts is in use. No new UI, navigation
  or styling dependencies — they fight SwiftUI and cost the iOS 26 material
  system.

**Verification**
- **Always build and run the `PracticeBuddy` scheme, never the Live Activity
  extension's.** The extension is embedded automatically into
  `PracticeBuddy.app/PlugIns/`; its own scheme cannot launch the app.
- Run **both** test targets before claiming done:
  `xcodebuild test -scheme PracticeBuddy -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'`
- When judging design fidelity, **diff against
  `Design/StudioQuest2/QA/selected-direction.png` directly.** Do not rely on
  `design-qa.md`; it graded the build against itself and reported all-clear on a
  build that had visibly under-delivered.

---

## 5. Two caveats to be aware of

**A. The practice tools are ported but not rebuilt.**
The six tools now share the Studio Quest canvas, accent and type — verified
pixel-exact against the Today tab in both appearances. But they are still
`Form`/`List`-based underneath rather than composed from Studio Quest
components, so they read as iOS grouped forms wearing the right colours. Going
further means real layout rewrites in files where breaking behaviour is easy
(timers, metronome engines, audio callbacks, Family Controls shielding). This
should be its own scoped pass with before/after verification per tool — it was
deliberately *not* bundled into the port, whose entire safety argument was that
no tool code changed. **If you take this on, port one tool end to end and verify
it before touching the other five.**

**B. There is a QA launch-argument race.**
`practiquest.v2.destination` persists in `UserDefaults`, and
`StudioQuestShell.onAppear` can read a stale value before `ContentView` applies
`--qa-destination`. The symptom is scripted launches landing on the wrong tab,
which produces confusing and misleading screenshots. Workaround:
`xcrun simctl uninstall <device> com.alexmalaimare.practicebuddy` between
scripted runs. This was left unfixed because the fix touches launch ordering and
destabilising startup right before an archive was not worth it. **Fixing it
properly is welcome — just verify cold-launch, warm-launch and notification
routing afterwards.**

---

## 6. Known gaps / candidate next work

- **Practice tools rebuild** (caveat A) — the largest remaining visual gap, on
  the highest-intent path in the app.
- **QA launch race** (caveat B).
- **Quest content is bundled, not fetched.** `StudioQuestCatalog` is the seam a
  remote or bundled feed plugs into; shipping a new quest still needs a build.
- **Community IA is wide** — three header actions plus four Connections
  sections (friends / following / followers / requests). Instagram collapses
  this. Worth revisiting.
- Segmented controls remain on Quest and Connections.
- `PBTheme` / `PBTypography` / `PBLayout` survive as a thin compatibility layer
  for the tools. They emit Studio Quest values now; they can go once caveat A is
  resolved.
- No `SKAdNetworkItems`, no ATT prompt, no Google UMP consent flow (the last is
  required for EEA/UK ad serving).

**Before uploading 2.0.0:** create the Pro product
`com.alexmalaimare.practiquest.pro.monthly` in App Store Connect, keep the
legacy Ad-Free SKU for entitlement recognition, deploy the updated Firebase
`syncEntitlements` allowlist first, and validate APNs / Live Activity / Family
Controls / StoreKit sandbox in TestFlight. **Every primary screen changed, so
App Store screenshots must be recaptured.**

---

## 7. Environment notes

- Xcode 26.6, iOS 26.5 simulators. Target device: iPhone 17 Pro Max.
- Signing is healthy: team `73J84HKXBC`, automatic, bundle IDs correctly nested
  (`com.alexmalaimare.practicebuddy` /
  `…practicebuddy.PracticeBuddyLiveActivity`).
- Debug device builds resolve `aps-environment` to `development` even though the
  entitlements file says `production` — Xcode substitutes it to match the
  development profile. This is expected.
- **Xcode rewrites `PracticeBuddy.xcscheme` while it is open.** If the "Choose an
  app to run" prompt returns, fix it via Product → Scheme → Edit Scheme → Run →
  Info (Executable: PracticeBuddy.app, Launch: Automatically).
