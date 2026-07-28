# PractiQuest 2.0 — Launch Plan Completion Audit

Audit date: 2026-07-27  
Branch: `codex/launch-hardening`  
Release train: 2.0.0 (31)  
Reference: `Design/StudioQuest2/QA/selected-direction.png`

## Status language

- **Verified** — implemented and exercised by current automated or inspected
  evidence.
- **Implemented** — present in the branch, but final proof requires a physical
  device, production traffic, TestFlight, or an owner action.
- **Staged hold** — intentionally not activated because activation before the
  corresponding client/release gate would break or endanger the shipped app.
- **Blocked externally** — cannot be completed from source code alone.

This audit does not describe PractiQuest 2.0 as released. The simulator
implementation and packaging are launch-candidate quality; the physical-device,
TestFlight, legal-site, App Store Connect, and staged Firebase gates remain
release requirements.

## Current-run evidence

The complete app scheme passed in one run:

```text
xcodebuild test \
  -project PracticeBuddy.xcodeproj \
  -scheme PracticeBuddy \
  -destination 'platform=iOS Simulator,id=54EC2207-327E-4262-AE90-3A31D022F394' \
  -parallel-testing-enabled NO
```

- Unit tests: **63/63 passed**
- UI tests: **30/30 passed**
- Result bundle:
  `/Users/nica/Library/Developer/Xcode/DerivedData/PracticeBuddy-cbtxogwfmhmjhogojkyhvrbwjxoa/Logs/Test/Test-PracticeBuddy-2026.07.27_21-14-05--0400.xcresult`
- Firebase emulator/rules tests: **10/10 passed** in the last rules run
- Function contract tests: **3/3 passed** in the last Functions run

Current visual audit captures:

- `/private/tmp/practiquest-completion-audit/01-today-light.png`
- `/private/tmp/practiquest-completion-audit/02-quest-light.png`
- `/private/tmp/practiquest-completion-audit/03-community-light.png`
- `/private/tmp/practiquest-completion-audit/04-you-light.png`
- `/private/tmp/practiquest-completion-audit/05-warmup-running-light.png`
- `/private/tmp/practiquest-completion-audit/06-rhythm-denied-dark.png`
- `/private/tmp/practiquest-completion-audit/07-history-light.png`
- `/private/tmp/practiquest-completion-audit/08-settings-ax-dark.png`

Durable comparison boards remain in `Design/StudioQuest2/QA/`. The older
reference's baked-in person is not authoritative; the accepted target is an
empty room with a separately rendered runtime avatar and independent
decorations.

## Milestone completion matrix

