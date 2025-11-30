# Metly – User Action Checklist

## Overview
This document lists **all the actions you need to take** to get the Metly application fully functional with:
- AI Proxy (Cloudflare Worker → OpenRouter)
- Real‑time price feed (Cloudflare Worker)
- Watchlist & Portfolio persistence (Firebase Firestore)
- Deployment of the Flutter web app (Vercel)

Each step includes **what to do**, **where**, **when**, and **why**. Follow the order; later steps depend on earlier ones.

---
### 1️⃣ Deploy the AI Proxy Cloudflare Worker
| When | Where | Why |
|------|-------|-----|
| **Now** (after code changes) | Cloudflare Dashboard → **Workers & Pages** → **Create a Worker** (e.g., `metly-ai-proxy`) | Provides a secure gateway that adds your `METLY_PROXY_TOKEN` and forwards requests to OpenRouter. |
| | Paste the content of `backend/ai‑proxy/worker.js` into the editor. | |
| | **Settings → Variables** → add two environment variables: | |
| | • `OPENROUTER_API_KEY` – your OpenRouter API key. | Needed for authentication with OpenRouter. |
| | • `METLY_PROXY_TOKEN` – a strong random string (you will also store this in the app). | Used by the Flutter app to prove it is authorised. |
| | Click **Save and Deploy**. | The worker is now live. |
| | **Copy the Worker URL** (e.g., `https://metly-ai-proxy.<subdomain>.workers.dev/v1/chat/completions`). | You will paste this URL into the Metly app settings. |

---
### 2️⃣ Deploy the Price Feed Cloudflare Worker
| When | Where | Why |
|------|-------|-----|
| **Immediately after step 1** | Cloudflare Dashboard → **Create another Worker** (e.g., `metly-price-feed`). | Supplies gold & silver prices to the app (currently simulated). |
| | Paste `backend/price‑worker/worker.js`. | |
| | No env vars are required for the simulated version. (If you later switch to a real API, add the needed keys here.) |
| | Deploy and **copy the Worker URL** (e.g., `https://metly-price-feed.<subdomain>.workers.dev`). |

---
### 3️⃣ Configure the Flutter App (Metly Web)
| When | Where | Why |
|------|-------|-----|
| **After you have both Worker URLs** | Open the deployed Metly web app (the Vercel URL you already have). | The app reads these settings at runtime. |
| | Go to **Settings** → **AI & Proxy**. | |
| | • **Proxy URL** → paste the AI Proxy Worker URL from step 1. |
| | • **Proxy Token** → paste the `METLY_PROXY_TOKEN` you created. |
| | Scroll to **Data Source**. |
| | • **Price Worker URL** → paste the Price Feed Worker URL from step 2. |
| | Save the settings. |
| | The app will now use the proxy for AI calls and fetch live (simulated) metal prices from the price worker. |

---
### 4️⃣ Set Up Firebase Firestore (Watchlist & Portfolio)
| When | Where | Why |
|------|-------|-----|
| **Before deploying the web app** (or immediately after step 3) | Firebase Console → your project (`metly‑62916`). | Stores user‑specific watchlist and portfolio data. |
| | Enable **Firestore** → **Create database** → choose **Start in test mode**. | Allows reads/writes without authentication for now (development). |
| | (Optional) Later replace test‑mode rules with the secure rules you will write in `firestore.rules`. |
| | The code in `lib/services/firestore_service.dart` reads/writes under `users/<test-user-id>/watchlist` and `users/<test-user-id>/portfolio`. | Hard‑coded `test-user-id` is used until you add Firebase Auth. |

---
### 5️⃣ Deploy the Updated Flutter Web App to Vercel
| When | Where | Why |
|------|-------|-----|
| **After steps 1‑4 are complete** | Local machine (project root). | Publishes the UI with the new functionality. |
| | Run the following commands (PowerShell):
```
flutter build web --release
npx -y vercel@latest deploy --prod
```
| The first builds the static web assets into `build/web`. The second uploads them to Vercel. |
| | When Vercel asks for the output directory, type `build/web`. |
| | After deployment, you will receive a new Vercel URL. |

---
### 6️⃣ Verify the Whole System
| When | What to Check |
|------|--------------|
| **Immediately after deployment** | Open the Vercel URL in a browser. |
| | • Prices appear and update when you tap **Refresh Prices**. |
| | • Click **Ask AI** – you should receive a short insight (no errors). |
| | • The **Watchlist** and **Portfolio** sections show “No … items” (empty is expected). |
| | • Open the browser console – there should be no CORS or network errors. |
| | If anything fails, revisit the corresponding step and ensure URLs and tokens are correct. |

---
### 7️⃣ Future Enhancements (Optional, not required now)
- **Add Firebase Authentication** and replace the hard‑coded `test-user-id` with the authenticated UID.
- **Swap the simulated price worker** for a real metal‑price API (e.g., MetalPriceAPI) – just modify `backend/price‑worker/worker.js` to call the external API and return the JSON shape.
- **Harden Firestore security rules** (move out of test mode) – edit `firestore.rules` to restrict reads/writes to the authenticated user.
- **Create UI for adding/removing watchlist items** and managing portfolio holdings.
- **Implement push notifications** for “Buy” signals (e.g., using Firebase Cloud Messaging).

---
## Quick Reference Table
| Step | Action | Location | Key Value |
|------|--------|----------|----------|
| 1 | Deploy AI Proxy Worker | Cloudflare → Workers | `METLY_PROXY_TOKEN`, `OPENROUTER_API_KEY` |
| 2 | Deploy Price Feed Worker | Cloudflare → Workers | (none required for simulated version) |
| 3 | Set URLs in Metly Settings | Metly web app → Settings | Proxy URL, Proxy Token, Price Worker URL |
| 4 | Enable Firestore (test mode) | Firebase Console → Firestore | – |
| 5 | Deploy Flutter web | Local terminal → Vercel | `build/web` directory |
| 6 | Verify | Browser (Vercel URL) | – |

---
**That’s everything you need to do.** Follow the steps in order, and you’ll have a fully‑functional Metly app with AI, live price data, and persistent watchlist/portfolio.
