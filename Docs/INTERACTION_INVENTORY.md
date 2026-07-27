# PractiQuest 2.0 Interaction Inventory

This document is the parity contract for the reachable Studio Quest interface. A
surface is complete only when its entire visible shape is tappable, its enabled
state is truthful, and its result is covered by a unit or UI test. Dynamic
collections use one contract per row type rather than one entry per database row.

## Global navigation

| Surface | Identifier or route | Result | Failure/disabled behavior | Automated coverage |
| --- | --- | --- | --- | --- |
| Today tab | `AppDestination.today` | Preserves Today navigation path | Never disabled | Shell UI test |
| Quest tab | `AppDestination.quest` | Preserves Quest navigation path | Never disabled | Shell UI test |
| Community tab | `AppDestination.community` | Preserves Community navigation path | Account gate remains in content | Shell UI test |
| You tab | `AppDestination.you` | Preserves You navigation path | Never disabled | Shell UI test |
| Practice Dock | Coordinator-owned state | Opens setup, starts/resumes a session, or restores the active tool | Replacement confirmation for incompatible activity | Coordinator unit tests and tool UI tests |
| Notification/deep link | Typed `AppRoute` payload | Replaces the exact owning tab path once | Unsupported payload is ignored and logged | Router unit tests |
| Practice URL | `practicebuddy://practice` | Starts the coordinator even for an anonymous user | Invalid custom routes are ignored | Incoming-link parser tests |
| Friend invite URL | custom or trusted `/invite?code=` URL | Sends immediately for a permanent account or retains the code through account linking | Invalid code/untrusted host is rejected; failed request remains retryable | Incoming-link parser tests |

## Today and practice

| Surface | Identifier | Result | Failure/disabled behavior | Automated coverage |
| --- | --- | --- | --- | --- |
| Next Practice | `today.startPractice` | Starts the recommended/last-used session | Coordinator presents recovery or save error | Today UI test |
| Practice setup | `today.setupPractice` | Opens typed setup route | Never decorative | Today UI test |
| Smart Coach | `today.smartCoach` | Opens Smart Coach | Pro state explains limits before action | Today UI test |
| Library tool card | `library.tool.<id>` | Opens or attaches the exact tool | Capability conflicts show replace/cancel | Library and tool UI tests |
| Library scope | `library.scope.<scope>` | Filters without losing search/favorites | Empty state explains filter | Library UI coverage |
| Metronome | `metronome.toggle`, `metronome.finish` | Acquires/releases shared playback ownership | Audio failure is visible | Metronome UI and audio-owner unit tests |
| Tuner | `tuner.toggle`, `tuner.reference`, `tuner.finish` | Acquires/releases tuner/reference ownership | Permission and route errors are visible | Tuner UI and audio-owner unit tests |
| Warm-up | `warmup.*` | Setup → timed sequence → transactional save | Empty, recovery, and retry-save states | Warm-up UI/runtime tests |
| Smart Loop | `smartloop.*` | Setup → work/rest loops → result/save | Pro preset limit explains lock; save can retry | Smart Loop UI/runtime tests |
| Guided practice | `guided.*` | Plan → Execute → private Reflect → save | Nested tools preserve parent clock | Guided-practice UI/runtime tests |
| Run-through | `runthrough.*` | Permission → count-in → recording → review/save | Cancel/failure deletes orphan file | Run-through UI/file tests |
| Rhythm | `rhythm.*` | Calibration/count-in → take → analysis/save | Denied/no-signal/interrupted states explain recovery | Rhythm UI/scoring tests |
| Intonation | `intonation.*` | Listening-ready → take → note analysis/save | Denied/no-signal/interrupted states explain recovery | Intonation UI/scoring tests |

## Quest and competition

| Surface | Route | Result | Failure/disabled behavior | Automated coverage |
| --- | --- | --- | --- | --- |
| Featured node | `.questDetail(QuestPresentation)` | Opens objective, progress, reward, and one CTA | Locked node explains prerequisite | Featured-node UI test |
| Quest CTA | Typed practice launch context | Starts/attaches the exact practice activity | Progress is awarded only after committed save | Quest attribution unit tests |
| Reward card | Quest reward ID | Collects once and updates balance/inventory | Already-collected state is non-actionable | Quest persistence tests |
| Duels & Leagues | `.duelArena(challengeID:)` | Opens queue, invite, active match, result, history, or league | Offline/permission/failure state is explicit | Route and duel lifecycle tests |

