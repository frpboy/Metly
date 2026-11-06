import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../widgets/common_widgets.dart';

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});
  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _message = TextEditingController();

  @override
  void initState() {
    super.initState();
    _message.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _email.dispose();
    _message.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Row(children: [
          Icon(Icons.check_circle_outline, color: Cfg.gold),
          SizedBox(width: 10),
          Text('Thank you! Feedback submitted.'),
        ]),
        behavior: SnackBarBehavior.floating));
    _message.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        drawer: const MetlyDrawer(),
        appBar: const MetlyAppBar(
            titleTop: 'Feedback', titleBottom: 'Tell us what to improve'),
        backgroundColor: const Color(0xFF0E0E0E),
        body: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Form(
                        key: _formKey,
                        child: Column(children: [
                          TextFormField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              labelText: 'Email (optional)',
                              labelStyle: TextStyle(color: Colors.white70),
                              hintText: 'name@example.com',
                              hintStyle: TextStyle(color: Colors.white38),
                              prefixIcon: Icon(Icons.email_outlined,
                                  color: Colors.white54),
                              enabledBorder: OutlineInputBorder(
                                  borderSide:
                                      BorderSide(color: Colors.white24)),
                              focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: Cfg.gold)),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _message,
                            style: const TextStyle(color: Colors.white),
                            minLines: 4,
                            maxLines: 6,
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Message required'
                                : null,
                            decoration: InputDecoration(
                              labelText: 'Your message',
                              labelStyle: const TextStyle(color: Colors.white70),
                              hintText: 'Share ideas, issues, or suggestions…',
                              hintStyle: const TextStyle(color: Colors.white38),
                              alignLabelWithHint: true,
                              prefixIcon: const Padding(
                                padding: EdgeInsets.only(bottom: 64),
                                child: Icon(Icons.chat_bubble_outline,
                                    color: Colors.white54),
                              ),
                              suffixIcon: _message.text.isNotEmpty
                                  ? IconButton(
                                      tooltip: 'Clear message',
                                      icon: const Icon(Icons.clear,
                                          color: Colors.white54),
                                      onPressed: () => _message.clear(),
                                    )
                                  : null,
                              enabledBorder: const OutlineInputBorder(
                                  borderSide:
                                      BorderSide(color: Colors.white24)),
                              focusedBorder: const OutlineInputBorder(
                                  borderSide: BorderSide(color: Cfg.gold)),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                      backgroundColor: Cfg.gold,
                                      foregroundColor: Colors.black,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 22, vertical: 14)),
                                  onPressed: _submit,
                                  icon: const Icon(Icons.send),
                                  label: const Text('Submit'))),
                        ]))))));
  }
}
