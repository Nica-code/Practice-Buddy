# Claude Instructions for PractiQuest Development

## Between-Session Continuity

**When starting a new chat:**
1. Read `PROJECT_STATE.md` for the current development state
2. Refer to memory files for user/project context
3. Don't re-scan the entire codebase unless necessary
4. Ask the user for clarification if state file is stale

**When ending a session:**
- Claude will automatically update `PROJECT_STATE.md` with completed work
- Claude will commit changes and push to GitHub branch `codex/launch-hardening`
- User says "Done for today" to trigger this workflow

---

## Core Principles

### 1. No Breaking Changes
- **Always verify**: Any change must preserve or improve functionality
- **Test-first mindset**: Understand behavior before changing it
- **Build must remain green**: Never commit code that doesn't compile
- **Document intentional patterns**: Keep gotchas and design decisions in PROJECT_STATE.md

### 2. Safety First
- Ask before making destructive changes (deletions, refactors of large files)
- Respect existing architecture (e.g., don't decompose large SwiftUI Views without explicit approval)
- Verify error handling is in place; never add silent `try?` without logging
- Check for crash risks (Dictionary uniqueKey assumptions, force unwraps, etc.)

### 3. Efficient Development
- Use targeted edits, not full file rewrites
- Reference existing code patterns (don't reinvent utilities)
- Keep UI polish separate from feature work
- Batch related changes together

---

## Project Context

### What is PractiQuest?
Music practice companion iOS app with:
- Customizable warm-up routines
- Real-time duel ladder
- Global leaderboards
- Friend requests & direct messaging
- Practice session tracking with metrics
- Ad-free subscription ($X.99/month via App Store)

### Tech Stack
- **Frontend**: SwiftUI + SwiftData
- **Backend**: Firebase Firestore + Authentication
- **Ads**: Google AdMob
- **Payments**: Apple In-App Purchase (subscription)

### Key Files to Know
- `Info.plist` — App configuration, privacy keys
- `PBLayout.swift` — Spacing/sizing constants (padXS=8, padSM=12, etc.)
- `PBTheme.swift` — Color palette, theme support
- `PBTypography.swift` — Font system
- `Features/` — View layer organized by feature (Home, Studio, Social, History, etc.)
- `Services/` — Business logic (Firebase, SwiftData, JourneyProgressManager, etc.)

### Design System
- Use `PBLayout` constants for spacing (never magic numbers like `8`, `12`, etc.)
- Use `palette.*` for colors (never hardcoded unless semantically intentional)
- Font styles from `type.*` (body, sectionTitle, button, etc.)
- Haptics via `PBHaptics.tap()`, `PBHaptics.success()`, etc.

---

## Common Workflows

### Adding a New Feature
1. **Plan first**: Sketch out Views, data flow, and Firebase schema changes
2. **Build bottom-up**: Services/data layer → ViewModels → Views
3. **Test as you go**: Verify build at each step
4. **Polish**: Spacing, colors, animations (once functionality is solid)
5. **Commit**: One feature = one logical commit

### Fixing a Bug
1. **Reproduce**: Understand the exact failure scenario
2. **Root cause**: Is it logic, state management, or UI?
3. **Minimal fix**: Change only what's necessary
4. **Verify**: Build + test the fix
5. **Commit**: Include bug description in commit message

### App Store Submission
1. **Verify**: All Rights & Certificates questionnaire answered
2. **Check**: Info.plist has required privacy keys
3. **Confirm**: PrivacyInfo.xcprivacy is present and accurate
4. **Build**: Archive in Release configuration
5. **Upload**: To App Store Connect
6. **Submit**: Click "Add for Review"

---

## Known Gotchas (Don't Change These)

### Intentional Patterns
- **`ITSAppUsesNonExemptEncryption: false`** — Correct; encryption is TLS only, not app APIs
- **Green dot for "online" status** — Intentionally universal color, not theme accent
- **Orange for warnings** — Semantic color, preserved across themes
- **`setData(merge: true)` in Firestore** — Performance optimization; don't revert to read-before-write
- **`try?` in fire-and-forget tasks** — Intentional; errors logged separately

### Crash Risks Fixed
- **Dictionary(uniqueKeysWithValues:)** — Replaced with `reduce(into:)` in JourneyProgressManager, StudioChatViewModel (2 locations)
- **Silent error swallowing** — HistoryView saves, Firestore inventory sync now have error logging

### Complex Areas (Approach Carefully)
- **TunerEngine**: `Task { @MainActor in }` wrapper is NOT removable (runs on AVAudio callback thread)
- **Large Views** (HomeView 1500+, JourneyView 2000+, HistoryView 2000+): Don't decompose without testing
- **Firebase init**: Uses `didInit` flags + `currentUID` checks; changing to `.task` risks double-init

---

## Code Quality Standards

### Logging
- Use `PBLog.sessionStore`, `PBLog.firebase`, `PBLog.ui`, `PBLog.export`, `PBLog.gamecenter`
- Always log errors; never silent `try?` without fallback logging
- Format: `PBLog.*.error("Description: \(error.localizedDescription, privacy: .public)")`

### Error Handling
- Prefer `do/catch` over `try?` for visibility
- Add user-facing feedback for critical errors (alerts, status messages)
- Fire-and-forget tasks can use `try?` if logged separately

### Naming
- SwiftUI Views: PascalCase, suffix with `View` (e.g., `SocialChatThreadView`)
- ViewModels: PascalCase, suffix with `ViewModel` (e.g., `StudioChatViewModel`)
- Services: CamelCase, describe function (e.g., `sendFriendMessage`)
- Constants: CamelCase (e.g., `padXS`, `radiusCard`)

### Comments
- Explain *why*, not *what* (code shows the what)
- Mark hacks with `// HACK:` and include issue tracker reference if available
- Mark performance-critical sections with `// PERFORMANCE:` note

---

## Git Workflow

### Branch Strategy
- **Main branch**: Production-ready code
- **codex/launch-hardening**: Pre-launch polish & hardening
- **Feature branches**: Off `codex/launch-hardening` for new features

### Commit Messages
- **Format**: `[Category] Brief description`
- **Examples**:
  - `[Fix] Replace Dictionary(uniqueKeysWithValues:) crash risk with reduce(into:)`
  - `[Polish] Add NSUserTrackingUsageDescription to Info.plist for App Store`
  - `[Feature] Add push notifications for friend requests`
- **Include context**: What was broken/why this change matters

### At End of Session
- Claude automatically updates `PROJECT_STATE.md`
- Claude commits all changes with descriptive message
- Claude pushes to current branch on GitHub

---

## Testing Checklist

Before committing:
- [ ] `xcodebuild` → `BUILD SUCCEEDED` (no warnings)
- [ ] Simulator launches without crashes
- [ ] Feature/fix works as intended
- [ ] No regressions in related features
- [ ] UX is polished (spacing, colors, animations)

For major features:
- [ ] Test on multiple screen sizes (SE, regular, Plus)
- [ ] Test iPad support (if applicable)
- [ ] Test light & dark modes
- [ ] Test with slow network (Firebase delay simulation)

---

## Resources & References

**Firebase Documentation**:
- Firestore: `https://firebase.google.com/docs/firestore`
- Auth: `https://firebase.google.com/docs/auth`

**SwiftUI & iOS**:
- Apple Developer: `https://developer.apple.com/documentation`
- SwiftUI Essentials: `https://developer.apple.com/tutorials/SwiftUI`

**App Store**:
- App Store Connect: `https://appstoreconnect.apple.com`
- Review Guidelines: `https://developer.apple.com/app-store/review/guidelines`
- Privacy & Security: `https://developer.apple.com/privacy`

**Project-Specific**:
- GitHub: `https://github.com/Nica-code/Practice-Buddy.git`
- App Store Bundle ID: `com.alexmalaimare.practicebuddy`
- Google Cloud Console: [Firebase project settings]

---

## Questions for Nica

Feel free to add context here about decisions you want preserved:
- [Any specific architectural choices to protect]
- [Features you're planning for v1.1]
- [Performance concerns to monitor]
