import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config/branding.dart';
import 'core/models/playlist.dart';
import 'core/models/song.dart';
import 'core/services/app_feedback.dart';
import 'core/services/artist_service.dart';
import 'core/services/boot_log.dart';
import 'core/services/home_catalog.dart';
import 'core/services/library_service.dart';
import 'core/services/local_music_service.dart';
import 'core/services/music_download_service.dart';
import 'core/services/native_bridge.dart';
import 'core/services/notification_bootstrap.dart';
import 'core/services/playback_service.dart';
import 'core/services/playlist_sync_service.dart';
import 'core/services/recommendation_service.dart';
import 'core/services/recommendation_worker.dart';
import 'core/services/settings_service.dart';
import 'core/services/youtube_service.dart';
import 'core/theme/glass.dart';
import 'core/theme/saxify_accents.dart';
import 'core/theme/saxify_theme.dart';
import 'core/theme/theme_controller.dart';
import 'ui/onboarding/welcome_page.dart';
import 'ui/shell/saxify_shell.dart';
import 'ui/shell/shell_controller.dart';

Future<void> _restoreEqualizerForPlayback(
  SettingsService settings,
  PlaybackService playback,
) async {
  final List<int> levels = settings.equalizerLevels;
  final bool requested = settings.equalizerEnabled && levels.isNotEmpty;
  bool applied = false;
  if (requested) {
    final int? session = playback.player.androidAudioSessionId;
    if (session != null && session != 0) {
      final EqualizerInfo? info = await NativeBridge.eqInit(session);
      if (info != null && info.supported) {
        for (int i = 0; i < levels.length && i < info.bands; i++) {
          await NativeBridge.eqSetBand(i, levels[i]);
        }
        await NativeBridge.eqSetEnabled(true);
        applied = true;
      }
    }
  }
  showAppNotice(applied
      ? 'Playing in this equalizer: ${settings.equalizerProfileName}'
      : 'Playing in Original audio');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    BootLog.write(details.exceptionAsString());
  };
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    BootLog.write('$error\n$stack');
    return true;
  };

  runZonedGuarded(
    () async {
      AppBoot? boot;
      try {
        boot = await _initializeApp().timeout(const Duration(seconds: 20));
      } catch (error, stack) {
        BootLog.write('init failed: $error\n$stack');
      }
      if (boot == null) {
        runApp(const IfallRecoveryApp());
        return;
      }
      runApp(IfallMusicApp(boot: boot));
    },
    (Object error, StackTrace stack) {
      BootLog.write('Zone error: $error\n$stack');
      runApp(const IfallRecoveryApp());
    },
  );
}

Future<AppBoot> _initializeApp() async {
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]).timeout(const Duration(seconds: 1), onTimeout: () {});

  final BootSnapshot native = await NativeBridge.bootState();
  if (native.safeMode) {
    BootLog.write('safe mode — skipping notification and recommendation init');
  }

  final SharedPreferences prefs = await SharedPreferences.getInstance().timeout(
    const Duration(seconds: 3),
  );
  await _migrateLegacyKeys(prefs);

  // The notification/media session is what keeps Android audio alive after
  // the app is backgrounded. Its failure is isolated internally, so still try
  // it in safe mode rather than silently dropping background playback.
  await NotificationBootstrap.init();

  final SettingsService settings = SettingsService(prefs);
  final LibraryService library = LibraryService(prefs);
  final LocalMusicService localMusic = LocalMusicService(prefs);
  final YoutubeService youtube = YoutubeService();
  final PlaybackService playback = PlaybackService(
    youtube: youtube,
    settings: settings,
    library: library,
  );
  final MusicDownloadService musicDownloads = MusicDownloadService(
    prefs: prefs,
  );
  await playback.restorePersistedQueue();
  NotificationBootstrap.handler?.attach(
    playback,
    library,
    localMusic: localMusic,
    downloads: musicDownloads,
  );
  library.onUserNotice = showAppNotice;
  final RecommendationService recommendations = RecommendationService(
    youtube: youtube,
  );
  final ArtistService artists = ArtistService(youtube: youtube);
  // Ensure an older saved 8D effect is disabled while the feature is Coming soon.
  await NativeBridge.spatialDisable();

  playback.onTrackStarted = (Song song) {
    recommendations.notePlay(song);
    recommendations.refresh(current: song, force: true);
    unawaited(_restoreEqualizerForPlayback(settings, playback));
  };
  playback.onTrackSkipped = recommendations.noteSkip;
  library.onLikeChanged = (Song song, bool liked) {
    if (liked) recommendations.noteLike(song);
  };

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.black,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  return AppBoot(
    settings: settings,
    library: library,
    localMusic: localMusic,
    youtube: youtube,
    playback: playback,
    recommendations: recommendations,
    artists: artists,
    musicDownloads: musicDownloads,
    safeMode: native.safeMode,
  );
}

/// Copies preference blobs written before the rename. The old prefix is built
/// from codes so a brand string is not reintroduced into the tree.
Future<void> _migrateLegacyKeys(SharedPreferences prefs) async {
  final String old = String.fromCharCodes(const <int>[
    115,
    105,
    100,
    105,
    102,
    121,
  ]);
  for (final String key in prefs.getKeys().toList()) {
    if (!key.startsWith('$old.')) continue;
    final String next = 'saxify.${key.substring(old.length + 1)}';
    if (prefs.containsKey(next)) continue;
    final Object? value = prefs.get(key);
    if (value is String) {
      await prefs.setString(next, value);
    } else if (value is bool) {
      await prefs.setBool(next, value);
    } else if (value is int) {
      await prefs.setInt(next, value);
    } else if (value is double) {
      await prefs.setDouble(next, value);
    } else if (value is List<String>) {
      await prefs.setStringList(next, value);
    }
  }
}

