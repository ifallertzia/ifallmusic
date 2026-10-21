import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The five destinations of the floating tab bar, in order.
enum SidifyTab { home, explore, search, library, together }

enum SearchMode { chooser, music, movies }

class SidifyShellController extends ChangeNotifier {
  SidifyShellController([this._prefs]) {
    final String? saved = _prefs?.getString(_modeKey);
    _ready = true;
    if (saved == 'music' || saved == 'movies') {
      _hasChoice = true;
      _moviesMode = saved == 'movies';
      _searchMode = _moviesMode ? SearchMode.movies : SearchMode.music;
    }
    notifyListeners();
  }

  static const String _modeKey = 'ifall.start_mode';
  final SharedPreferences? _prefs;

  SidifyTab _tab = SidifyTab.home;
  SearchMode _searchMode = SearchMode.chooser;
  final List<SidifyTab> _history = <SidifyTab>[];
  String _searchQuery = '';
  int _searchNonce = 0;
  bool _ready = false;
  bool _hasChoice = false;
  bool _moviesMode = false;

  SidifyTab get tab => _tab;
  int get index => _tab.index;
  SearchMode get searchMode => _searchMode;
  String get searchQuery => _searchQuery;
  int get searchNonce => _searchNonce;
  bool get ready => _ready;
  bool get hasModeChoice => _hasChoice;
  bool get isMoviesMode => _moviesMode;

  Future<void> chooseMode({required bool movies}) async {
    _moviesMode = movies;
    _hasChoice = true;
    _searchMode = movies ? SearchMode.movies : SearchMode.music;
    _tab = SidifyTab.home;
    _history.clear();
    notifyListeners();
    await _prefs?.setString(_modeKey, movies ? 'movies' : 'music');
  }

  Future<void> switchMode() => chooseMode(movies: !_moviesMode);

  Future<void> requireModeChoiceNextLaunch() async {
    await _prefs?.remove(_modeKey);
  }

  void setSearchMode(SearchMode mode) {
    if (_searchMode == mode) return;
    _searchMode = mode;
    notifyListeners();
  }

  void select(SidifyTab tab) {
    if (tab == _tab) return;
    _history.remove(tab);
    _history.add(_tab);
    _tab = tab;
    notifyListeners();
  }

  void goHome() => select(SidifyTab.home);
  void goExplore() => select(SidifyTab.explore);
  void goLibrary() => select(SidifyTab.library);
  void goTogether() => select(SidifyTab.together);

  void goSearch([String query = '']) {
    _searchQuery = query;
    _searchNonce++;
    _searchMode = _moviesMode ? SearchMode.movies : SearchMode.music;
    select(SidifyTab.search);
    notifyListeners();
  }

  bool back() {
    if (_tab == SidifyTab.home) return false;
    if (_history.isEmpty) {
      _tab = SidifyTab.home;
      notifyListeners();
      return true;
    }
    _tab = _history.removeLast();
    notifyListeners();
    return true;
  }
}
