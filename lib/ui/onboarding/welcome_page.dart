import 'package:flutter/material.dart';

import '../../config/branding.dart';
import '../../core/theme/ifall_ui.dart';

/// First-launch profile setup.
///
/// BitChord's onboarding is a single card on true black: the chubby mascot,
/// the wordmark, one field, one pill. The name is stored locally and used
/// throughout IfallMusic; there is no email sign-up or account requirement.
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
    final IfallPalette c = IfallPalette.of(context);
    final Color onAccent =
        ThemeData.estimateBrightnessForColor(c.accent) == Brightness.dark
            ? Colors.white
            : Colors.black;

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool small = constraints.maxWidth < 360;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 24, 22, 32),
                  child: IfallGlass(
                    radius: IfallUI.rXl,
                    blur: 0,
                    padding: const EdgeInsets.fromLTRB(20, 26, 20, 22),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        // The chubby mascot, tinted by the live accent.
                        Image.asset(
                          IfallBranding.logoAsset,
                          width: small ? 96 : 120,
                          height: small ? 96 : 120,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(height: 18),
                        Text(
                          IfallBranding.appName,
                          textAlign: TextAlign.center,
                          style: IfallText.style(
                            small ? 28 : 34,
                            weight: FontWeight.w800,
                            letterSpacing: -1.2,
                            color: c.accent,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          IfallBranding.tagline,
                          textAlign: TextAlign.center,
                          style: IfallText.caption(c.onSurfaceVariant),
                        ),
                        const SizedBox(height: 26),
                        Text(
                          "Who's listening?",
                          textAlign: TextAlign.center,
                          style: IfallText.style(
                            small ? 23 : 26,
                            weight: FontWeight.w800,
                            letterSpacing: -0.8,
                            color: c.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Choose a name for your music space. You can change it later in Settings.',
                          textAlign: TextAlign.center,
                          style: IfallText.body(c.onSurfaceVariant),
                        ),
                        const SizedBox(height: 22),
                        TextField(
                          controller: _name,
                          autofocus: true,
                          maxLength: 32,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _continue(),
                          style: IfallText.body(c.onSurface),
                          decoration: InputDecoration(
                            hintText: 'Your name',
                            counterText: '',
                            prefixIcon: Icon(
                              Icons.person_outline_rounded,
                              color: c.accent,
                            ),
                            errorText: _error,
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: FilledButton.icon(
                            onPressed: _saving ? null : _continue,
                            style: FilledButton.styleFrom(
                              backgroundColor: c.accent,
                              foregroundColor: onAccent,
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(IfallUI.rPill),
                              ),
                            ),
                            icon: _saving
                                ? SizedBox(
                                    width: 17,
                                    height: 17,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: onAccent,
                                    ),
                                  )
                                : const Icon(Icons.arrow_forward_rounded),
                            label: Text(
                              'Enter ${IfallBranding.appName}',
                              style: IfallText.body(onAccent).copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            IfallChip(
                              label: 'Ad-free listening',
                              icon: Icons.block_rounded,
                              selected: false,
                              onTap: () {},
                            ),
                            IfallChip(
                              label: 'Offline downloads',
                              icon: Icons.download_rounded,
                              selected: false,
                              onTap: () {},
                            ),
                            IfallChip(
                              label: 'Listen Together',
                              icon: Icons.groups_rounded,
                              selected: false,
                              onTap: () {},
                            ),
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
    );
  }
}
