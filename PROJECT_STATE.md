# PractiQuest — Development State Snapshot

**Last Updated**: 2026-07-26
**Current App Version**: 2.0.0 (build 31) — not yet uploaded
**Active Branch**: `codex/launch-hardening`
**Build Status**: `BUILD SUCCEEDED` (simulator + signed `generic/platform=iOS`)
**Tests**: 10/10 unit, 6/6 UI

---

## 2026-07-26 — Studio Quest 2.0 design pass

Ten commits, starting from a checkpoint of the previous session's uncommitted
work (`f008bab`) so the whole pass is revertible. Swift LOC 39,994 → 29,449.

### Typography — the app was rendering fake bold everywhere
`StudioQuestTokens.Typography` called `.weight(.bold)` on `SpaceGrotesk-Regular`,
a 400-only face with no variable axis, so CoreText synthesized every page,
section and card title by smearing the outline. Now ships Regular / Medium /
SemiBold / Bold instanced from the official OFL variable font, with each display
role naming the file genuinely cut at that weight.

`PBFontChoice` had the same bug independently: once it resolved a custom family
it returned `.custom(name:size:)` and dropped the requested weight, so every
headline in the practice tools rendered at Regular.

Body copy stays on the system font deliberately — **Space Grotesk has no Hangul
and the app ships Korean.**

Bundled fonts: 1.6 MB → 352 KB (12 faces → 4).

### The v1 UI layer is gone
Studio Quest 2.0 was already the default shell, so the entire v1 view layer was
dead weight compiled into every build. Removed ~11,300 lines: HomeView,
JourneyView, StudioHubView, ProfileTabView, SettingsView, ShopView,
InventoryView, StoreView, PracticeView, HistoryView, SocialView, FriendsView,
the onboarding tutorial and their component files, plus the `practiquestV2UI`
flag. Also removed `StudioQuestCommunityView` (624 lines) — a superseded
first-pass Community screen inside the *v2* layer that nothing referenced.

**Rescued before deletion** (v2 routes to them):
`SocialChatThreadView` and `PublicUserProfileView` now live in their own files.

**`HomeViewComponents.swift` is kept despite the name** — it holds
`MetronomeEngine`, `PracticeAppShieldManager`, `SoundStyle`, `Subdivision` and
`TunerNeedleGauge`, which `PracticeStudioView` and `PracticeSessionCoordinator`
depend on. Do not delete it because it looks like v1.

### Shop
`AppRoute.avatarStudio(section: .shop)` was **never constructed anywhere**, so
nothing could route to the shop. Now `AppRoute.shop` with a real
`StudioQuestShopView`, reached from a `StudioQuestTokenChip` in the Today and
Quest headers. The Shop segment was removed from Avatar Studio so exactly one
shop exists.

### You tab and Studio Edit
You opens on an edge-to-edge hero at 52% of screen height with parallax; the
avatar renders at 66% width instead of 46%. `StudioQuestAvatarScene` gained a
`Presentation` (`.card` / `.hero`). Studio Edit became a full-screen editor
presented as a `fullScreenCover` — a pushed view kept the practice dock on
screen, because the dock is a `tabViewBottomAccessory` and survives
`.toolbar(.hidden, for: .tabBar)`.

### Practice tools ported via the theme layer
The six tools reached from Quest nodes still rendered through the v1 `PBTheme`
palette. Ported by making `PBTheme` resolve to `StudioQuestTokens` rather than
by rewriting call sites — **no tool's layout or logic was touched**, so
behaviour is provably unchanged. Verified by sampling the modal canvas colour of
every tool against Today: exact match in light and dark.

This fixed a live upgrade bug: `ThemeManager` still read the saved
`pb.settings.colorThemeID`, but the theme picker was deleted in 2.0 — anyone who
had picked Cantabile or Concert Hall in v1 kept pink or gold practice tools
inside a cobalt app, with no way to change it. `PBTheme.byID` now deliberately
ignores the stored identifier.

