import 'package:flutter/foundation.dart';

/// The five destinations of the floating tab bar, in order.
enum SidifyTab { home, explore, search, library, together }

/// Sub-view inside the Search tab:
/// - [chooser]: asks between Music and Movies & Series
/// - [music]: existing untouched Music search experience
/// - [movies]: Movies & Series search, recommended catalog, and downloads
enum SearchMode { chooser, music, movies }

/// Owns which tab is showing, a small back-history of tab visits, and the
/// query handed to the Search tab from elsewhere (Home chips, artist pages…).
///
/// Back behaviour mirrors the site: back replays tab visits and only leaves
/// the app at Home. [back] returns true when it consumed the press.
class SidifyShellController extends ChangeNotifier {
  SidifyTab _tab = SidifyTab.home;
  SearchMode _searchMode = SearchMode.chooser;
  final List<SidifyTab> _history = <SidifyTab>[];
  String _searchQuery = '';
  int _searchNonce = 0;

  SidifyTab get tab => _tab;
  int get index => _tab.index;
  SearchMode get searchMode => _searchMode;

  /// The query the Search tab should adopt, and a nonce that changes even
  /// when the same query is handed over twice.
  String get searchQuery => _searchQuery;
  int get searchNonce => _searchNonce;

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
    _searchMode =
        query.trim().isNotEmpty ? SearchMode.music : SearchMode.chooser;
    select(SidifyTab.search);
    notifyListeners();
  }

  /// Consumes a back press by returning to the previous tab. False at Home,
  /// where the press should leave the app.
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
