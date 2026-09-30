// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/config/setting_keys.dart';
import 'package:hermes/config/themes.dart';
import 'package:hermes/widgets/interface_scale.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
  });

  setUp(() async {
    await AppSettings.store.clear();
  });

  test(
    'scale changes are bounded, rounded and restored from preferences',
    () async {
      final controller = InterfaceScaleController();
      addTearDown(controller.dispose);
      expect(controller.value, 1.0);
      await controller.setScale(1.254);
      expect(controller.value, 1.25);
      expect(AppSettings.interfaceScale.value, 1.25);
      final restored = InterfaceScaleController();
      addTearDown(restored.dispose);
      expect(restored.value, 1.25);
      await controller.setScale(3);
      expect(controller.value, 1.5);
      await controller.setScale(0);
      expect(controller.value, 0.75);
      await controller.setScale(double.nan);
      expect(controller.value, 1.0);
    },
  );

  for (final scale in [0.75, 1.0, 1.5]) {
    testWidgets('scales geometry and viewport metrics at $scale', (
      tester,
    ) async {
      await AppSettings.interfaceScale.setItem(scale);
      const marker = ValueKey('marker');
      const data = MediaQueryData(
        size: Size(800, 600),
        devicePixelRatio: 2,
        padding: EdgeInsets.all(12),
        viewPadding: EdgeInsets.all(24),
        viewInsets: EdgeInsets.only(bottom: 120),
        systemGestureInsets: EdgeInsets.all(6),
        textScaler: TextScaler.linear(1.2),
        displayFeatures: [
          DisplayFeature(
            bounds: Rect.fromLTWH(400, 0, 12, 600),
            type: DisplayFeatureType.hinge,
            state: DisplayFeatureState.postureFlat,
          ),
        ],
      );
      MediaQueryData? scaledData;
      var taps = 0;
      await tester.pumpWidget(
        MediaQuery(
          data: data,
          child: InterfaceScale(
            child: MaterialApp(
              home: Builder(
                builder: (context) {
                  scaledData = MediaQuery.of(context);
                  return Align(
                    alignment: Alignment.topLeft,
                    child: GestureDetector(
                      onTap: () => taps++,
                      child: const SizedBox(
                        key: marker,
                        width: 100,
                        height: 50,
                        child: ColoredBox(color: Colors.blue),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(scaledData!.size, data.size / scale);
      expect(scaledData!.devicePixelRatio, 2 * scale);
      expect(scaledData!.padding, data.padding / scale);
      expect(scaledData!.viewPadding, data.viewPadding / scale);
      expect(scaledData!.viewInsets, data.viewInsets / scale);
      expect(scaledData!.systemGestureInsets, data.systemGestureInsets / scale);
      expect(scaledData!.textScaler.scale(10), 12);
      expect(scaledData!.displayFeatures.single.bounds.left, 400 / scale);
      final size =
          tester.getBottomRight(find.byKey(marker)) -
          tester.getTopLeft(find.byKey(marker));
      expect(size.dx, closeTo(100 * scale, 0.01));
      expect(size.dy, closeTo(50 * scale, 0.01));
      await tester.tapAt(Offset(50 * scale, 25 * scale));
      expect(taps, 1);
      expect(
        PantheonThemes.isColumnModeByWidth(scaledData!.size.width),
        scale < 1,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
