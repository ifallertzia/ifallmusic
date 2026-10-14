import 'package:flutter/material.dart';

import '../../config/branding.dart';
import '../../core/theme/sidify_theme.dart';
import '../widgets/sidify_widgets.dart';

/// First run: the site's welcome — Sidify mark, one name field, listen.
/// Asking nothing but the name keeps the promise honest (no signup, no
/// ads, no "sign in to continue").
class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key, required this.onComplete});

  /// Called with the listener's name when they press Continue.
  final Future<void> Function(String name) onComplete;

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  final TextEditingController _controller = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final String name = _controller.text.trim();
    if (name.isEmpty || _busy) return;
    setState(() => _busy = true);
    await widget.onComplete(name);
  }

  @override
  Widget build(BuildContext context) {
    final SidifyTokens t = context.sidify;
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 40, 28, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Spacer(flex: 2),
              const SidifyLogoMark(size: 84),
              const SizedBox(height: 22),
              Text(
                'Welcome to Sidify',
                style: SidifyText.display(t.text),
              ),
              const SizedBox(height: 10),
              Text(
                SidifyBranding.tagline +
                    '. Play anything, keep your library, and listen '
                        'together — all on this phone.',
                style: TextStyle(fontSize: 15, height: 1.5, color: t.text2),
              ),
              const SizedBox(height: 36),
              Text(
                'WHAT SHOULD WE CALL YOU?',
                style: SidifyText.eyebrow(t.text2),
              ),
              const SizedBox(height: 10),
              Container(
                height: 52,
                decoration: BoxDecoration(
                  color: t.fill,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: t.edge, width: 0.5),
                ),
                child: Row(
                  children: <Widget>[
                    const SizedBox(width: 16),
                    Icon(Icons.person_rounded, size: 20, color: t.text2),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        autofocus: true,
                        textCapitalization: TextCapitalization.words,
                        style: TextStyle(fontSize: 17, color: t.text),
                        decoration: InputDecoration(
                          hintText: 'Your name',
                          hintStyle: TextStyle(color: t.text2),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                        onSubmitted: (_) => _continue(),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(flex: 3),
              SidifyButton(
                label: _busy ? 'One moment…' : 'Continue',
                icon: Icons.arrow_forward_rounded,
                onTap: _busy ? null : _continue,
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'No account, no email, nothing leaves this phone.',
                  style: TextStyle(fontSize: 12.5, color: t.text3),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
