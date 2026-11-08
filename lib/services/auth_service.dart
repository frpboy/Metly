import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_core/firebase_core.dart' as fb_core;

/// Minimal app-facing user record (no firebase_auth types leak into the UI).
class MetlyUser {
  final String uid;
  final String? email;
  const MetlyUser({required this.uid, this.email});
}

/// Auth seam: production uses [FirebaseAuthService]; tests supply fakes.
abstract class AuthService {
  Stream<MetlyUser?> authChanges();
  MetlyUser? get current;
  Future<MetlyUser> signIn(String email, String password);
  Future<MetlyUser> signUp(String email, String password);
  Future<void> resetPassword(String email);
  Future<void> signOut();
}

/// Human-readable auth failure, mapped from Firebase error codes.
class AuthException implements Exception {
  final String message;
  const AuthException(this.message);
  @override
  String toString() => message;
}

class FirebaseAuthService implements AuthService {
  final fb.FirebaseAuth _auth;
  FirebaseAuthService([fb.FirebaseAuth? auth])
      : _auth = auth ?? fb.FirebaseAuth.instance;

  MetlyUser? _wrap(fb.User? u) =>
      u == null ? null : MetlyUser(uid: u.uid, email: u.email);

  @override
  Stream<MetlyUser?> authChanges() => _auth.authStateChanges().map(_wrap);

  @override
  MetlyUser? get current => _wrap(_auth.currentUser);

  Never _throwMapped(fb.FirebaseAuthException e) {
    final msg = switch (e.code) {
      'invalid-email' => 'That email address looks invalid.',
      'email-already-in-use' =>
        'An account already exists for this email. Try signing in.',
      'weak-password' => 'Password is too weak. Use at least 6 characters.',
      'user-not-found' ||
      'wrong-password' ||
      'invalid-credential' =>
        'Email or password is incorrect.',
      'user-disabled' => 'This account has been disabled.',
      'too-many-requests' =>
        'Too many attempts. Please wait a bit and try again.',
      'network-request-failed' =>
        'Network error. Check your connection and retry.',
      _ => 'Authentication failed (${e.code}). Please try again.',
    };
    throw AuthException(msg);
  }

  @override
  Future<MetlyUser> signIn(String email, String password) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(
          email: email.trim(), password: password);
      return _wrap(cred.user)!;
    } on fb.FirebaseAuthException catch (e) {
      _throwMapped(e);
    }
  }

  @override
  Future<MetlyUser> signUp(String email, String password) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
          email: email.trim(), password: password);
      return _wrap(cred.user)!;
    } on fb.FirebaseAuthException catch (e) {
      _throwMapped(e);
    }
  }

  @override
  Future<void> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on fb.FirebaseAuthException catch (e) {
      // Deliberately vague on unknown accounts: do not leak which emails
      // are registered.
      if (e.code == 'user-not-found' || e.code == 'invalid-email') return;
      _throwMapped(e);
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();
}

/// Used when Firebase has not been initialized (e.g. widget tests that never
/// run main()). Behaves as permanently signed out; sign-in attempts fail
/// with a readable message instead of crashing the widget tree.
class SignedOutStubAuth implements AuthService {
  const SignedOutStubAuth();
  @override
  Stream<MetlyUser?> authChanges() => Stream.value(null);
  @override
  MetlyUser? get current => null;
  @override
  Future<MetlyUser> signIn(String email, String password) =>
      throw const AuthException('Accounts are unavailable right now.');
  @override
  Future<MetlyUser> signUp(String email, String password) =>
      throw const AuthException('Accounts are unavailable right now.');
  @override
  Future<void> resetPassword(String email) =>
      throw const AuthException('Accounts are unavailable right now.');
  @override
  Future<void> signOut() async {}
}

/// Resolves the production auth service. Safe to call from any widget:
/// returns a signed-out stub when Firebase was never initialized.
AuthService metlyDefaultAuth() {
  try {
    if (fb_core.Firebase.apps.isEmpty) return const SignedOutStubAuth();
  } catch (_) {
    return const SignedOutStubAuth();
  }
  return FirebaseAuthService();
}
