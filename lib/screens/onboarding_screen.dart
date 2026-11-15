import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../services/auth_service.dart';

/// First-run onboarding shown once after install.
///
/// Shown only when [completeFlag] is not set; upgrades with the flag already
/// stored never see it again. Three steps, all optional-relevant:
/// welcome, optional account, finish. No permission prompts and no paywall.
class OnboardingScreen extends StatefulWidget {
  final SharedPreferences prefs;

  /// Auth service override for tests; defaults to [metlyDefaultAuth].
  final AuthService? auth;
  const OnboardingScreen({super.key, required this.prefs, this.auth});

  static const String completeFlag = 'onboarding_complete_v1';

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _step = 0;
  static const int _stepCount = 3;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int step) {
    _controller.animateToPage(step,
        duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  Future<void> _finish() async {
    await widget.prefs.setBool(OnboardingScreen.completeFlag, true);
    if (mounted) Navigator.pushReplacementNamed(context, '/');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E0E),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 64),
                    child: _step > 0
                        ? TextButton(
                            key: const Key('onboard_back'),
                            onPressed: () => _goTo(_step - 1),
                            child: const Text('Back',
                                softWrap: false,
                                style: TextStyle(color: Colors.white70)),
                          )
                        : null,
                  ),
                  const Spacer(),
                  Text('Step ${_step + 1} of $_stepCount',
                      key: const Key('onboard_step_label'),
                      style: const TextStyle(color: Colors.white54, fontSize: 13)),
                  const Spacer(),
                  const SizedBox(width: 64),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _controller,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _step = i),
                children: [
                  _WelcomeStep(onBegin: () => _goTo(1)),
                  _AccountStep(
                    signedIn:
                        (widget.auth ?? metlyDefaultAuth()).current != null,
                    onSignIn: () async {
                      await Navigator.pushNamed(context, '/auth');
                      if (mounted) setState(() {});
                    },
                    onSkip: () => _goTo(2),
                  ),
                  _FinishStep(onFinish: _finish),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepShell extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final List<Widget> actions;
  const _StepShell(
      {required this.icon,
      required this.title,
      required this.body,
      required this.actions});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
          Icon(icon, color: Cfg.gold, size: 64),
          const SizedBox(height: 24),
          Text(title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Cfg.gold, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Text(body,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white70, height: 1.5)),
          const SizedBox(height: 36),
          ...actions,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WelcomeStep extends StatelessWidget {
  final VoidCallback onBegin;
  const _WelcomeStep({required this.onBegin});

  @override
  Widget build(BuildContext context) {
    return _StepShell(
      icon: Icons.trending_up,
      title: 'Welcome to Metly',
      body: 'Track live gold & silver prices, build your watchlist, '
          'and get SIP tips with AI insights.',
      actions: [
        ElevatedButton(
          key: const Key('onboard_begin'),
          style: ElevatedButton.styleFrom(
              backgroundColor: Cfg.gold,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30))),
          onPressed: onBegin,
          child: const Text('Begin setup',
              style: TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

class _AccountStep extends StatelessWidget {
  final bool signedIn;
  final VoidCallback onSignIn;
  final VoidCallback onSkip;
  const _AccountStep(
      {required this.signedIn, required this.onSignIn, required this.onSkip});

  @override
  Widget build(BuildContext context) {
    if (signedIn) {
      return _StepShell(
        icon: Icons.check_circle_outline,
        title: "You're signed in",
        body: 'Your watchlist and portfolio will sync to this account '
            'across your devices.',
        actions: [
          ElevatedButton(
            key: const Key('onboard_continue'),
            style: ElevatedButton.styleFrom(
                backgroundColor: Cfg.gold,
                foregroundColor: Colors.black,
                padding:
                    const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30))),
            onPressed: onSkip,
            child: const Text('Continue',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      );
    }
    return _StepShell(
      icon: Icons.cloud_sync_outlined,
      title: 'Save your watchlist',
      body: 'Sign in with your email to save your watchlist and portfolio '
          'to your account and sync them across your devices.\n\n'
          'You can browse prices without an account.',
      actions: [
        ElevatedButton.icon(
          key: const Key('onboard_signin'),
          style: ElevatedButton.styleFrom(
              backgroundColor: Cfg.gold,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30))),
          icon: const Icon(Icons.login),
          label: const Text('Sign in',
              style: TextStyle(fontWeight: FontWeight.w600)),
          onPressed: onSignIn,
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          key: const Key('onboard_skip_account'),
          style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: const BorderSide(color: Colors.white38),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30))),
          onPressed: onSkip,
          child: const Text('Continue without account',
              style: TextStyle(fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }
}

class _FinishStep extends StatelessWidget {
  final VoidCallback onFinish;
  const _FinishStep({required this.onFinish});

  @override
  Widget build(BuildContext context) {
    return _StepShell(
      icon: Icons.check_circle_outline,
      title: "You're all set",
      body: 'Start tracking live prices from your dashboard.',
      actions: [
        ElevatedButton(
          key: const Key('onboard_finish'),
          style: ElevatedButton.styleFrom(
              backgroundColor: Cfg.gold,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30))),
          onPressed: onFinish,
          child: const Text('Finish',
              style: TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}
