# Metly – Complete Action Checklist for You

## 📋 Overview
This document lists **every step you need to take** to get the Metly app fully functional on all platforms (Web, Android) and to resolve the current compile/runtime errors.  For each step we include **what**, **where**, **when**, and **why**.

---
### 1️⃣ Fix DashboardScreen compile errors (Web & Android)
| When | Where | What | Why |
|------|-------|------|-----|
| **Now** | `lib/screens/dashboard_screen.dart` | Replace the wrong import `import '../models/price_snapshot.dart';` with the correct file `import '../models/price_model.dart';` | `PriceSnapshot` (and `evaluateSignal`) are defined in `price_model.dart`. The old import points to a non‑existent file, causing *“Target of URI doesn't exist”* and a cascade of undefined‑symbol errors. |
| **Now** | `lib/screens/dashboard_screen.dart` | Ensure the import list looks like this (order not critical):
```dart
import '../config/app_config.dart';
import '../services/price_service.dart';
import '../services/ai_service.dart';
import '../models/price_model.dart';   // ← corrected line
import '../models/watchlist_item.dart';
import '../models/portfolio_item.dart';
import '../services/firestore_service.dart';
import '../widgets/common_widgets.dart';
import '../widgets/signal_card.dart';
```
| Without the correct import the compiler cannot find `PriceSnapshot`, `Metal`, or `evaluateSignal`. |
| **Now** | `lib/models/portfolio_item.dart` | Verify the file exists (we created it in a previous step). | The Firestore service references `PortfolioItem`; missing this class caused *“Undefined class 'PortfolioItem'”* errors. |
| **Now** | `lib/services/firestore_service.dart` | The import line `import '../models/portfolio_item.dart';` should now resolve correctly. | Same reason as above. |
| **After changes** | Anywhere (terminal) | Run `flutter analyze` or `flutter build web` again to confirm the errors are gone. | Guarantees the code compiles before deployment. |

---
### 2️⃣ Build & Deploy the Flutter Web app
| When | Where | What | Why |
|------|-------|------|-----|
| **After fixing DashboardScreen** | Project root (`d:\K4NN4N\Metly`) | Run the release build:
```powershell
flutter build web --release
```
| Produces the static assets in `build/web`. |
| **Immediately after the build succeeds** | Project root | Deploy to Vercel (you already have the Vercel CLI installed):
```powershell
npx -y vercel@latest deploy --prod
```
| The `--prod` flag creates the production URL (e.g. `https://metly-gold.vercel.app`). |
| **After deployment** | Vercel dashboard or terminal output | Copy the **Production URL** and open it in a browser. | You will need this URL later when testing the AI proxy and price worker. |

---
### 3️⃣ Deploy the Cloudflare Workers (already done, but keep for reference)
| When | Where | What | Why |
|------|-------|------|-----|
| **Now (or later)** | Cloudflare Dashboard → **Workers & Pages** | • **AI Proxy Worker** – paste `backend/ai-proxy/worker.js`.<br>• **Price Feed Worker** – paste `backend/price-worker/worker.js`. | These workers expose the OpenRouter API and the simulated gold/silver price feed to the Flutter app. |
| **After creating each worker** | Settings → **Variables** | Add the required environment variables:<br>• `OPENROUTER_API_KEY` – your OpenRouter key.<br>• `METLY_PROXY_TOKEN` – a strong random token (store it in the app). | The workers need these values to authenticate requests. |
| **After both workers are live** | Note the URLs (e.g. `https://metly-ai-proxy.<sub>.workers.dev/v1/chat/completions` and `https://metly-price-feed.<sub>.workers.dev`). | You will paste these URLs into the Metly app Settings screen. |

