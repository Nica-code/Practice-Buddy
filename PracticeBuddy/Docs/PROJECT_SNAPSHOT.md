PracticeBuddy — Project Snapshot (Day 8)

Purpose

PracticeBuddy is an iOS + iPadOS app to help violinists practice better by tracking practice time, sessions, and notes, with simple goals and streaks. The app includes a theming + typography system to make the UI feel slick, clean, and “music-inspired.”

Day 8 focus: add a Home metronome in a new Practice Tools section, fix metronome runtime crash, and expand metronome controls (pulse/subdivision/sound style).

⸻

Persistent Rule (Applies to Every Coding Day)

Full-file code rule: Whenever we make changes, ChatGPT must always provide the FULL updated code for every file that needs to be changed (copy-paste ready), not just snippets/diffs.
If a new file must be created, ChatGPT must provide the FULL contents of the new file and the exact path where it should be created.
If a file does not need changes, ChatGPT should not rewrite it.

⸻

Environment
    •    macOS: 26.2 (Build 25C56)
    •    Xcode: 26.2 (Build 17C52)
    •    Runs on: iPhone + iPad (Universal; tested on simulator + real device)
    •    UI: SwiftUI
    •    Language: Swift
    •    Persistence: SwiftData

⸻

Current State (What Works)

App Navigation
    •    Main navigation is a bottom Tab Bar:
    •    Home
    •    History
    •    Buddies (formerly Friends)
    •    Settings
    •    Each tab is wrapped in its own NavigationStack.
    •    Lazy tab initialization enabled via PBLazyView to avoid building all tabs at launch.

Minimalist Navigation Bar
    •    All top navigation titles are removed (blank titles) for a clean minimalist look.
    •    Back buttons, search, toolbar actions still work, but titles don’t show.

⸻

Day 7 Changes / Improvements

1) Theme Consistency (Minimal Model)
    •    All 4 themes now share the same background/surface/text behavior as Classic.
    •    The only per-theme visual difference is accent color, applied consistently in the same places as Classic.
    •    Objective: maximum readability + consistent look across tabs in light/dark.

2) Tab Bar Styling Stability (Dark/Light Consistency)
    •    The tab bar appearance updates reliably when switching between Light/Dark/System.
    •    Avoided .id(colorScheme) view rebuilds (which previously caused scroll position jumps).
    •    Uses PBTabBarStyle.apply(...) + refresh of visible tab bars to force UIKit appearance update.

3) Settings UX Polish
    •    Added/kept a Store entry in Settings that opens a “Coming Soon” screen (future feature unlocks placeholder).
    •    Added an About section (version + developer info + email + website links).
    •    Email/Website displayed as two pill buttons side-by-side:
    •    Email opens the default mail client (works on device; Simulator can fail).
    •    Website opens default browser.

4) Keep History Picker Behavior (Exactly as requested)
    •    In the selection list (the sheet/page with options):
    •    “Unlimited” and all numbers display in primary color.
    •    In Settings row display:
    •    “Unlimited” shows as primary
    •    Numbers show as secondary

5) Navigation Title Flicker Fix
    •    Fixed the Settings title disappearing/flickering issue by removing toolbar/nav background overrides in Settings (a known SwiftUI + Form issue).
    •    Settings now stays visually stable.

6) Home Title Copy Update
    •    Home hero title changed:
    •    “Practice Buddy” → “Let’s Practice!”

7) Friends → Buddies Rename (User-Facing Copy)
    •    Tab label changed to Buddies.
    •    FriendsView user-facing text updated:
    •    “friends” → “buddies” in the UI copy (while still using Game Center friends internally).

8) Leaderboards Toggle Clarity
    •    Leaderboard scope toggle now displays:
    •    Buddies (ON)
    •    Global (OFF)
    •    Still powered by Game Center leaderboard scopes (friends vs global).

9) History Chrome Background Alignment
    •    History uses the same “chrome background” approach as other tabs for consistent safe-area/background behavior.

