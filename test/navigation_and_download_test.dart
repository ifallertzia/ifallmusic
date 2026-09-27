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