class AppBoot {
  const AppBoot({
    required this.settings,
    required this.library,
    required this.localMusic,
    required this.youtube,
    required this.playback,
    required this.recommendations,
    required this.artists,
    required this.musicDownloads,
    required this.safeMode,
  });

  final SettingsService settings;
  final LibraryService library;
  final LocalMusicService localMusic;
  final YoutubeService youtube;
  final PlaybackService playback;
  final RecommendationService recommendations;
  final ArtistService artists;
  final MusicDownloadService musicDownloads;
  final bool safeMode;
}

class IfallMusicApp extends StatefulWidget {
  const IfallMusicApp({super.key, required this.boot});

  final AppBoot boot;

  @override
  State<IfallMusicApp> createState() => _IfallMusicAppState();
}

class _IfallMusicAppState extends State<IfallMusicApp>
    with WidgetsBindingObserver {
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _afterFirstFrame());
  }

  Future<void> _afterFirstFrame() async {
    await NativeBridge.markLaunchSuccess();
    final AppBoot boot = widget.boot;
    if (boot.safeMode) return;
    try {
      await boot.recommendations.open().timeout(const Duration(seconds: 4));
      if (boot.recommendations.store.recovered) {
        BootLog.write('recommendation db recreated');
      }
    } catch (e) {
      BootLog.write('recommendation open skipped: $e');
    }
    boot.library.onPlaylistsChanged = () {
      if (!boot.settings.autoPlaylistSync) return;
      _syncTimer?.cancel();
      _syncTimer = Timer(const Duration(seconds: 8), () async {
        final String? code = await PlaylistSyncService.shareAllPlaylists(
          boot.library.playlists.map((Playlist p) => p.toJson()).toList(),
          copyToClipboard: false,
        );
        if (code != null) await boot.settings.setLastPlaylistCode(code);
      });
    };
    try {
      await registerRecommendationRefresh().timeout(const Duration(seconds: 3));
    } catch (e) {
      BootLog.write('workmanager skipped: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      unawaited(widget.boot.playback.persistQueueNow());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppBoot boot = widget.boot;
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsService>.value(value: boot.settings),
        ChangeNotifierProvider<LibraryService>.value(value: boot.library),
        ChangeNotifierProvider<LocalMusicService>.value(value: boot.localMusic),
        ChangeNotifierProvider<PlaybackService>.value(value: boot.playback),
        ChangeNotifierProvider<RecommendationService>.value(
          value: boot.recommendations,
        ),
        ChangeNotifierProvider<MusicDownloadService>.value(
          value: boot.musicDownloads,
        ),
        ChangeNotifierProvider<ThemeController>(
          create: (_) => ThemeController(boot.settings),
        ),
        ChangeNotifierProvider<HomeCatalog>(
          create: (_) => HomeCatalog(
            youtube: boot.youtube,
            library: boot.library,
            artists: boot.artists,
          ),
        ),
        ChangeNotifierProvider<ShellController>(
          create: (_) => ShellController(),
        ),
      ],
      child: Provider<YoutubeService>.value(
        value: boot.youtube,
        child: Provider<ArtistService>.value(
          value: boot.artists,
          child: Provider<bool>.value(
            value: boot.safeMode,
            child: const _IfallRoot(),
          ),
        ),
      ),
    );
  }
}

class IfallProfileGate extends StatelessWidget {
  const IfallProfileGate({super.key});

  @override
  Widget build(BuildContext context) {
    final SettingsService settings = context.watch<SettingsService>();
    if (settings.displayName.isEmpty) {
      return WelcomePage(onComplete: settings.setDisplayName);
    }
    return const SaxifyShell();
  }
}

class _IfallRoot extends StatelessWidget {
  const _IfallRoot();

  @override
  Widget build(BuildContext context) {
    final ThemeController theme = context.watch<ThemeController>();
    return MaterialApp(
      scaffoldMessengerKey: appMessengerKey,
      title: IfallBranding.appName,
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: SaxifyTheme.build(theme.accent),
      darkTheme: SaxifyTheme.build(theme.accent),
      builder: (BuildContext context, Widget? child) {
        // Apple-like restraint on huge system font scales: the layout keeps its
        // rhythm and text stays readable instead of overflowing.
        final MediaQueryData media = MediaQuery.of(context);
        final double scale = media.textScaler.scale(1).clamp(1.0, 1.3);
        return MediaQuery(
          data: media.copyWith(textScaler: TextScaler.linear(scale)),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const IfallProfileGate(),
    );
  }
}

/// Shown only when startup could not finish — black, quiet, one action.
class IfallRecoveryApp extends StatelessWidget {
  const IfallRecoveryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: SaxifyTheme.build(SaxifyAccents.violetPulse),
      home: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Image.asset(IfallBranding.logoAsset, width: 96, height: 96),
                const SizedBox(height: 20),
                Text(
                  'IfallMusic could not finish starting.',
                  textAlign: TextAlign.center,
                  style: SaxifyTheme.appleFont(
                    size: 19,
                    weight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Reset the local cache and try again. Your liked songs and playlists stay on this device.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: SaxifyColors.textMuted,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 22),
                GlassButton(
                  label: 'Reset and retry',
                  icon: Icons.refresh_rounded,
                  expand: true,
                  onPressed: () async {
                    await NativeBridge.clearLocalPrefs();
                    try {
                      final AppBoot boot = await _initializeApp().timeout(
                        const Duration(seconds: 20),
                      );
                      runApp(IfallMusicApp(boot: boot));
                    } catch (error) {
                      BootLog.write('retry failed: $error');
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
