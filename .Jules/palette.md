## 2025-05-15 - Dual-Coding Status Signals and Consolidated Screen Reader Semantics

**Learning:** In dark-themed financial interfaces, recommendation cards (e.g. Buy vs Wait) that rely primarily on color coding (green/red background and border) violate WCAG 1.4.1 (Use of Color) and force screen reader users to navigate multiple fragmented text and fact chips before understanding the recommendation.
**Action:** Pair recommendation titles with clear status iconography (`Icons.trending_up_rounded` and `Icons.pause_circle_outline_rounded`) and wrap complex decision cards in a parent `Semantics(container: true, label: ...)` providing a single coherent summary for assistive technology.
