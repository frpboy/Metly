import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:metly/services/auth_bootstrap.dart';
import 'package:metly/services/auth_service.dart';

void main() {
  test('ready includes a confirmed signed-out session', () async {
    expect(await waitForInitialAuthState(Stream.value(null)), isTrue);
  });
  test('never-emitting SDK is bounded and subscription canceled', () async {
    var canceled = false;
    final states =
        StreamController<MetlyUser?>(onCancel: () => canceled = true);
    expect(
        await waitForInitialAuthState(states.stream,
            timeout: const Duration(milliseconds: 10)),
        isFalse);
    expect(canceled, isTrue);
    await states.close();
  });
  test('SDK error does not prevent app startup', () async {
    expect(await waitForInitialAuthState(Stream.error(StateError('offline'))),
        isFalse);
  });
  test('late auth recovery remains available to a route listener', () async {
    final states = StreamController<MetlyUser?>.broadcast();
    expect(
        await waitForInitialAuthState(states.stream,
            timeout: const Duration(milliseconds: 10)),
        isFalse);
    final recovered = states.stream.first;
    states.add(const MetlyUser(uid: 'restored-late'));
    expect((await recovered)?.uid, 'restored-late');
    await states.close();
  });
}
