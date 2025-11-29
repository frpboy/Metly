# Metly Project Plan

## Project Overview
Metly is a Flutter-based mobile application designed to track Gold and Silver prices, provide buy/wait signals, and offer AI-driven insights. The project is currently in a prototype stage, with most functionality contained within a single file (`lib/main.dart`) and using mock data.

## Tech Stack
-   **Framework**: Flutter (Dart SDK >=3.4.0 <4.0.0)
-   **Platforms**: Android, iOS, Web, Windows, Linux, macOS
-   **State Management**: Currently `setState` (Needs migration to Provider/Riverpod/Bloc)
-   **Local Storage**: `shared_preferences`
-   **Networking**: `dio`
-   **AI Integration**: OpenRouter API (Direct & via Cloudflare Worker proxy)
-   **Backend/Services**:
    -   **Firebase**: Configured (`firebase.json`, `.firebaserc`) but not initialized in code.
    -   **Cloudflare**: Proxy for AI calls (implied by `ProxyAiClient`).

## Current Status (What's Built)
### Core Logic
-   **Pricing Engine**: `PriceSnapshot`, `Signal` (Buy/Wait) logic based on price thresholds and festive windows.
-   **Mock Data**: `MockPriceProvider` generates fake price data with jitter for testing.
-   **AI Client**: `OpenRouterClient` and `ProxyAiClient` classes implementation for fetching market explanations.
-   **Configuration**: `Cfg` class handles pricing constants and AI mode switching.

### UI / UX
-   **Navigation**: Custom AppBar and Drawer (`MetlyAppBar`, `MetlyDrawer`).
-   **Dashboard**: Displays Gold/Silver prices, signals, and AI insights.
-   **Settings**: Toggle AI modes (Off, Metly Cloud, User API Key), adjust preferences.
-   **Static Pages**: About screen, Paywall stub, Feedback stub.
-   **Theming**: Dark mode aesthetic with Gold/Silver accents.

## Roadmap (What's Left)

### 2. Backend & Data Integration
-   [ ] **Real Price Data**: Replace `MockPriceProvider` with a real API integration (e.g., MetalPriceAPI, GoldAPI).
-   [ ] **Firebase Initialization**: Add `Firebase.initializeApp()` to `main()`.
-   [ ] **Authentication**: Implement Firebase Auth (Google Sign-In, Email/Password) for user accounts.
-   [ ] **Database**: Use Firestore to store user preferences, favorites, and feedback.

### 3. Feature Completion
-   [ ] **Paywall**: Implement actual payment processing (e.g., Stripe, RevenueCat) or link to a payment gateway.
-   [ ] **Feedback**: Connect the feedback form to a backend (Firestore or Cloud Function).
-   [ ] **Notifications**: Implement push notifications for "Buy" signals using Firebase Cloud Messaging (FCM).

### 4. Testing & Polish
-   [ ] **Unit Tests**: Test the pricing logic and signal evaluation algorithms.
-   [ ] **Widget Tests**: Verify UI components render correctly.
-   [ ] **Integration Tests**: Test the full flow from data fetching to UI update.
-   [ ] **CI/CD**: Set up GitHub Actions for automated building and testing.

## Directory Structure Proposal
```
lib/
├── main.dart
├── config/
│   ├── theme.dart
│   └── constants.dart
├── models/
│   ├── price_snapshot.dart
│   └── signal_result.dart
├── services/
│   ├── api_service.dart
│   ├── ai_service.dart
│   └── auth_service.dart
├── providers/ (or bloc/)
│   └── app_state.dart
├── screens/
│   ├── dashboard_screen.dart
│   ├── settings_screen.dart
│   └── ...
└── widgets/
    ├── common/
    └── specific/
```
