# Palette's Journal - Critical UX Learnings

## 2026-11-06 - Clear affordances and accessibility on multi-line text inputs
**Learning:** In Flutter multi-line `TextFormField` components, users often make drafts or paste content they wish to clear easily. Providing a conditional `suffixIcon` with an `IconButton` gives immediate feedback and control, but icon-only buttons on input fields must provide a descriptive `tooltip` (e.g. `tooltip: 'Clear message'`) so screen readers announce semantic action labels instead of generic icons.
**Action:** When adding quick-action icon buttons or suffix icons inside text form fields, always ensure descriptive tooltips and semantic labels are configured so screen readers and keyboard users can easily identify and activate them.
