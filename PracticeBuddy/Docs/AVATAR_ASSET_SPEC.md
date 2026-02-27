Avatar Full-Body Asset Spec (Phase 1A Scaffold)

Purpose
- This spec defines how to add full-body avatar art so the app automatically renders character images instead of fallback symbol circles.

How Rendering Works
- The app looks up a full-body image asset for each avatar ID using this mapping:
  - `avatar_<key>` -> `avatar_full_<key>`
- Example:
  - avatar ID: `avatar_note`
  - expected image asset name: `avatar_full_note`
- If asset is missing, the app falls back to SF Symbol avatar rendering.

Current Avatar IDs
- `avatar_note` -> `avatar_full_note`
- `avatar_violin` -> `avatar_full_violin`
- `avatar_mic` -> `avatar_full_mic`
- `avatar_headphones` -> `avatar_full_headphones`
- `avatar_star` -> `avatar_full_star`
- `avatar_wave` -> `avatar_full_wave`
- `avatar_bolt` -> `avatar_full_bolt`
- `avatar_leaf` -> `avatar_full_leaf`
- `avatar_f_piano` -> `avatar_full_f_piano`
- `avatar_m_guitar` -> `avatar_full_m_guitar`
- `avatar_f_teacher` -> `avatar_full_f_teacher`
- `avatar_m_coach` -> `avatar_full_m_coach`

Asset Creation Guidelines
- Place images in `Assets.xcassets` as image sets with the exact names above.
- Format:
  - PNG with transparent background preferred
  - 1:1 canvas
  - 1024x1024 source recommended (scales well down to small avatar sizes)
- Framing:
  - full-body character centered
  - keep padding around edges (~8-10%) to avoid clipping in rounded avatar frame
- Style consistency:
  - similar line weight/shading across characters
  - similar visual height so characters feel balanced in grids/cards

Testing Checklist
- Open Profile -> Personalize and verify each avatar renders full-body art.
- Check smaller avatar contexts:
  - Social friends list
  - Play ladder/profile chips
  - Public profile
- Confirm fallback still works if one asset is intentionally removed.
