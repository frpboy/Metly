import 'dart:async';

import 'package:sentry_flutter/sentry_flutter.dart';

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
/// Every event passes [sanitizeSentryEvent], the single egress boundary,
/// which rebuilds the event from known-safe parts instead of redacting
/// strings.
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
    }, appRunner: appRunner);
  }

  static Future<void> capture(Object error, StackTrace? stackTrace) async {
    if (!configured) return;
    await Sentry.captureException(error, stackTrace: stackTrace);
  }
}

/// Structural guard for fields that should only ever hold code or
/// device identifiers. A value containing transport, path, query or
/// identity characters - or whitespace where identifiers cannot have
/// any - cannot be a plain identifier, so the field is dropped.
/// Charset constraint, not content matching.
String? structuralField(String? value, {int maxLength = 128, bool allowSpace = false}) {
  if (value == null || value.length > maxLength) return null;
  const banned = ['/', '\\', '@', '?', '=', '&', '%'];
  for (final ch in banned) {
    if (value.contains(ch)) return null;
  }
  if (!allowSpace && value.split('').any((c) => c.trim().isEmpty)) return null;
  return value;
}

/// Egress boundary: minimal generic reconstruction, not string
/// redaction. Anything that can carry user text or identifiers is
/// dropped by structure: exception values, messages, transaction names,
/// culprit, breadcrumbs, request data, user, server name, tags, extras,
/// threads, absolute paths and source context lines. Frame detail is
/// kept only for frames from the app's own package (compile-time
/// identifiers). Contexts are rebuilt with allowlisted fields only.
SentryEvent sanitizeSentryEvent(SentryEvent event) {
  const appPackagePrefix = 'package:metly/';

  event.user = null;
  event.request = null;
  event.breadcrumbs = null;
  event.serverName = null;
  event.message = null;
  event.transaction = null;
  event.culprit = null;
  event.threads = null;
  event.tags?.clear();
  event.extra?.clear();

  final exceptions = event.exceptions;
  if (exceptions != null) {
    for (final e in exceptions) {
      e.type = structuralField(e.type);
      e.module = structuralField(e.module);
      e.value = null; // free text: can embed URLs, paths, tokens
      final mech = e.mechanism;
      if (mech != null) {
        mech.description = null;
        mech.helpLink = null;
      }
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
    }
  }

  final contexts = event.contexts;
  contexts.response = null;
  contexts.trace = null;
  final os = contexts.operatingSystem;
  if (os != null) {
    os.name = structuralField(os.name, maxLength: 64, allowSpace: true);
    os.version = structuralField(os.version, maxLength: 64);
    os.build = null;
    os.kernelVersion = null;
  }
  final device = contexts.device;
  if (device != null) {
    device.name = null; // can be a user-chosen device name
    device.model = structuralField(device.model, maxLength: 64, allowSpace: true);
    device.brand = structuralField(device.brand, maxLength: 64, allowSpace: true);
    device.manufacturer =
        structuralField(device.manufacturer, maxLength: 64, allowSpace: true);
  }
  final app = contexts.app;
  if (app != null) {
    app.name = null;
    app.identifier = structuralField(app.identifier, maxLength: 128);
    app.version = structuralField(app.version, maxLength: 64);
    app.build = structuralField(app.build, maxLength: 64);
  }
  return event;
}
