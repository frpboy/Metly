# Bolt's Performance Journal

## 2026-11-10 - Firestore Reactive Stream Instantiation in Flutter StreamBuilder
**Learning:** In Flutter, calling a Firestore stream getter/method (such as `firestore.watchlistStream()`) directly inside a widget's `build()` method creates a new `Stream` instance on every build. When the parent widget rebuilds (e.g. timers, button clicks, price polling, state changes), `StreamBuilderBaseState.didUpdateWidget` compares `oldWidget.stream != newWidget.stream`. Because it is a new Stream reference, Flutter unsubscribes from the existing listener and resubscribes to the new one. In Firestore, this causes unnecessary network and cache snapshot resubscriptions and potential UI spinner flickers.
**Action:** Always convert sections consuming dynamic Firestore streams into `StatefulWidget` (or memoize the stream), caching the `Stream` instance in `State.initState` and updating it only in `State.didUpdateWidget` when the underlying configuration/service changes.
