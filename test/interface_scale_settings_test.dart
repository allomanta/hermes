// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/config/setting_keys.dart';
import 'package:hermes/l10n/l10n.dart';
import 'package:hermes/pages/settings_style/settings_style.dart';
import 'package:hermes/widgets/interface_scale.dart';
import 'package:hermes/widgets/matrix.dart';
import 'package:hermes/widgets/theme_builder.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Client extends Fake implements Client {
  @override
  String get userID => '@preview';
  @override
  bool get formatLocalpart => false;
  @override
  bool get mxidLocalPartFallback => true;
  @override
  final Map<String, BasicEvent> accountData = {};
  @override
  final onSync = CachedStreamController<SyncUpdate>();
}

class _Matrix extends Fake with Diagnosticable implements MatrixState {
  @override
  final _Client client = _Client();
}

Future<InterfaceScaleController> _mountSettings(WidgetTester tester) async {
  final matrix = _Matrix();
  addTearDown(matrix.client.onSync.close);
  await tester.pumpWidget(
    InterfaceScale(
      child: ThemeBuilder(
        builder: (context, themeMode, primaryColor) =>
            Provider<MatrixState>.value(
              value: matrix,
              child: MaterialApp(
                localizationsDelegates: L10n.localizationsDelegates,
                supportedLocales: L10n.supportedLocales,
                home: const SettingsStyle(),
              ),
            ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return Provider.of<InterfaceScaleController>(
    tester.element(find.byType(SettingsStyle)),
    listen: false,
  );
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
  });
  setUp(() async {
    await AppSettings.store.clear();
  });

  testWidgets('Appearance scale changes and reset update saved values', (
    tester,
  ) async {
    final controller = await _mountSettings(tester);
    expect(find.text('Interface scale'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    final slider = tester.widget<Slider>(find.byType(Slider).first);
    slider.onChanged!(1.25);
    await tester.pumpAndSettle();
    expect(controller.value, 1.25);
    expect(find.text('125%'), findsOneWidget);
    expect(AppSettings.interfaceScale.value, 1.25);
    expect(AppSettings.fontSizeFactor.value, 1.0);
    await tester.tap(find.byTooltip('Reset'));
    await tester.pumpAndSettle();
    expect(controller.value, 1.0);
    expect(find.text('100%'), findsOneWidget);
    expect(AppSettings.interfaceScale.value, 1.0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Appearance controls fit a phone at maximum zoom', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await AppSettings.interfaceScale.setItem(1.5);
    await _mountSettings(tester);
    expect(find.text('150%'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Reset'));
    await tester.pumpAndSettle();
    expect(find.text('100%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
