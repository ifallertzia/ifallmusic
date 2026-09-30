import 'package:flutter_test/flutter_test.dart';
import 'package:ifallmusic/core/utils/audio_container.dart';
import 'package:ifallmusic/ui/shell/shell_controller.dart';

void main() {
  test('back replays tab visits and only exits at home', () {
    final shell = ShellController();
    shell.goSearch('Song');
    shell.goLibrary();
    shell.goSettings();
    expect(shell.back(), isTrue);
    expect(shell.tab, SaxifyTab.library);
    expect(shell.back(), isTrue);
    expect(shell.tab, SaxifyTab.search);
    expect(shell.back(), isTrue);
    expect(shell.tab, SaxifyTab.home);
    expect(shell.back(), isFalse);
    shell.dispose();
  });
  test('duplicate tabs do not add history; explicit home is exit boundary', () {
    final shell = ShellController();
    shell.goSearch();
    shell.goSearch('new');
    shell.goLibrary();
    shell.goHome();
    expect(shell.back(), isFalse);
    shell.dispose();
  });
  test('Library opens Your Space instead of preselecting Liked', () {
    final shell = ShellController();
    expect(shell.libraryTab, LibraryTabs.overview);
    shell.goLiked();
    expect(shell.libraryTab, LibraryTabs.liked);
    shell.select(SaxifyTab.library);
    expect(shell.libraryTab, LibraryTabs.overview);
    shell.goHome();
    shell.select(SaxifyTab.library);
    expect(shell.libraryTab, LibraryTabs.overview);
    shell.dispose();
  });

  test('Library deep links are consumed once, so Back returns to the list', () {
    final shell = ShellController();
    shell.goLiked();
    expect(shell.libraryTab, LibraryTabs.liked);
    final int nonce = shell.libraryNonce;

    // The Library list opens the section as a pushed page and immediately
    // clears the request, so a second visit starts from the list again.
    shell.clearLibraryTab();
    expect(shell.libraryTab, LibraryTabs.overview);
    expect(shell.libraryNonce, greaterThan(nonce));

    shell.goDownloads();
    expect(shell.libraryTab, LibraryTabs.downloads);
    shell.select(SaxifyTab.library);
    expect(shell.libraryTab, LibraryTabs.overview);
    expect(shell.back(), isTrue);
    expect(shell.tab, SaxifyTab.home);
    shell.dispose();
  });

  test('download container uses honest extension and MIME', () {
    expect(
      audioContainer([0, 0, 0, 24, 0x66, 0x74, 0x79, 0x70]).extension,
      'm4a',
    );
    expect(audioContainer([0x1a, 0x45, 0xdf, 0xa3]).mime, 'audio/webm');
    expect(audioContainer([0x4f, 0x67, 0x67, 0x53]).extension, 'ogg');
    expect(
      () => audioContainer([60, 104, 116, 109, 108]),
      throwsFormatException,
    );
  });
}