### Quest content
`StudioQuestCatalog` is now the single source of truth. Previously the list was
inline in `StudioQuestQuestView` with a second hand-written copy of "Dynamic
control" in Today that had already drifted in both subtitle and launched task.
Today's "Next quest" now surfaces the first *outstanding* quest instead of
hard-coding one that may already be complete.

### Other
- Elevation scale (`StudioQuestTokens.Elevation` + `studioQuestSurface`): cast
  shadow in light, strengthening border in dark.
- Today/Community density restored toward the approved board; Swift Charts
  replaced the hand-stacked capsule week bars.
- You's weekly ring was filling by minutes while printing session count — two
  metrics in one control. Fixed.
- Motion pass, all gated on Reduce Motion.

---

## Xcode / build notes

**Always build and run the `PracticeBuddy` scheme.** The Live Activity
extension is embedded automatically (`PracticeBuddy.app/PlugIns/`); its own
scheme cannot launch the app.

The `PracticeBuddy` scheme's Launch action had been switched into widget
debugging mode (`askForAppToLaunch="Yes"`, `launchAutomaticallySubstyle="2"`,
`<RemoteRunnable com.apple.springboard>`), which is what produced the "Choose an
app to run" prompt. Restored to a normal `BuildableProductRunnable`. **Xcode
rewrites this file while open** — if the prompt returns, fix it via Product →
Scheme → Edit Scheme → Run → Info.

The shared scheme previously had no `<Testables>`, so `xcodebuild test` failed
with "not configured for the test action". Both test targets are now wired in.

Signing is healthy: team `73J84HKXBC`, automatic, bundle IDs correctly nested.
Debug device builds resolve `aps-environment` to `development` even though the
entitlements file says `production` — Xcode substitutes it to match the
development profile.

---

## Known gaps

- **Quest content is bundled, not fetched.** `StudioQuestCatalog` is the seam a
  remote or bundled feed would plug into; shipping a new quest still needs a
  build.
- **QA launch-argument race.** `practiquest.v2.destination` persists across
  launches, and `StudioQuestShell.onAppear` can read a stale value before
  `ContentView` applies `--qa-destination`. Uninstall the app between scripted
  runs, or the destination may be wrong.
- Community IA is still wide: three header actions plus four Connections
  sections. Worth revisiting.
- Segmented controls remain on Quest and Connections.
- `PBTheme` / `PBTypography` / `PBLayout` still exist as a thin compatibility
  layer for the practice tools. They now emit Studio Quest values, but the tools
  are still Form/List-based rather than built from Studio Quest components.
- No `SKAdNetworkItems`, no ATT prompt, no UMP consent flow (needed for EEA/UK
  ad serving).

---

## Before uploading 2.0.0

- Create the Pro product `com.alexmalaimare.practiquest.pro.monthly` in App
  Store Connect; keep the legacy Ad-Free SKU for entitlement recognition.
- Deploy the updated Firebase `syncEntitlements` allowlist first.
- Validate anonymous → Apple/Google/email upgrade on a physical device.
- Validate APNs, Live Activity, Family Controls shielding, StoreKit sandbox
  purchase/restore, and grandfathered entitlements in TestFlight.
- Recapture App Store screenshots — every primary screen changed.

---

## Key files

- `PracticeBuddy/App/ContentView.swift`, `App/AppNavigation.swift`
- `PracticeBuddy/Features/StudioQuest/` — the v2 shell and destinations
- `PracticeBuddy/Models/StudioQuestCatalog.swift` — quest content
- `PracticeBuddy/SharedUI/StudioQuestDesign.swift` — tokens, surfaces, chrome
- `PracticeBuddy/SharedUI/PBTheme.swift` — compatibility layer for the tools
- `PracticeBuddy/Services/JourneyProgressManager.swift`
- `functions/index.js`, `firestore.rules`