---
### 4️⃣ Configure the Metly app Settings (Web UI)
| When | Where | What | Why |
|------|-------|------|-----|
| **After the Vercel deployment** | Open the deployed Metly site (the URL from step 2). | Go to **Settings → AI & Proxy** and fill in:
- **Proxy URL** – the AI Proxy Worker URL.
- **Proxy Token** – the token you set in Cloudflare.
| The app will now route AI calls through the secure proxy. |
| **Same Settings page** | **Data Source** section | Enter the **Price Worker URL** (from step 3). | Enables the dashboard to fetch live gold/silver prices. |
| **Save** | – | – | Persists the configuration in `SharedPreferences`. |

---
### 5️⃣ Set up Firebase Firestore (Watchlist & Portfolio persistence)
| When | Where | What | Why |
|------|-------|------|-----|
| **Now (or before first deployment)** | Firebase Console → your project (`metly‑62916`). | 1. Enable **Firestore** → *Create database* → choose **Start in test mode** (public read/write).<br>2. (Optional) Later replace the test‑mode rules with the secure rules you will write in `firestore.rules`. | Test mode lets the app write watchlist/portfolio data without authentication during development. |
| **After enabling** | No further action needed for the current code because `FirestoreService` uses a hard‑coded `test-user-id`. | When you add real authentication, replace that ID with `FirebaseAuth.instance.currentUser!.uid`. |

---
### 6️⃣ Resolve Android Gradle / JVM error
The Android build failed because the system is using **Java 8**, but Gradle 8.12 (required by the project) needs **Java 11+**.
| When | Where | What | Why |
|------|-------|------|-----|
| **Immediately** | Your Windows machine | Install a JDK 11 (or newer). You can download it from **AdoptOpenJDK**, **Zulu**, or **Microsoft Build Tools**. |
| **After installation** | Environment Variables | Set `JAVA_HOME` to the JDK folder (e.g. `C:\Program Files\Java\jdk-11.0.22`). Add `%JAVA_HOME%\bin` to the `Path` variable. |
| **After updating PATH** | Terminal | Run `java -version` to confirm it reports **11** (or higher). |
| **Then** | Project root | Run `flutter clean` to clear old Gradle caches. |
| **Finally** | Project root | Run the Android build again:
```powershell
flutter build apk --release   # or flutter run for a device
```
| With Java 11 the Gradle wrapper can download the correct distribution and the build will succeed. |

---
### 7️⃣ Verify the whole system
| When | What to check |
|------|--------------|
| **After each major step** (Web build, Workers, Settings, Android build) | 1. Open the Vercel URL – prices refresh, **Ask AI** returns a short insight.
2. In the dashboard, the **Watchlist** and **Portfolio** sections show “No … items” (empty is expected).
3. Open the browser console – no CORS or network errors.
4. For Android, run the app on a device/emulator – the UI should load, and the same price/AI features work. |

---
## 📌 Quick Reference Table
| Step | Action | Location | Key value / command |
|------|--------|----------|---------------------|
| 1 | Fix import | `lib/screens/dashboard_screen.dart` | `import '../models/price_model.dart';` |
| 2 | Add missing model | `lib/models/portfolio_item.dart` | (file created) |
| 3 | Build Web | project root | `flutter build web --release` |
| 4 | Deploy Web | project root | `npx -y vercel@latest deploy --prod` |
| 5 | Deploy AI Proxy | Cloudflare → Workers | `backend/ai-proxy/worker.js` |
| 6 | Deploy Price Worker | Cloudflare → Workers | `backend/price-worker/worker.js` |
| 7 | Set app URLs | Metly Settings (web) | Proxy URL, Proxy Token, Price Worker URL |
| 8 | Enable Firestore (test mode) | Firebase Console | – |
| 9 | Install Java 11 | Windows | Download JDK 11, set `JAVA_HOME` |
|10 | Android build | project root | `flutter clean && flutter build apk --release` |

---
### ✅ When you’re done
- All compile errors should disappear (`flutter build web` succeeds). 
- The Vercel site is live and shows live prices and AI insights. 
- Android builds without the Gradle/JVM error. 
- Watchlist & Portfolio data persist in Firestore (test mode). 

If any step fails, re‑run the preceding step, double‑check the URLs/keys, and let me know the exact error message – I’ll help you troubleshoot further.
