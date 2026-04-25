# Live Activity Extension Setup (One-Time Xcode Step)

Live Activity manager code is already in app target, but lock-screen rendering requires a Widget Extension target.

## Steps

1. Open `/Users/nica/Downloads/Apps/PracticeBuddy/PracticeBuddy/PracticeBuddy.xcodeproj` in Xcode.
2. `File` -> `New` -> `Target...`
3. Choose `Widget Extension`.
4. Product Name: `PracticeBuddyLiveActivity`
5. Check `Include Live Activity`.
6. Language: `Swift`, Interface: `SwiftUI`.
7. When created, remove auto-generated widget files from the new target and add these files instead:
   - `/Users/nica/Downloads/Apps/PracticeBuddy/PracticeBuddy/PracticeBuddyLiveActivity/PracticeBuddyLiveActivityBundle.swift`
   - `/Users/nica/Downloads/Apps/PracticeBuddy/PracticeBuddy/PracticeBuddyLiveActivity/PracticeTimerLiveActivityWidget.swift`
   - `/Users/nica/Downloads/Apps/PracticeBuddy/PracticeBuddy/PracticeBuddy/Shared/PracticeLiveActivityAttributes.swift`
8. Ensure `PracticeLiveActivityAttributes.swift` is in BOTH targets:
   - `PracticeBuddy` (app target)
   - `PracticeBuddyLiveActivityExtension` (widget extension target)
9. Build and run on physical iPhone (Live Activities don’t always behave exactly like device on simulator).

## Expected behavior

- Start timer or session in Practice tab -> Live Activity appears on lock screen.
- While running, it updates elapsed/remaining context.
- Stop/pause/save -> Live Activity ends.

