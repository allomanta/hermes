// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart' as emoji;
import 'package:flutter/material.dart' as flutter_material;
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/config/setting_keys.dart';
import 'package:hermes/l10n/l10n.dart';
import 'package:hermes/pages/chat/chat.dart';
import 'package:hermes/pages/chat/chat_emoji_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Client extends Fake implements Client {
  @override
  final Map<String, BasicEvent> accountData = {};
}

class _Room extends Fake implements Room {
  @override
  final client = _Client();
  @override
  final Map<String, Map<String, StrippedStateEvent>> states = {};
}

class _Controller extends ChatController {
  @override
  final Room room = _Room();
  String? selected;
  @override
  void onEmojiSelected(dynamic category, emoji.Emoji? emoji) {
    selected = emoji?.emoji;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'emoji search opens, filters and selects in ${brightness.name}',
      (tester) async {
        final controller = _Controller()..showEmojiPicker = true;
        addTearDown(controller.scrollController.dispose);
        addTearDown(controller.sendController.dispose);
        final theme = ThemeData(brightness: brightness);
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            locale: const Locale('en'),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(width: 400, child: ChatEmojiPicker(controller)),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.search));
        await tester.pumpAndSettle();
        final field = find.byType(flutter_material.TextField);
        expect(field, findsOneWidget);
        expect(tester.takeException(), isNull);
        final nativeTheme = flutter_material.Theme.of(tester.element(field));
        expect(nativeTheme.brightness, brightness);
        expect(nativeTheme.colorScheme.primary, theme.colorScheme.primary);
        await tester.enterText(field, 'fox');
        await tester.pumpAndSettle();
        expect(find.text('🦊'), findsOneWidget);
        await tester.tap(find.text('🦊'));
        await tester.pumpAndSettle();
        expect(controller.selected, '🦊');
        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();
        expect(find.byType(flutter_material.TextField), findsNothing);
        expect(find.byIcon(Icons.search), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
