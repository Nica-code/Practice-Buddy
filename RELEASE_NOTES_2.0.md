# PractiQuest 2.0 — Studio Quest

## App Store release notes

PractiQuest has been rebuilt around one simple idea: start meaningful practice
faster.

- Start or resume from the new Practice Dock anywhere in the app.
- Stay focused in a calmer Practice Studio with verification, reflection,
  metronome, tuner, and a rebuilt Practice Library.
- Use redesigned Warm-up, Smart Loop, guided practice, Run-through, Rhythm, and
  Intonation tools that stay synchronized with your session.
- Follow a visual Quest journey, collect rewards, and compete in fair duels and
  leagues.
- Practice alongside trusted musicians through generated Practice Moments,
  private connections, requests, and messages.
- Make your space yours with an independently rendered musician avatar, empty
  studio rooms, and decorations you can place yourself.
- Review dedicated Goals, History, achievements, profile, Pro, and Settings
  experiences.
- Enjoy a unified premium design in true light and dark appearances, with
  improved accessibility and complete Korean and Romanian localization.

Your existing practice history, notes, XP, rating, tokens, inventory, purchases,
friends, messages, notification preferences, and avatar identity are preserved.

## Internal release facts

- Version/build: 2.0.0 (31)
- Scheme to archive: `PracticeBuddy`
- Bundle ID: `com.alexmalaimare.practicebuddy`
- Runtime v1 fallback: none
- Public Explore at initial launch: off
- Advertising: none
- Current Pro SKU: `com.alexmalaimare.practiquest.pro.monthly`
- Legacy recognized SKU: `com.alexmalaimare.practicebuddy.adfree.monthly`
- Paid-access authority: verified StoreKit 2 current entitlements
- Trial authority: App Check callable/server state

## Verified baseline

- 57/57 unit tests
- 30/30 UI tests
- 10/10 Firebase emulator/rules tests
- Korean and Romanian: complete coverage for 779 extracted source keys

## Migration requirements

- Map legacy tab state into Today, Quest, Community, or You.
- Preserve each top-level typed navigation path.
- Migrate legacy avatar IDs into versioned loadouts and keep compatibility
  writing during the migration window.
- Preserve SwiftData sessions, reflections, specialized tool logs, XP, rating,
  tokens, inventory, quests, friends, messages, notifications, and preferences.
- Recognize legacy Ad-Free owners as Pro.
- Require permanent legacy accounts with old profile schema to complete the
  identity upgrade, while retaining offline private practice.

## Privacy and safety

- Analytics are bounded and content-free.
- Coarse friend activity contains only last-practice timing and can be disabled.
- Practice Moments contain no photos, video, audio, captions, comments, notes,
  or reflections.
- Public/private account data is separated.
- Age-band restrictions, blocks, reports, relationship access, and Moment
  audience are server enforced.
- Client mutations use App Check V2 callables.

## Submission gates

1. Create and review the current Pro product in App Store Connect.
2. Execute `Docs/FIREBASE_DEPLOYMENT_RUNBOOK.md`.
3. Complete `Docs/PHYSICAL_DEVICE_RELEASE_CHECKLIST.md`.
4. Run internal and external focused TestFlight migrations.
5. Fix every P0, P1, and P2 defect.
6. Capture final screenshots from deterministic release states.
7. Update privacy, age, moderation/support, terms, and release metadata.
8. Archive the `PracticeBuddy` scheme, never the Live Activity extension.
