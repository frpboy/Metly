# Palette's Journal - Critical Learnings Only

## 2026-03-31 - Semantic Labels for Flutter Image Assets
**Learning:** In Flutter, `Image.asset` without `semanticLabel` is treated as purely decorative or unannounced to assistive tech like TalkBack/VoiceOver, leaving critical branding and informative logo images invisible to screen readers.
**Action:** Always provide `semanticLabel` on `Image.asset` and `Image.network` when the image carries informative or navigational brand context, and verify with `find.bySemanticsLabel(...)` in widget tests.
