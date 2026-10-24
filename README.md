# Metly 🪙

Metly is a premium Flutter application designed to track Gold and Silver prices in real-time, providing intelligent "Buy" or "Wait" signals and AI-driven market insights.

## Links

- **Web demo (prototype; prices are mocked):** https://metly-gold.vercel.app/
- **Source code:** https://github.com/frpboy/Metly

## ✨ Features

-   **Real-time Price Tracking**: Monitor live Gold and Silver prices (currently mocked).
-   **Smart Signals**: Get actionable "Buy" or "Wait" recommendations based on price trends and festive windows.
-   **AI Insights**: Ask the AI for detailed explanations of market movements and signal rationale.
-   **Premium UI**: A sleek, dark-themed interface with gold and silver accents.
-   **Customizable**: Toggle between different AI modes (Metly Cloud, User API Key) and configure preferences.

## 🛠 Tech Stack

-   **Framework**: Flutter (Dart)
-   **State Management**: `setState` (Migration to Provider/Riverpod planned)
-   **Networking**: `dio`
-   **Local Storage**: `shared_preferences`
-   **AI Integration**: OpenRouter API
-   **Backend**: Firebase (Configured), Cloudflare Workers (Proxy)

## 🚀 Getting Started

### Prerequisites

-   Flutter SDK (>=3.4.0 <4.0.0)
-   Dart SDK
-   Android Studio / VS Code with Flutter extensions

### Installation

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/frpboy/metly.git
    cd metly
    ```

2.  **Install dependencies:**
    ```bash
    flutter pub get
    ```

3.  **Run the app:**
    ```bash
    flutter run
    ```

## 🗺 Roadmap

-   [ ] **Architecture Refactor**: Split `main.dart` into a scalable folder structure.
-   [ ] **Real Data**: Integrate with live Metal Price APIs.
-   [ ] **Firebase**: Initialize Firebase Auth and Firestore.
-   [ ] **Notifications**: Push notifications for price alerts.
-   [ ] **Paywall**: Implement premium subscription features.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.