⸻

Day 8 Changes / Improvements

1) Home “Practice Tools” Section Added
    •    Added a new section on Home called Practice Tools.
    •    Includes a metronome tool integrated into the existing List/Form visual style.
    •    Uses existing typography/theme tokens so it matches the rest of the app.

2) Metronome Controls (Initial + Expanded)
    •    Start/Stop metronome controls on Home.
    •    BPM control via slider (40–220 BPM), persisted in AppStorage.
    •    Time signature picker: 2/4, 3/4, 4/4, 6/8, persisted in AppStorage.
    •    Subdivision picker added:
    •    Quarter
    •    8th
    •    Triplet
    •    16th
    •    Sound style picker added:
    •    Click
    •    Wood
    •    Beep

3) Visual Beat Pulse
    •    Added a pulse indicator in the metronome row.
    •    Pulse is synced to beat boundaries to give visual timing feedback.
    •    Uses lightweight scale animation and existing accent color.

4) Metronome Audio Engine + Crash Fix
    •    Implemented metronome engine with AVFoundation.
    •    Added accented downbeat + normal beat + lighter subdivision tick.
    •    Fixed runtime crash that occurred when pressing Start (AVAudioPlayerNode scheduleBuffer exception).
    •    Crash fix included:
    •    safer AVAudioEngine/player format setup
    •    format-aligned buffer generation
    •    safer scheduleBuffer usage
    •    configuration refresh flow for sound style/subdivision updates

5) Lifecycle + Persistence Behavior
    •    Metronome stops when Home disappears to avoid unexpected background ticking while navigating tabs.
    •    Metronome settings persist:
    •    BPM
    •    beats per bar (time signature)
    •    subdivision
    •    sound style

6) Build Verification
    •    Verified project builds successfully after metronome additions and crash fix.
    •    xcodebuild (iOS Simulator, CODE_SIGNING_ALLOWED=NO): BUILD SUCCEEDED

⸻

New / Notable Files (Day 8)
    •    PracticeBuddy/Features/Home/HomeView.swift (Practice Tools + metronome UI + metronome engine + crash fix)

New / Notable Files (Day 7)
    •    PracticeBuddy/Features/Settings/StoreView.swift (Store placeholder “Coming Soon”)
    •    PracticeBuddy/Settings/HistoryRetentionPickerView.swift (custom Keep History picker behavior)

(About section view exists and is in Settings — includes pill buttons for Email/Website.)

⸻

Project Structure (Current)
    •    App
    •    Docs
    •    Features (Friends, History, Home, Onboarding, Practice, Settings)
    •    Models
    •    Services (Export, Social)
    •    SharedUI
    •    Assets
    •    PracticeBuddy entitlements file

(Models folder should remain at top-level alongside Features/Services/SharedUI.)

⸻

Known Limitations / Notes
    •    Email mailto: may fail in the Simulator (expected). Works properly on a real device with a configured mail client.
    •    Game Center leaderboards may show “application not recognized” until App Store Connect Game Center setup + TestFlight build exists.
    •    Store is a placeholder (“Coming Soon”) for post-launch feature unlocks.
    •    Metronome timing is timer-driven for now (good for MVP/UI integration, but not sample-accurate at pro-audio precision).
    •    Metronome currently lives in HomeView (can be moved into a dedicated service/file if we want stricter separation later).

⸻

Where We Stopped (End of Day 8)
    •    UI looks consistent across themes and appearance modes.
    •    Minimalist navigation (no top titles) applied across the app.
    •    Buddies tab rename + copy updates complete.
    •    Keep History picker behaves exactly as specified.
    •    Store placeholder view restored and accessible.
    •    Settings nav title flicker resolved.
    •    Home now includes a Practice Tools section with a working metronome.
    •    Metronome crash on Start was fixed.
    •    Pulse animation, subdivisions, and sound styles are implemented.
