import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:metly/services/crash_reporting.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Hostile-scope negative proof for the Metly Sentry egress boundary,
/// using the real SDK classes and the real event serializer
/// (event.toJson(), the exact payload the envelope carries).
void main() {
  const hostileStrings = [
    'person@example.com',
    'account-name',
    '203.0.113.10',
    'https://api.metly.example/prices?token=eyJhbGciOiJIUzI1NiJ9',
    'session=secret',
    'user typed private text',
    'rahul-personal-device',
    'eyJhbGciOiJIUzI1NiJ9',
  ];

  SentryEvent hostileEvent() {
    final event = SentryEvent();
    event.user = SentryUser(
        email: 'person@example.com',
        username: 'account-name',
        ipAddress: '203.0.113.10');
    event.request = SentryRequest(
        url: 'https://api.metly.example/prices?token=eyJhbGciOiJIUzI1NiJ9',
        cookies: 'session=secret');
    event.breadcrumbs = [Breadcrumb(message: 'user typed private text')];
    event.serverName = 'rahul-personal-device';
    event.message = SentryMessage(
        'failed https://api.metly.example/prices?token=eyJhbGciOiJIUzI1NiJ9');
    event.transaction = '/paywall/private-item';
    event.tags = {'user_query': 'private-item'};
    event.extra = {'attempt_url': 'https://api.metly.example/prices?token=eyJhbGciOiJIUzI1NiJ9'};
    event.contexts.device = SentryDevice(
        name: 'rahul-personal-device',
        model: 'Pixel 8',
        brand: 'Google',
        manufacturer: 'Google');
    // Exceptions and stack frames have no public constructors in the
    // SDK, so build them through the real SDK deserializer.
    event.exceptions = [
      SentryException.fromJson({
        'type': 'Exception',
        'value':
            'failed to load https://api.metly.example/prices?token=eyJhbGciOiJIUzI1NiJ9',
        'stacktrace': {
          'frames': [
            {
              'abs_path': 'package:metly/services/price_service.dart',
              'filename': 'price_service.dart',
              'function': 'fetchPrices',
              'lineno': 42,
              'in_app': true,
            },
            {
              'abs_path': '/home/rahul/private/path/external.dart',
              'filename': 'external.dart',
              'function': 'load https://api.metly.example/x',
              'module': 'external',
              'lineno': 1,
              'in_app': false,
            },
          ],
        },
      }),
    ];
    return event;
  }

  test('structural reconstruction keeps only known-safe parts', () {
    final event = sanitizeSentryEvent(hostileEvent());
    expect(event.user, isNull);
    expect(event.request, isNull);
    expect(event.breadcrumbs, isNull);
    expect(event.serverName, isNull);
    expect(event.message, isNull);
    expect(event.transaction, isNull);
    expect(event.tags, isNull);
    expect(event.extra, isNull);
    expect(event.contexts.device?.name, isNull);
    expect(event.contexts.device?.model, 'Pixel 8');

    final exception = event.exceptions!.single;
    expect(exception.type, 'Exception');
    expect(exception.value, isNull);
    final frames = exception.stackTrace!.frames;
    expect(frames[0].function, 'fetchPrices');
    expect(frames[0].absPath, isNull);
    // Out-of-package frame: all detail dropped.
    expect(frames[1].module, isNull);
    expect(frames[1].function, isNull);
    expect(frames[1].fileName, isNull);
    expect(frames[1].lineNo, isNull);
  });

  test('actual SDK serialized payload contains no hostile string', () {
    final sanitized = sanitizeSentryEvent(hostileEvent());
    final payload = jsonEncode(sanitized.toJson());
    expect(payload, contains('Exception'));
    expect(payload, contains('fetchPrices'));
    for (final hostile in hostileStrings) {
      expect(payload.contains(hostile), isFalse,
          reason: 'payload leaked: $hostile');
    }
  });

  test('structural guard drops identifier fields with transport chars', () {
    expect(structuralField('Pixel 8', allowSpace: true), 'Pixel 8');
    expect(structuralField('fetchPrices'), 'fetchPrices');
    expect(structuralField('Google/session=secret'), isNull);
    expect(structuralField('person@example.com'), isNull);
    expect(structuralField('a?b=c'), isNull);
    expect(structuralField('has space'), isNull);
    expect(structuralField('x' * 200), isNull);
    expect(structuralField(null), isNull);
  });

  test('fresh event carries new identity and omits uncopied fields', () {
    final hostile = hostileEvent();
    final out = sanitizeSentryEvent(hostile);
    expect(out.eventId.toString(), isNot(hostile.eventId.toString()));
    expect(out.level, hostile.level);
    expect(out.platform, hostile.platform);
    expect(out.threads, isNull);
    expect(out.culprit, isNull);
    expect(out.sdk, isNull);
    expect(out.throwable, isNull);
    expect(out.contexts['zz_foreign'], isNull);
  });

  test('EventOnlyTransport drops non-event items from the final envelope',
      () async {
    final event = SentryEvent(release: '1.0.0+1');
    final item = await SentryEnvelopeItem.fromEvent(event);
    final attachment = SentryAttachment.fromIntList(
        'hello'.codeUnits, 'note.txt',
        contentType: 'text/plain');
    final captured = <SentryEnvelope>[];
    final transport = EventOnlyTransport(_RecordingTransport(captured));
    await transport.send(SentryEnvelope(
      SentryEnvelopeHeader(event.eventId, null),
      [SentryEnvelopeItem.fromAttachment(attachment), item],
    ));
    expect(captured, hasLength(1));
    expect(captured.single.items, hasLength(1));
    expect(captured.single.items.single.header.type, 'event');
    expect(captured.single.items.single.header.attachmentType, isNull);
  });
}

class _RecordingTransport implements Transport {
  _RecordingTransport(this.sent);
  final List<SentryEnvelope> sent;
  @override
  Future<SentryId?> send(SentryEnvelope envelope) async {
    sent.add(envelope);
    return envelope.header.eventId;
  }
}
