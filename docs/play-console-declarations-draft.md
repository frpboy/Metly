# Metly - Play Console declarations DRAFT (for Rahul's review; NOT submitted)

Prepared 2026-11-18 against repo main 27b8873f, verified live in the Firebase
console (read-only, account frpboy12@gmail.com) the same day. Items marked
[OWNER CONFIRM] cannot be answered from repo or console and need Rahul's
confirmation before submission. Nothing here has been entered into Play Console.

## App identity (recommendation; enrollment itself is a held owner action)
- Package: `com.k4nn4n.metly` - already the shipped applicationId in all three
  public preview releases and the public repo; the de-facto stable identity.
  Firebase console shows "No matching Play apps found" under Google Play
  integration, consistent with no linked Play app yet (not proof a Play
  Console app does not exist - creation state still to confirm at submission).
- Signing: release signingConfig = debug key in android/app/build.gradle.kts.
  Verified by certificate (not filename): the installable preview asset
  Metly-v1.0.0-build-101401-localdebugkey.apk is signed with the Android debug
  certificate (CN=Android Debug, SHA-256
  96:D8:0A:D6:54:04:17:BE:C4:DE:09:F6:00:B2:F3:E8:3C:7F:23:81:0A:A3:49:25:A1:B2:D3:D5:CF:14:91:87).
  The non-suffixed Metly-v1.0.0-build-101401.apk asset is UNSIGNED (no signer
  block) - never deliver that asset as installable.
  Recommendation: Google Play app signing (Play-managed app key) + generated
  upload keystore in the vault - same route as Seali; no new fee (Rahul's
  Play dev account already exists). CONSEQUENCE: a Play-signed build has a
  DIFFERENT signer, so existing debug-preview installs cannot upgrade in
  place - testers must UNINSTALL the preview build first. One-time cost, not
  a seamless upgrade. Signing enrollment decision itself stays held.

## Data safety (grounded in code + live console)
- Email address - COLLECTED: email+password sign-in via Firebase Auth
  (lib/screens/auth_screen.dart, lib/services/auth_service.dart; console shows
  Email/Password provider ENABLED). Purpose: account management.
  [OWNER CONFIRM: whether sign-in is mandatory or optional for core price
  viewing - affects the "required vs optional" answer.]
- Watchlist and portfolio entries - COLLECTED, stored per-user in Cloud
  Firestore users/{uid}/watchlist and users/{uid}/portfolio
  (lib/services/firestore_service.dart). Purpose: app functionality.
  Console: Firestore database provisioned; zero reads/writes/deletes in the
  last 7 days (usage tab) - backend live but no traffic yet.
- Feedback email + message - COLLECTED when the user submits feedback
  (lib/screens/feedback_screen.dart). Purpose: support.
- AI prompts - "Metly AI" mode sends prompts to the Metly Cloudflare proxy
  which calls OpenRouter; "Use My API" mode keeps the user's own OpenRouter
  key on-device only (SharedPreferences; lib/config/app_config.dart). AI can
  be turned OFF (AiMode.off).
- Analytics: NONE - Firebase console Integrations shows Google Analytics NOT
  enabled (only an "Enable" button); no analytics SDK in pubspec.yaml. No ads,
  no AdMob, no tracking SDKs.
- Price data - fetched via the app's own Vercel route
  https://metly-gold.vercel.app/api/prices backed by OroPocket's free API
  (verified live 2026-11-18: real Indian 24K gold/silver buy/sell INR rates,
  GST separate, stale:false). No personal data sent for prices.
- Encryption in transit: HTTPS throughout (dio; Firebase SDKs).
- Privacy policy URL: https://metly.frpboy.in/privacy (live, verified
  2026-11-18) - from the existing project-sites legal work.

## Content rating / audience
- Finance app, no gambling or simulated gambling visible in code.
  [OWNER CONFIRM via the Play IARC questionnaire.]

## F-Droid status (officially grounded; decision held)
- F-Droid Inclusion Policy (f-droid.org/en/docs/Inclusion_Policy, fetched
  2026-11-18): "proprietary tracking or advertising libraries and analytics
  tools such as Google Play Services and Firebase ... are strictly forbidden";
  upstream must "implement either a FLOSS alternative or a build flavour that
  does not require these dependencies".
- Metly's build includes firebase_core + firebase_auth + cloud_firestore
  (pubspec.yaml; Firebase.initializeApp in lib/main.dart), so it is NOT
  eligible for F-Droid as-is. The precise tradeoff (held for grounded review,
  NOT part of this prep): an `fdroid` build flavor that strips Firebase
  (watchlist/portfolio sync disabled or replaced) vs. deferring F-Droid.
  Even with a flavor, expect the Non-Free Network Services Anti-Feature flag
  (OpenRouter AI) - a flag, not an exclusion. License Apache-2.0 is FLOSS-fine.

## Open inconsistencies flagged (documentation hygiene, not blockers)
- README says prices are "currently mocked" - STALE: the app fetches real
  rates via the Vercel/OroPocket route (verified live).
- ACTION_ITEMS.md says prices come direct from gold-api.com - STALE in the
  other direction: the shipping code path is the Vercel proxy to OroPocket.
  README should be updated before public listing. (ACTION_ITEMS.md also
  contains operational checklists; it is a repo document, not an authority
  source - noted, not acted on.)
- README roadmap lists "Firebase: Initialize" as pending, but Firebase is
  already wired in main.dart and enabled in the console.
