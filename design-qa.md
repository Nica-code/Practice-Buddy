# PractiQuest 2.0 — Studio Quest Design QA

Updated: 2026-07-27

## Comparison method

The approved direction and implementation were placed into combined boards at
matched device sizes. Screenshots were not graded in isolation.

Reference:

- `Design/StudioQuest2/QA/selected-direction.png`

Current combined evidence:

- `Design/StudioQuest2/QA/launch-quality-root-comparison.png`
- `Design/StudioQuest2/QA/launch-quality-compact-comparison.png`
- `Design/StudioQuest2/QA/launch-quality-promax-comparison.png`

One approved correction supersedes the older reference: room artwork is empty.
The user avatar and every optional decoration are rendered as separate runtime
layers.

## Current simulator finding

Within the deterministic simulator matrix:

- P0: none known.
- P1: none known.
- P2: none known.

This is not the final release sign-off. Physical-device, TestFlight, and
deployed-backend findings remain ungraded until their checklists run.

## Visual system checks

- Light and dark use equivalent geometry and semantic contrast.
- No dark lower control surface leaks into light Practice Studio.
- Content surfaces are opaque; glass/material is limited to navigation, Dock,
  and transient controls.
- Chat and message backgrounds are solid, not decorative gradients.
- Quest artwork is width-bounded and cannot expand the viewport.
- Dock height is measured and scroll pages provide final-item clearance.
- Full visible pills/cards/rows own their hit shape.
- Avatar Studio is only in You.
- Duels are owned only by Duels & Leagues.
- Profile editing is integrated into You rather than duplicated as a menu item.
- Space Grotesk uses real bundled faces; body copy stays system-native.
- Reachable practice tools no longer use the retired PBTheme/Form/List grammar.

## Root comparison notes

### Today

- One dominant practice action.
- Daily goal, Smart Coach, Next Quest, recent session, and community pulse are
  ordered with lower dashboard density than the original implementation.
- Idle Dock is compact and does not compete with the hero.

### Quest

- Journey and Duels & Leagues remain local sections without duplicate Arena
  cards.
- Featured nodes use one catalog and typed detail/CTA behavior.
- Reward presentation is anchored so it does not obscure node labels.

### Community

- Feed is the root.
- Search and Messages are the primary header actions.
- Connections appears as relationship context.
- Rows use whitespace, no chevrons/long dividers/filler copy, and full-pill
  actions.

### You

- Empty room, decorations, avatar, and foreground/lighting are independent.
- The runtime avatar occupies the intended human position.
- Identity, activity, achievements, Avatar Studio, Goals, History, Pro, and
  Settings remain reachable without making the hero a menu wall.

## Secondary and lifecycle checks

Deterministic routes cover:

- Practice setup/studio/library;
- every practice tool;
- permission denied, recovered, save-error, and completed tool states;
- Goals, History, session detail, profile, Settings, Pro;
- Duel Arena, Avatar Studio, room editing, Shop;
- feed, Connections, requests, messages, exact conversation, public profiles;
- loading, mandatory update, localization, and accessibility text.

## Automated verification

Latest exact run:

- `StudioQuestFoundationTests`: 58/58
- `StudioQuestNavigationUITests`: 30/30
- Firebase emulator/rules: 10/10
- Function contracts: 3/3

The UI suite includes:

- all top-level and secondary routes;
- full friend-pill interaction;
- featured quest nodes;
- public relationship states;
- every practice tool's core runtime;
- denied permission, recovery, and failed-save fixtures;
- room editor controls;
- Korean/Romanian launch reachability;
- pseudolocalization/accessibility text reachability.

## Localization and accessibility

- 779 extracted source keys.
- Korean missing: 0.
- Romanian missing: 0.
- Dynamic layouts use wrapping, `ViewThatFits`, or accessible alternatives.
- Important states include text/symbol information, not color alone.
- Reduce Motion gates parallax, particles, and nonessential motion.
- Non-drag room placement controls are present.

## Remaining release evidence

Before final sign-off:

1. execute `Docs/PHYSICAL_DEVICE_RELEASE_CHECKLIST.md`;
2. deploy through `Docs/FIREBASE_DEPLOYMENT_RUNBOOK.md`;
3. run internal and external focused TestFlight;
4. recapture final App Store images from the deployed release configuration;
5. close every device/TestFlight P0, P1, and P2.

Simulator/source QA result: passed.
Final release QA result: pending external gates.
