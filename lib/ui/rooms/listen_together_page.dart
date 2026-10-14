import 'package:flutter/material.dart';

import '../../core/theme/sidify_theme.dart';
import '../widgets/sidify_widgets.dart';

/// Listen Together — the site's Rooms. The feature is not switched on yet:
/// every entry point (the Home invite, the player capsule, Settings) lands on
/// this Coming soon card instead of the room lobby.
class ListenTogetherPage extends StatelessWidget {
  const ListenTogetherPage({super.key, this.embedded = true});

  /// As a tab (inside the shell) vs pushed over it (from the player).
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final SidifyTokens t = context.sidify;
    final Widget body = SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 190),
        physics: const BouncingScrollPhysics(),
        children: <Widget>[
          const PageTitle('Listen Together'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.fromLTRB(22, 30, 22, 30),
              decoration: BoxDecoration(
                color: t.raised,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: t.edge, width: 0.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: t.brand.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.people_rounded,
                      size: 30,
                      color: t.brand,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(
                        'Listen Together',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                          color: t.text,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: t.fill2,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Coming soon',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: t.text2,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Start a room, share the code, and everyone hears the '
                    'same song at the same moment. This feature is on its '
                    'way — it will light up here soon.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: t.text2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    if (embedded) return body;
    return Scaffold(backgroundColor: t.bg, body: body);
  }
}
