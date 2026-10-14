import 'package:flutter_test/flutter_test.dart';
import 'package:ifallmusic/core/utils/audio_container.dart';
import 'package:ifallmusic/ui/shell/sidify_shell_controller.dart';

void main() {
  test('back replays tab visits and only exits at home', () {
    final SidifyShellController shell = SidifyShellController();
    shell.goSearch('Song');
    shell.goLibrary();
    shell.goTogether();
    expect(shell.back(), isTrue);
    expect(shell.tab, SidifyTab.library);
    expect(shell.back(), isTrue);
    expect(shell.tab, SidifyTab.search);
    expect(shell.back(), isTrue);
    expect(shell.tab, SidifyTab.home);
    expect(shell.back(), isFalse);
    shell.dispose();
  });

  test('duplicate tabs do not add history; explicit home is exit boundary', () {
    final SidifyShellController shell = SidifyShellController();
    shell.goSearch();
    shell.goSearch('new');
    shell.goLibrary();
    shell.goHome();
    expect(shell.back(), isFalse);
    shell.dispose();
  });

  test('search hand-off carries the query and bumps the nonce', () {
    final SidifyShellController shell = SidifyShellController();
    shell.goSearch('Believer');
    expect(shell.tab, SidifyTab.search);
    expect(shell.searchQuery, 'Believer');
    final int nonce = shell.searchNonce;
    shell.goHome();
    shell.goSearch('Believer');
    expect(shell.searchNonce, greaterThan(nonce));
    shell.dispose();
  });

  test('tab indices match the floating tab bar order', () {
    expect(SidifyTab.home.index, 0);
    expect(SidifyTab.explore.index, 1);
    expect(SidifyTab.search.index, 2);
    expect(SidifyTab.library.index, 3);
    expect(SidifyTab.together.index, 4);
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
