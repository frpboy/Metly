## 2026-11-10 - Feedback Form State Reset & Autofill

**Learning:** When forms provide optional fields (like contact email alongside a message textarea), partial resets after submission (e.g. only resetting the message body) create confusing UX where users aren't sure whether their form was fully submitted or retained, while on-screen soft keyboards can obscure floating snackbar notifications unless dismissed.
**Action:** Always dismiss active input focus with `FocusScope.of(context).unfocus()`, clear all form fields upon successful submit, and provide standard `autofillHints` (e.g., `AutofillHints.email`) for keyboard / password manager accessibility.
