import 'package:flutter/foundation.dart';

/// Bottom-nav tabs of IfallMusic.
///
/// The old build had five tabs including a "Save" section with a backend
/// downloader. That whole section is gone — the app now has four clean tabs and
/// downloads live where they belong: Library ▸ Downloads, plus a one-tap
/// download button in the Home header.
enum SaxifyTab { home, search, library, settings }

/// Index of the Library tabs, kept in one place so deep links stay honest.
class LibraryTabs {
  const LibraryTabs._();

  static const int liked = 0;
  static const int playlists = 1;
  static const int songs = 2;
  static const int artists = 3;
  static const int onDevice = 4;
  static const int downloads = 5;
  static const int history = 6;
  static const int lyrics = 7;
}

/// Coordinates the shell: which tab is showing and what the search box should
/// run. Mood chips on Home, "Show all" links and deep links all go through here.
class ShellController extends ChangeNotifier {
  SaxifyTab _tab = SaxifyTab.home;
  final List<SaxifyTab> _history = [];
  bool get canGoBack => _tab != SaxifyTab.home;
  void _visit(SaxifyTab next) {
    if (_tab == next) return;
    if (next == SaxifyTab.home) {
      _history.clear();
    } else {
      _history.add(_tab);
    }
    _tab = next;
  }

  bool back() {
    if (!canGoBack) return false;
    _tab = _history.isNotEmpty ? _history.removeLast() : SaxifyTab.home;
    notifyListeners();
    return true;
  }

  String? _pendingQuery;
  int _queryNonce = 0;
  int _libraryTab = LibraryTabs.liked;
  int _libraryNonce = 0;

  SaxifyTab get tab => _tab;

  /// Non-null when something asked the Search tab to run a query.
  String? get pendingQuery => _pendingQuery;
  int get queryNonce => _queryNonce;

  /// Which Library tab should be open (Library ▸ Liked by default — never
  /// surprising, never confusing).
  int get libraryTab => _libraryTab;
  int get libraryNonce => _libraryNonce;

  void select(SaxifyTab tab) {
    if (_tab == tab) return;
    _visit(tab);
    notifyListeners();
  }

  void goSearch([String? query]) {
    _visit(SaxifyTab.search);
    _pendingQuery = query;
    _queryNonce++;
    notifyListeners();
  }

  void goHome() {
    _visit(SaxifyTab.home);
    notifyListeners();
  }

  void goLibrary([int? tab]) {
    _visit(SaxifyTab.library);
    if (tab != null) {
      _libraryTab = tab;
      _libraryNonce++;
    }
    notifyListeners();
  }

  /// Library ▸ Downloads — the section the heart/download icon opens.
  void goDownloads() => goLibrary(LibraryTabs.downloads);

  void goLiked() => goLibrary(LibraryTabs.liked);

  void goSettings() {
    _visit(SaxifyTab.settings);
    notifyListeners();
  }

  void clearPendingQuery() {
    if (_pendingQuery == null) return;
    _pendingQuery = null;
    notifyListeners();
  }
}
