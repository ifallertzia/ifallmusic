import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ifallmusic/core/services/update_service.dart';
import 'package:ifallmusic/core/theme/sidify_theme.dart';
import 'package:ifallmusic/ui/settings/update_dialog.dart';

void main() {
  testWidgets('automatic offer has Later and does not stack dialogs', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(
      theme: SidifyTheme.build(Brightness.dark),
      home: Builder(builder: (c) {
        context = c;
        return const Scaffold();
      }),
    ));
    const info = UpdateInfo(
      currentVersion: '2.10.0', latestVersion: '2.11.0',
      apkUrl: 'https://github.com/example/app/releases/download/v2/app.apk',
    );
    final dialog = showUpdateDialog(context, info: info);
    await tester.pumpAndSettle();
    await showUpdateDialog(context, info: info);
    expect(find.text('New app available'), findsOneWidget);
    expect(find.text('Update now'), findsOneWidget);
    expect(find.text('Later'), findsOneWidget);
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    await dialog;
    expect(updateDialogOpen, isFalse);
  });
}
