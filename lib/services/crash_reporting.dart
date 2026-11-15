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
/// Two boundaries, both tested with the real SDK:
/// 1. [sanitizeSentryEvent] replaces every captured event with a FRESH
///    generic event carrying only qualified fields.
/// 2. [EventOnlyTransport] wraps the HTTP transport and forwards only
///    the single event item of each envelope, so attachments or any
///    other item type are dropped at the final boundary even if an
///    integration adds them after beforeSend.
class MetlyCrashReporting {
  MetlyCrashReporting._();

  static const _dsn = String.fromEnvironment('METLY_SENTRY_DSN');

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
      options.beforeSend = (event, hint) => sanitizeSentryEvent(event);
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

/// Final-envelope guard: forwards only the event item of each envelope
/// under a rebuilt header (no trace context, no original item set).
/// Attachments, replays, profiles or any other item type are dropped
/// here even if something upstream adds them after beforeSend.
class EventOnlyTransport implements Transport {
  EventOnlyTransport(this._inner);

  final Transport _inner;

  @override
  Future<SentryId?> send(SentryEnvelope envelope) async {
    final eventItems =
        envelope.items.where((item) => item.header.type == 'event').toList();
    if (eventItems.isEmpty) return envelope.header.eventId;
    final id = envelope.header.eventId ?? SentryId.newId();
    final filtered = SentryEnvelope(
      SentryEnvelopeHeader(id, envelope.header.sdkVersion,
          sentAt: DateTime.now().toUtc()),
      eventItems,
      containsUnhandledException: envelope.containsUnhandledException,
    );
    return _inner.send(filtered);
  }
}

/// Structural guard for fields that should only ever hold code or
/// device identifiers. A value containing transport, path, query or
/// identity characters - or whitespace where identifiers cannot have
/// any - cannot be a plain identifier, so the field is dropped.
/// Charset constraint, not content matching.
String? structuralField(String? value,
    {int maxLength = 128, bool allowSpace = false}) {
  if (value == null || value.length > maxLength) return null;
  const banned = ['/', '\\', '@', '?', '=', '&', '%'];
  for (final ch in banned) {
    if (value.contains(ch)) return null;
  }
  if (!allowSpace && value.split('').any((c) => c.trim().isEmpty)) return null;
  return value;
}

/// Egress boundary: instead of scrubbing the captured event, build a
/// FRESH generic event and copy only qualified fields. Anything not
/// explicitly copied - user, request, breadcrumbs, message, transaction,
/// culprit, tags, extras, threads, server name, SDK/unknown fields -
/// cannot leak because it never enters the new event. Frame objects are
/// rebuilt field-by-field (the SDK's stack-trace type has no public
/// constructor, so frames are sanitized in place before being reused);
/// detail survives only for frames from the app's own package, and
/// absolute paths, context lines and addresses are always dropped.
SentryEvent sanitizeSentryEvent(SentryEvent source) {
  const appPackagePrefix = 'package:metly/';

  final contexts = Contexts();
  final os = source.contexts.operatingSystem;
  if (os != null) {
    contexts.operatingSystem = SentryOperatingSystem(
      name: structuralField(os.name, maxLength: 64, allowSpace: true),
      version: structuralField(os.version, maxLength: 64),
    );
  }
  final device = source.contexts.device;
  if (device != null) {
    contexts.device = SentryDevice(
      model: structuralField(device.model, maxLength: 64, allowSpace: true),
      brand: structuralField(device.brand, maxLength: 64, allowSpace: true),
      manufacturer:
          structuralField(device.manufacturer, maxLength: 64, allowSpace: true),
    );
  }
  final app = source.contexts.app;
  if (app != null) {
    contexts.app = SentryApp(
      identifier: structuralField(app.identifier, maxLength: 128),
      version: structuralField(app.version, maxLength: 64),
      build: structuralField(app.build, maxLength: 64),
    );
  }

  return SentryEvent(
    eventId: SentryId.newId(),
    timestamp: DateTime.now().toUtc(),
    platform: source.platform,
    level: source.level,
    logger: structuralField(source.logger, maxLength: 64),
    // Trusted build metadata only.
    release: structuralField(source.release),
    dist: structuralField(source.dist, maxLength: 64),
    environment: structuralField(source.environment, maxLength: 64),
    contexts: contexts,
    exceptions: source.exceptions?.map((e) {
      final frames = e.stackTrace?.frames;
      if (frames != null) {
        for (final f in frames) {
          final fromApp = f.absPath?.startsWith(appPackagePrefix) ?? false;
          f.absPath = null;
          f.contextLine = null;
          if (!fromApp) {
            f.module = null;
            f.function = null;
            f.fileName = null;
            f.lineNo = null;
          } else {
            f.module = structuralField(f.module);
            f.function = structuralField(f.function);
            f.fileName = structuralField(f.fileName);
          }
        }
      }
      final mechanismType = structuralField(e.mechanism?.type, maxLength: 64);
      return SentryException(
        type: structuralField(e.type),
        // value is free text and can embed URLs, paths, tokens: dropped.
        value: null,
        module: structuralField(e.module),
        mechanism: mechanismType == null
            ? null
            : Mechanism(type: mechanismType, handled: e.mechanism!.handled),
        stackTrace: e.stackTrace,
      );
    }).toList(),
  );
}
