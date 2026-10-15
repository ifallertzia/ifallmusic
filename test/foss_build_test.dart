import 'package:flutter_test/flutter_test.dart';
import 'package:ifallmusic/config/foss_build.dart';

void main() {
  test('default CI/GitHub binaries keep the in-app updater', () {
    expect(FossBuild.fdroidDefine, isFalse);
    expect(FossBuild.flavor, isEmpty);
    expect(FossBuild.isFdroid, isFalse);
    expect(FossBuild.githubUpdaterEnabled, isTrue);
  });
}
