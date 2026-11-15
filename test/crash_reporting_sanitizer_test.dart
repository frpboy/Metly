import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:metly/services/crash_reporting.dart';
import 'package:sentry/src/transport/rate_limiter.dart';
import 'package:sentry/src/envelope/sentry_envelope_header.dart';
import 'package:sentry/src/envelope/sentry_item_type.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Boundary proof for the fixed-generic Sentry payload, executed against
/// the real SDK classes. A hostile captured event/envelope is passed
/// through the boundary; the outgoing payload must be exactly the fixed
/// generic event (trusted build constants plus fresh id/time) with no
/// byte of the input carried over.
void main() {
  final hostileStrings = [
    'rahul.muraleedharan@example.com',
    'https://example.com/private/path?token=FIXTURE-NOT-A-SECRET',
    'Authorization: Bearer FIXTURE-NOT-A-SECRET',
    '/sdcard/Download/secret-file.txt',
    'user-supplied free text title',
    '192.168.10.77',
    'hostile-marker-7f3a',
  ];

  SentryEvent hostileEvent() => SentryEvent(
        level: SentryLevel.fatal,
        logger: 'hostile-marker-7f3a',
        release: 'https://example.com/private/path?token=FIXTURE-NOT-A-SECRET',
        dist: 'Authorization: Bearer FIXTURE-NOT-A-SECRET',
        environment: 'user-supplied free text title',
        serverName: '192.168.10.77',
        user: SentryUser(email: 'rahul.muraleedharan@example.com'),
        request: SentryRequest(url: 'https://example.com/private/path?token=FIXTURE-NOT-A-SECRET'),
        breadcrumbs: [Breadcrumb(message: 'user-supplied free text title')],
        tags: const {'k': 'hostile-marker-7f3a'},
        extra: const {'k': 'Authorization: Bearer FIXTURE-NOT-A-SECRET'},
        contexts: Contexts(
          device: SentryDevice(name: "rahul's personal phone", model: 'hostile-marker-7f3a'),
        ),
      );

  group('fixed generic event boundary', () {
    test('generic event carries constants only and fresh identity', () {
      final out = buildGenericEvent();
      expect(out.level, SentryLevel.error);
      expect(out.logger, 'app');
      expect(out.environment, 'production');
      expect(out.message?.formatted,
          'app error - details withheld by privacy boundary');
      expect(out.exceptions?.single.type, 'AppError');
      expect(out.user, isNull);
      expect(out.request, isNull);
      expect(out.breadcrumbs, isNull);
      expect(out.serverName, isNull);
      expect(out.tags, isNull);
      expect(out.extra, isNull);
      final a = buildGenericEvent();
      final b = buildGenericEvent();
      expect(a.eventId.toString(), isNot(b.eventId.toString()));
    });

    test('actual SDK serialized payload contains no hostile string', () {
      final payload = jsonEncode(buildGenericEvent().toJson());
      for (final hostile in hostileStrings) {
        expect(payload.contains(hostile), isFalse,
            reason: 'payload leaked: $hostile');
      }
    });

    test('transport discards a hostile envelope and sends one fixed event item',
        () async {
      final captured = <SentryEnvelope>[];
      final transport = EventOnlyTransport(_RecordingTransport(captured), RateLimiter(SentryOptions()));
      final hostileItem = SentryEnvelopeItem.fromEvent(hostileEvent());
      final attachment = SentryAttachment.fromIntList(
          'hostile-marker-7f3a'.codeUnits, 'note.txt',
          contentType: 'text/plain');
      final attachmentItem = SentryEnvelopeItem.fromAttachment(attachment);
      await transport.send(SentryEnvelope(
        SentryEnvelopeHeader(SentryId.newId(), null),
        [hostileItem, attachmentItem],
      ));
      expect(captured, hasLength(1));
      final out = captured.single;
      expect(out.items, hasLength(1));
      expect(out.items.single.header.type, SentryItemType.event);
      expect(out.items.single.header.attachmentType, isNull);
      // Read the raw bytes of the single item and scan them.
      final bytes = await out.items.single.dataFactory();
      final text = utf8.decode(bytes, allowMalformed: true);
      for (final hostile in hostileStrings) {
        expect(text.contains(hostile), isFalse,
            reason: 'envelope leaked: $hostile');
      }
    });
    test('transport drops envelopes without an event item', () async {
      final captured = <SentryEnvelope>[];
      final transport = EventOnlyTransport(_RecordingTransport(captured), RateLimiter(SentryOptions()));
      // Empty envelope: dropped.
      await transport.send(
          SentryEnvelope(SentryEnvelopeHeader(SentryId.newId(), null), const []));
      // Attachment-only envelope: dropped, never converted into an error.
      final attachment = SentryAttachment.fromIntList('x'.codeUnits, 'a.txt',
          contentType: 'text/plain');
      await transport.send(SentryEnvelope(
        SentryEnvelopeHeader(SentryId.newId(), null),
        [SentryEnvelopeItem.fromAttachment(attachment)],
      ));
      expect(captured, isEmpty);
    });
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