| Milestone | Status | Requirement evidence | Remaining gate |
|---|---|---|---|
| 0 — Deterministic baseline and QA | **Verified** | Immutable `AppLaunchConfiguration`, typed router initialization, deterministic identity/community/tool fixtures, exact route arguments, interaction inventory, visual boards, current 63/30 run. QA launch now resets persisted room placements and focused-tool elapsed state. | Keep fixture coverage synchronized with newly added screens. |
| 1 — Unified practice runtime | **Verified in simulator** | `PracticeSessionCoordinator` owns canonical timing, recovery, verification, shielding, Live Activity state, save/discard, and launch attribution. `PracticeAudioSessionCoordinator` serializes audio owners. Transactional completion and typed parent/tool relationships are covered by unit/UI tests. | Physical interruption, route, microphone, Family Controls, and ActivityKit validation. |
| 2 — Tool system and Library | **Verified** | Shared Studio Quest tool pages, live/result/setup/permission/recovery components; searchable categorized Library with recents/favorites and full-surface cards; no reachable tool uses Form/List as its primary grammar. | Final physical-device visual/audio inspection. |
| 3 — Tool-by-tool rebuild | **Verified in simulator** | Warm-up, Smart Loop, Plan–Execute–Reflect, Run-through, Rhythm, Intonation, Metronome, and Tuner each have setup/runtime/result/recovery/failure coverage. Deterministic scoring, phase timing, audio ownership, orphan-file cleanup, and save retry tests are present. | Microphone latency/accuracy, headphone routes, interruptions, and real recording files on device. |
| 4 — Root IA polish | **Verified** | Today has one dominant start action; Quest owns Journey plus Duels & Leagues; Community is feed-first with Search/Messages and relationship-aware actions; You owns the separate avatar/room system, Goals, History, Pro, and Settings. Full-surface and Dock-clearance UI assertions pass. | Final release screenshots after production configuration is available. |
| 5 — Functional parity audit | **Verified for reachable simulator flows** | `Docs/INTERACTION_INVENTORY.md`, typed secondary-route coverage, Quest nodes, full-pill Community actions, exact chat routing, Shop-to-Quest routing, account/auth states, tool lifecycle tests, room editor controls, localization, and error/recovery states. | Test real notifications, APNs, Universal Links, StoreKit sandbox, and migration data through TestFlight/device. |
| 6 — Backend/security preflight | **Implemented; partially deployed** | V2 App Check callables, hardened compatibility HTTP handlers, private/public projections, age and relationship rules, blocks/reports, rate limits, cleanup jobs, 8 indexes, emulator tests, and bounded Functions. Functions/indexes/Hosting/Storage are deployed. | **Staged hold:** owner-only Firestore rules await v2 cutover. DeviceCheck key, accepted device traffic, App Check observation/enforcement, and production migration remain. |
| 7 — Monetization/ad cleanup | **Verified** | Google Mobile Ads/UMP and app ad infrastructure are removed; no banner/rewarded/duel ad path exists; verified StoreKit entitlements recognize legacy Ad-Free and current Pro products. IPA inspection found no ad framework or retired placement symbols. | Create/configure the new monthly Pro SKU and confirm price/legacy product availability. |
| 8 — Testing and quality gates | **Automated gates verified** | Current 63/30 app run, rules 10/10, Functions 3/3, Korean/Romanian coverage, deterministic accessibility/pseudolocalization checks, visual audit, signed generic build, and App Store export. | Complete every item in `Docs/PHYSICAL_DEVICE_RELEASE_CHECKLIST.md` and resolve device/TestFlight P0–P2 defects. |
| 9 — TestFlight and App Store | **Blocked externally** | Valid build-31 archive and exported IPA exist; metadata, privacy answers, release copy, physical checklist, deployment runbook, and legal-site branch are prepared. | Reauthenticate App Store Connect/provider access or supply API credentials; upload; configure Pro; merge/deploy/review legal site; run internal/external beta; capture final screenshots; submit. |

## Practice-tool evidence

| Tool | Runtime integration | Failure/recovery evidence | Device evidence still required |
|---|---|---|---|
| Warm-up Generator | Canonical focused/contextual session clock; Dock and live elapsed remain synchronized; quest attribution occurs after save. | Pause/resume/result, background phase boundaries, recovered/save-error fixtures. | Background timing and haptics on device. |
| Smart Loop | Timestamp work/rest phases; one clean mark per completed interval; deterministic ladder; shared metronome. | Pause/resume, interruption model, completion, preset-limit explanation, save retry. | Audio route/interruption behavior. |
| Plan–Execute–Reflect | Parent clock preserved through nested tools; private reflection; transactional plan/session save. | Pause/resume, nested navigation, recovered/save-error states. | Background/nested audio utility behavior. |
| Run-through | Permission before count-in/metronome/recording; shared recorder; parent session markers. | Denial, interruption model, result/save retry, orphan-file lifecycle tests. | Real microphone, route changes, interruption, and file playback. |
| Rhythm Accuracy | Shared microphone; silent visual/haptic pulse by default; deterministic onset scoring. | Permission denial, insufficient input distinction, synthetic onset tests, recovery/save error. | Latency calibration and headphone-only audible pulse. |
| Intonation | Waits for listening-ready; shared tuner; corrected pattern mapping and deterministic pitch scoring. | Permission/no-signal/recovery/save error, synthetic pitch streams, reference-frequency tests. | Real instrument/noise conditions and reference tone routes. |
| Metronome | Shared audio owner; active-session context; full-surface toggle. | Replace/stop behavior and recovered/save-error fixture coverage. | Speaker/headphone/interruption behavior. |
| Tuner | Shared audio owner; listening/reference tone lifecycle; active-session context. | Stop-on-exit, permission/recovery/error coverage. | Real microphone/reference tone coexistence. |

