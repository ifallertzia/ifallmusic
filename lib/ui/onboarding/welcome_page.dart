import 'package:flutter/material.dart';

import '../../config/branding.dart';
import '../../core/theme/glass.dart';
import '../../core/theme/saxify_accents.dart';
import '../../core/theme/saxify_theme.dart';
import '../widgets/saxify_logo.dart';

/// First-launch profile setup, in the liquid-glass look.
///
/// The name is stored locally and used throughout IfallMusic; there is no
/// email sign-up or account requirement.
class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key, required this.onComplete});

  final Future<void> Function(String name) onComplete;

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  final TextEditingController _name = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final String value = _name.text.trim();
    if (value.isEmpty) {
      setState(() => _error = 'Please enter a name to continue.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onComplete(value);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save your name. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final SaxifyAccent accent = context.accent;
    return AuroraBackdrop(
      intensity: 1.2,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bool small = constraints.maxWidth < 360;
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 24, 22, 32),
                    child: GlassPanel(
                      glow: true,
                      padding: const EdgeInsets.fromLTRB(20, 26, 20, 22),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          SaxifyLogo(size: small ? 80 : 100, accent: accent),
                          const SizedBox(height: 20),
                          ShaderMask(
                            blendMode: BlendMode.srcIn,
                            shaderCallback: (Rect bounds) =>
                                accent.horizontalGradient.createShader(bounds),
                            child: Text(
                              IfallBranding.appName,
                              style: SaxifyTheme.appleFont(
                                size: small ? 28 : 34,
                                weight: FontWeight.w800,
                                letterSpacing: -1.2,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            IfallBranding.tagline,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12.5,
                              letterSpacing: 0.6,
                              color: SaxifyColors.textMuted,
                            ),
                          ),
                          const SizedBox(height: 26),
                          Text(
                            "Who's listening?",
                            textAlign: TextAlign.center,
                            style: SaxifyTheme.appleFont(
                              size: small ? 23 : 26,
                              weight: FontWeight.w800,
                              letterSpacing: -0.8,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Choose a name for your music space. You can change it later in Settings.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13.5,
                              height: 1.5,
                              color: SaxifyColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 22),
                          TextField(
                            controller: _name,
                            autofocus: true,
                            maxLength: 32,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _continue(),
                            decoration: InputDecoration(
                              hintText: 'Your name',
                              counterText: '',
                              prefixIcon: Icon(
                                Icons.person_outline_rounded,
                                color: accent.primary,
                              ),
                              errorText: _error,
                            ),
                          ),
                          const SizedBox(height: 16),
                          GlassButton(
                            label: _saving ? 'Saving…' : 'Enter ${IfallBranding.appName}',
                            icon: Icons.arrow_forward_rounded,
                            expand: true,
                            onPressed: _saving ? null : _continue,
                          ),
                          const SizedBox(height: 16),
                          const Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            runSpacing: 8,
                            children: <Widget>[
                              GlassTag('Ad-free listening', icon: Icons.block_rounded),
                              GlassTag('Offline downloads', icon: Icons.download_rounded),
                              GlassTag('8D audio · coming soon', icon: Icons.surround_sound_rounded),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
