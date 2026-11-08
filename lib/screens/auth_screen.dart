import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/app_config.dart';
import '../services/auth_service.dart';
import '../widgets/common_widgets.dart';

/// Email + password sign in / create account.
/// Sessions persist automatically (Firebase Auth web default), so a
/// signed-in user stays signed in across reloads until they sign out.
class AuthScreen extends StatefulWidget {
  final AuthService? authOverride;
  const AuthScreen({super.key, this.authOverride});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  late final AuthService _auth = widget.authOverride ?? FirebaseAuthService();
  bool _isSignUp = false;
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  String? _info;
  bool _resetBusy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String? _validate() {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      return 'Enter a valid email address.';
    }
    if (_password.text.length < 6) {
      return 'Password must be at least 6 characters.';
    }
    return null;
  }

  Future<void> _forgotPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      setState(() {
        _error = 'Enter your email above, then tap "Forgot password".';
        _info = null;
      });
      return;
    }
    setState(() {
      _resetBusy = true;
      _error = null;
      _info = null;
    });
    try {
      await _auth.resetPassword(email);
      if (mounted) {
        setState(() =>
            _info = 'If an account exists for that email, a reset link is on its way.');
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not send the reset email. Try again.');
      }
    } finally {
      if (mounted) setState(() => _resetBusy = false);
    }
  }

  Future<void> _submit() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      if (_isSignUp) {
        await _auth.signUp(_email.text, _password.text);
      } else {
        await _auth.signIn(_email.text, _password.text);
      }
      if (!mounted) return;
      // Return to wherever the user came from. If /auth was the initial
      // route (deep link), there is nothing to pop: go home instead.
      final popped = await Navigator.of(context).maybePop();
      if (!popped && mounted) {
        Navigator.of(context).pushReplacementNamed('/');
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const MetlyDrawer(),
      appBar: const MetlyAppBar(titleTop: 'Account', titleBottom: 'Metly'),
      backgroundColor: const Color(0xFF0E0E0E),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _isSignUp ? 'Create your account' : 'Sign in',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      color: Cfg.gold,
                      fontSize: 22,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  'Save your watchlist and portfolio to your account.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  style: const TextStyle(color: Colors.white),
                  decoration: _deco('Email', Icons.mail_outline),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: _obscure,
                  autofillHints: [
                    _isSignUp
                        ? AutofillHints.newPassword
                        : AutofillHints.password
                  ],
                  style: const TextStyle(color: Colors.white),
                  decoration: _deco('Password', Icons.lock_outline).copyWith(
                    suffixIcon: IconButton(
                      tooltip: _obscure ? 'Show password' : 'Hide password',
                      icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: Colors.white54),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  onSubmitted: (_) => _busy ? null : _submit(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.redAccent, fontSize: 13)),
                ],
                if (_info != null) ...[
                  const SizedBox(height: 12),
                  Text(_info!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.greenAccent, fontSize: 13)),
                ],
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: (_busy || _resetBusy) ? null : _forgotPassword,
                    child: Text(
                      _resetBusy ? 'Sending…' : 'Forgot password?',
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: Cfg.gold,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5))
                      : Text(_isSignUp ? 'Create account' : 'Sign in',
                          style:
                              const TextStyle(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _isSignUp = !_isSignUp;
                            _error = null;
                            _info = null;
                          }),
                  child: Text(
                    _isSignUp
                        ? 'Already have an account? Sign in'
                        : 'New to Metly? Create an account',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _deco(String label, IconData icon) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        prefixIcon: Icon(icon, color: Colors.white54),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.white24)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Cfg.gold)),
      );
}
