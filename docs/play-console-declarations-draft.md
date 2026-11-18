# Metly - Play Console declarations DRAFT (for Rahul's review; NOT submitted)

Prepared 2026-11-18 against repo main 27b8873f. Every answer below is grounded in
the code paths cited; items marked [OWNER CONFIRM] cannot be answered from the
repo and need Rahul's confirmation before submission. Nothing here has been
entered into Play Console.

## App identity (recommendation, enrollment itself is a held owner action)
- Package: `com.k4nn4n.metly` - already the shipped applicationId in all three
  public preview releases (builds 101101/101301/101401). Recommend keeping it;
  renaming orphans the existing preview install base for no benefit.
- Signing route (recommendation): Google Play app signing (Play-managed app
  signing key) + a generated upload keystore stored in the vault - same route
  as Seali. IMPORTANT CONSEQUENCE: the current preview APKs are signed with the
  Android debug certificate (verified by cert, CN=Android Debug, SHA-256
  96:D8:0A:D6:54:04:17:BE:C4:DE:09:F6:00:B2:F3:E8:3C:7F:23:81:0A:A3:49:25:A1:B2:D3:D5:CF:14:91:87;
  the non-suffixed `Metly-v1.0.0-build-101401.apk` asset is unsigned). A
  Play-signed build has a DIFFERENT signer, so existing debug-preview installs
  cannot upgrade in place - testers must UNINSTALL the preview build first.
  This is a known one-time cost, not a seamless upgrade.
  Signing enrollment decision itself stays held for Rahul.

## Data safety (grounded in code)
- Email address - COLLECTED: email+password sign-in via Firebase Auth
  (lib/screens/auth_screen.dart, lib/services/auth_service.dart).
  Purpose: account management. [OWNER CONFIRM: whether sign-in is mandatory or
  optional for core price viewing - affects the "required vs optional" answer.]
- Watchlist and portfolio entries - COLLECTED, stored per-user in Cloud
  Firestore `users/{uid}/watchlist` and `users/{uid}/portfolio`
  (lib/services/firestore_service.dart). Purpose: app functionality.
- Feedback email + message - COLLECTED when user submits feedback
  (lib/screens/feedback_screen.dart). Purpose: app functionality/support.
- AI prompts - when AI mode is "Metly AI", prompts go to the Metly Cloudflare
  proxy which calls OpenRouter; in "Use My API" mode the user's own OpenRouter
  key is stored on-device only in SharedPreferences
  (lib/config/app_config.dart). AI can be turned off (AiMode.off).
- Price data - fetched from gold-api.com without personal data
  (backend note in ACTION_ITEMS.md).
- No advertising SDKs, no analytics SDKs in pubspec.yaml.
  [OWNER CONFIRM: Firebase project `metly-e1d84` console settings - whether
  Analytics is enabled there; not determinable from the repo.]
- Encryption in transit: all network access is HTTPS (dio; Firebase SDKs).
- Privacy policy URL: [OWNER ACTION - none found in repo; Play requires one.]

## Content rating / audience
- Finance app, no gambling, no simulated gambling visible in code.
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
  Likely Anti-Feature flag even then: Non-Free Network Services (OpenRouter).
- License is Apache-2.0 (FLOSS - satisfies the license requirement).

## Open inconsistencies flagged (not blockers for this draft)
- README still says prices are "currently mocked"; ACTION_ITEMS.md says the
  price worker was quarantined and the app now fetches real spot prices from
  gold-api.com. Listing copy above follows the newer statement; README should
  be updated before public listing.
- README roadmap lists "Firebase: Initialize" as pending, but Firebase is
  already wired in main.dart. Declared-vs-wired state is inconsistent;
  runtime working state of Auth/Firestore is not established by the repo.