## Current visual audit findings and disposition

1. **Today, light — healthy.** Editorial hierarchy, dominant practice action,
   opaque content surfaces, and Dock separation are coherent.
2. **Quest, light — healthy.** The path is constrained to the viewport and
   featured quest nodes remain actionable; no Avatar Studio or duplicate Duel
   Arena ownership appears.
3. **Community, light — healthy.** Feed-first hierarchy, header actions, opaque
   social surfaces, and relationship summaries are consistent.
4. **You, light — corrected.** Deterministic launches previously accumulated
   six starter plants through persisted AppStorage. QA launch state now resets
   the starter loadout, leaving the room bare while retaining the separately
   rendered avatar.
5. **Warm-up active, light — corrected.** The live tool showed `0:12` while the
   Dock showed `0:00`. Standalone QA tool state now advances the canonical
   practice clock; the screenshot and UI assertion show both at `0:12`.
6. **Rhythm permission denied, dark — healthy.** Recovery is explicit, readable,
   and uses a true dark semantic surface.
7. **History, light — healthy.** Filters, metrics, trend/timeline hierarchy, and
   opaque content surfaces follow Studio Quest.
8. **Settings, accessibility dark — healthy within screenshot limits.** No
   visible horizontal overflow or mixed-appearance component was found.

Screenshots cannot prove VoiceOver speech order, physical microphone accuracy,
audio-session route behavior, APNs, ActivityKit/Dynamic Island, Family Controls,
StoreKit sandbox, or production Firebase authorization. Those claims remain
open until their dedicated device/production evidence is recorded.

## Completion-standard disposition

| Completion requirement | Disposition |
|---|---|
| Every practice tool is visually native to Studio Quest | **Verified** |
| One coherent runtime; no concurrent timer/audio conflict | **Verified by unit/UI tests; device interruption evidence pending** |
| Tool lifecycle and failure-state tests | **Verified** |
| Persistence errors visible and recoverable | **Verified** |
| Every visible control has a tested result | **Verified for the reachable interaction inventory; external system actions remain device/TestFlight gates** |
| Empty room/avatar/decorations architecture | **Verified** |
| Relationship-aware Community and profiles | **Verified** |
| Firebase rules, Functions, indexes, App Check, emulator tests production-ready | **Implemented and tested; rules/App Check rollout intentionally staged** |
| Advertising code removed | **Verified** |
| Both app test targets green | **Verified: 63/63 + 30/30** |
| Physical-device practice, audio, Live Activity, Family Controls, APNs, StoreKit | **Not yet verified** |
| No P0/P1/P2 defect remains | **No known simulator P0/P1/P2; device/TestFlight verdict pending** |

## Required next actions

1. Restore App Store Connect provider authentication or use an App Store
   Connect API key, then upload the source-exact build-31 archive.
2. Connect and unlock a physical iPhone and run the complete device checklist.
3. Confirm the monthly Pro price and legacy Ad-Free sale/availability policy,
   then create/configure the new monthly Pro product.
4. Confirm the monitored legal/support email and approve review/merge/deployment
   of the v2 legal-site branch.
5. Register DeviceCheck, generate legitimate TestFlight/device App Check
   traffic, observe metrics, and only then enable enforcement.
6. Coordinate the owner-only Firestore rules with the v2 client cutover.
7. Run internal and focused external TestFlight migration testing.
8. Fix any device/TestFlight P0–P2 defect, capture final deterministic App Store
   screenshots, publish metadata, and submit with the `PracticeBuddy` scheme.
