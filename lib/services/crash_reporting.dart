import 'dart:async';

import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:sentry_flutter/src/transport/http_transport.dart';
import 'package:sentry_flutter/src/transport/rate_limiter.dart';

/// Minimal automatic crash/error reporting for Metly.
///
/// Error and crash capture only: no performance tracing, profiling,
/// session tracking, screenshots, view hierarchy or breadcrumbs, and the
/// native SDKs are explicitly NOT auto-initialized (sentry_flutter
/// 10.4.0 defaults them ON - verified in the package source), because
/// native capture is an unqualified path: disabled and labeled, not
/// sent raw. SDK logs default to a no-op logger (verified in the 10.4.0
/// source) and are never enabled here.
///
/// Boundary: nothing the SDK captured is forwarded. Every captured
/// event, hint and envelope item is discarded and replaced by ONE fixed
/// generic event built only from trusted build constants plus a fresh
/// id and timestamp ([buildGenericEvent]). The transport wrapper
/// ([EventOnlyTransport]) rebuilds the final envelope the same way at
/// the last boundary, so anything added after beforeSend - attachments,
/// extra items, integrations - is dropped as well. There is no content
/// scanning: the input is never read.
class MetlyCrashReporting {
  MetlyCrashReporting._();

  static const _dsn = String.fromEnvironment('METLY_SENTRY_DSN');

  /// Trusted build constant; set with --dart-define=METLY_RELEASE=... .
  static const _release = String.fromEnvironment('METLY_RELEASE');

  static bool get configured => _dsn.isNotEmpty;

  /// Wraps [appRunner] with Sentry when a DSN is configured at build
  /// time (--dart-define=METLY_SENTRY_DSN=...). Without it the app runs
  /// exactly as before with no reporting active.
  static Future<void> run(FutureOr<void> Function() appRunner) async {
    if (!configured) {
      await appRunner();
      return;
    }
    await SentryFlutter.init((options) {
      options.dsn = _dsn;
      options.debug = false;
      options.tracesSampleRate = null;
      options.profilesSampleRate = null;
      options.sendDefaultPii = false;
      options.attachScreenshot = false;
      options.attachViewHierarchy = false;
      options.enableUserInteractionBreadcrumbs = false;
      options.enableAppLifecycleBreadcrumbs = false;
      options.enableAutoSessionTracking = false;
      options.enableWatchdogTerminationTracking = false;
      options.autoInitializeNativeSdk = false;
      options.enableNativeCrashHandling = false;
      options.attachThreads = false;
      options.beforeSend = (event, hint) => buildGenericEvent();
      // Pre-setting a non-noop transport stops the SDK replacing it
      // (verified in SentryClient source); the SDK still wraps it with
      // its client-report layer.
      options.transport =
          EventOnlyTransport(HttpTransport(options, RateLimiter(options)));
    }, appRunner: appRunner);
  }

  static Future<void> capture(Object error, StackTrace? stackTrace) async {
    if (!configured) return;
    await Sentry.captureException(error, stackTrace: stackTrace);
  }
}

/// The only payload ever sent: a fixed generic event built from trusted
/// build constants (constant level/logger/environment, compile-time
/// release define) with a fresh random id and current timestamp. No
/// field, hint, attachment, frame, thread, context, tag, extra or any
/// other value from the captured input is read or carried over.
SentryEvent buildGenericEvent() {
  return SentryEvent(
    eventId: SentryId.newId(),
    timestamp: DateTime.now().toUtc(),
    level: SentryLevel.error,
    logger: 'app',
    release: MetlyCrashReporting._release.isEmpty
        ? null
        : MetlyCrashReporting._release,
    environment: 'production',
    contexts: Contexts(),
  );
}

/// Final boundary: whatever envelope the SDK built is discarded and
/// replaced by one envelope containing exactly one item - the fixed
/// generic event - under a fresh header. The incoming envelope and its
/// items are never forwarded.
class EventOnlyTransport implements Transport {
  EventOnlyTransport(this._inner);

  final Transport _inner;

  @override
  Future<SentryId?> send(SentryEnvelope envelope) async {
    final event = buildGenericEvent();
    final item = SentryEnvelopeItem.fromEvent(event);
    return _inner.send(SentryEnvelope(
      SentryEnvelopeHeader(event.eventId, null),
      [item],
    ));
  }
}
