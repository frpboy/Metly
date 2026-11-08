import 'auth_service.dart';

/// Bounds startup without treating an unresolved restoration as signed out.
/// Each route keeps its live listener so a late SDK event can recover the UI.
Future<bool> waitForInitialAuthState(Stream<MetlyUser?> states,
    {Duration timeout = const Duration(seconds: 8)}) async {
  try {
    await states.timeout(timeout).first;
    return true;
  } catch (_) {
    return false;
  }
}