## Community

| Surface | Identifier or route | Result | Failure/disabled behavior | Automated coverage |
| --- | --- | --- | --- | --- |
| Search header | `.peopleSearch(query:)` | Opens people search | Permanent profile required | Route test |
| Messages header | `.communityMessages(friendUID:threadID:)` | Opens inbox or exact thread | Accepted friends only | Exact-chat UI test |
| Your circle | `community.connections` | Opens Connections | Permanent profile required | Community fixture UI test |
| Friend pill | Full `StudioQuestInteractiveSurface` | Opens Message/Profile/Duel/Remove chooser | Actions reflect current relationship | Full-pill UI test |
| Share friend invite | Profile row or Connections sheet | Opens the native share sheet with a validated Universal Link | Hidden when no valid owned code exists | Invite URL unit tests and secondary-route coverage |
| Connection profile area | Full leading row surface | Opens exact public profile | Trailing relationship buttons remain independent | Relationship UI tests |
| Follow actions | `profile.follow`, `profile.unfollow`, `profile.cancelFollowRequest`, `profile.followBack` | Mutates server-authoritative relationship and refreshes in place | Loading disables repeat; failure is retryable | Relationship UI tests |
| Friend actions | `profile.acceptFriend`, `profile.declineFriend`, `profile.message`, `profile.duel` | Accept/decline or route to exact eligible feature | Messaging/duel only appears for accepted friends | Relationship UI tests |
| Block action | `profile.unblock` and More menu | Blocks/unblocks and updates visible state | Server error remains visible | Relationship UI test |
| Moment author | `.publicProfile(userID:)` | Opens exact author | Missing profile has retry/unavailable state | Route test |
| Moment artwork | `.practiceMoment(momentID:)` | Opens exact generated Moment | Expired/deleted Moment shows unavailable state | Moment lifecycle tests |
| Reaction chip | Reaction enum | Creates/replaces one bounded reaction | Failure is visible; no arbitrary content | Moment repository tests |

## You and secondary destinations

| Surface | Route | Result | Failure/disabled behavior | Automated coverage |
| --- | --- | --- | --- | --- |
| Edit profile | `.profile(userID:nil)` | Edits identity and public projection | Validation and server errors stay inline | Secondary-route UI test |
| Avatar room | Room editor presentation | Enters drag or accessible placement mode | Locked inventory cannot be placed | Room editor tests |
| Avatar Studio | `.avatarStudio(section:)` | Customize or Collection | Incompatible/locked items explain state | You route test |
| Shop | `.shop` | Opens cosmetic catalog | No ad path; Pro/price state explicit | Shop route/entitlement tests |
| Goals | `.goals` | Opens dedicated goals editor | Save/validation errors visible | You route test |
| History | `.history`, `.sessionDetail(sessionID:)` | Filters timeline or opens exact session | Deleted session shows unavailable; export explains Pro | You route test |
| Pro | `.pro(source:)` | Opens source-aware entitlement screen | Purchase/restore failures visible | Entitlement tests |
| Start Pro trial | `entitlementTrialV2` | Claims server-authoritative one-time trial | Permanent account and App Check required; failure stays visible | Entitlement callable unit tests |
| Purchase/restore | Verified StoreKit 2 transaction | Grants current or legacy Pro access | Cached/client-submitted identifiers cannot grant access | Entitlement policy tests |
| Settings | `.settings(section:)` | Opens exact section | Destructive actions require consequence confirmation | You route test |

## Release audit

The source audit counts `Button`, `NavigationLink`,
`StudioQuestInteractiveSurface`, menus, gestures, sheets, and incoming routes in
reachable Studio Quest files. Before release:

1. Every new interactive surface receives an identifier when the outcome is
   business-critical or stateful.
2. A gesture may not wrap child buttons; profile/content areas and trailing
   actions are separate controls.
3. A visually button-like surface may not be decorative.
4. All save actions expose loading, committed success, and retryable failure.
5. All destructive actions explain local and cloud consequences.
6. The complete 57-unit/30-UI suite, accessibility matrix, Firebase rules suite,
   and physical-device checklist must pass before this inventory is signed off.
