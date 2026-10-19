import 'dart:async';
import 'package:flutter/material.dart';

/// Lightweight first frame while native services and the library are loading.
class BootScreen extends StatefulWidget {
  const BootScreen({super.key});

  @override
  State<BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends State<BootScreen> {
  Timer? _timer;
  int _tick = 0;
  static const _lines = <String>[
    'from feed import library, recommendations',
    'tracks = library.restore()',
    'for song in tracks: cache_artwork(song)',
    'radio = recommendations.connect(tracks)',
    'feed = sorted(radio, key=lambda s: s.vibe)',
    'player.prepare(feed)',
  ];

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 90), (_) {
      if (mounted) setState(() => _tick++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: const Color(0xff080e11),
      body: SafeArea(child: Column(children: [
        const Spacer(),
        SizedBox(height: 220, child: ClipRect(child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (int i = 0; i < 8; i++) Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 22),
            child: Text('>>> ${_lines[(_tick ~/ 2 + i) % _lines.length]}',
              maxLines: 1, overflow: TextOverflow.fade,
              style: TextStyle(fontFamily: 'monospace', fontSize: 12,
                color: Colors.greenAccent.withValues(alpha: 0.3 + i * 0.09))),
          )],
        ))),
        const SizedBox(height: 32),
        const Text('Setting up your feed', style: TextStyle(
          color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 24),
        SizedBox(height: 90, child: Row(mainAxisAlignment: MainAxisAlignment.center,
          children: [for (int i = 0; i < 5; i++) Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Container(width: 56, height: 76,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(8),
                gradient: LinearGradient(colors: [
                  Colors.primaries[(i * 3 + _tick ~/ 12) % Colors.primaries.length].shade700,
                  const Color(0xff14232a),
                ])),
              child: const Icon(Icons.music_note, color: Colors.white70)),
          )])),
        const Spacer(),
        const Padding(padding: EdgeInsets.only(bottom: 36),
          child: CircularProgressIndicator(color: Colors.greenAccent)),
      ])),
    ),
  );
}
