// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/config/setting_keys.dart';
import 'package:hermes/config/themes.dart';
import 'package:hermes/widgets/interface_scale.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<InterfaceScaleController> _mountApp(
  WidgetTester tester,
  Widget home,
) async {
  late InterfaceScaleController controller;
  await tester.pumpWidget(
    InterfaceScale(
      child: MaterialApp(
        home: Builder(
          builder: (context) {
            controller = InterfaceScaleController.of(context);
            return home;
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

Future<void> _sendZoomKey(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool shift = false,
}) async {
  final modifier = defaultTargetPlatform == TargetPlatform.macOS
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  // Use a complete simulator map; the shortcut modifier follows the target OS.
  await tester.sendKeyDownEvent(modifier, platform: 'macos');
  if (shift) {
    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.shiftLeft,
      platform: 'macos',
    );
  }
  await tester.sendKeyEvent(
    key,
    platform: 'macos',
    physicalKey: key == LogicalKeyboardKey.add
        ? PhysicalKeyboardKey.equal
        : null,
  );
  if (shift) {
    await tester.sendKeyUpEvent(
      LogicalKeyboardKey.shiftLeft,
      platform: 'macos',
    );
  }
  await tester.sendKeyUpEvent(modifier, platform: 'macos');
  await tester.pumpAndSettle();
}

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

  testWidgets(
    'desktop zoom keys work with editor focus and preserve the draft',
    (tester) async {
      final text = TextEditingController(text: 'A draft');
      final focus = FocusNode();
      addTearDown(text.dispose);
      addTearDown(focus.dispose);
      final controller = await _mountApp(
        tester,
        Scaffold(
          body: TextField(controller: text, focusNode: focus, autofocus: true),
        ),
      );
      for (final (key, shift) in [
        (LogicalKeyboardKey.equal, false),
        (LogicalKeyboardKey.equal, true),
        (LogicalKeyboardKey.add, true),
        (LogicalKeyboardKey.numpadAdd, false),
      ]) {
        final previous = controller.value;
        await _sendZoomKey(tester, key, shift: shift);
        expect(controller.value, closeTo(previous + 0.1, 0.001));
        expect(text.text, 'A draft');
        expect(focus.hasFocus, isTrue);
      }
      await _sendZoomKey(tester, LogicalKeyboardKey.digit0);
      expect(controller.value, 1.0);
      await _sendZoomKey(tester, LogicalKeyboardKey.minus);
      expect(controller.value, 0.9);
      await _sendZoomKey(tester, LogicalKeyboardKey.numpadSubtract);
      expect(controller.value, 0.8);
      await _sendZoomKey(tester, LogicalKeyboardKey.numpad0);
      expect(controller.value, 1.0);
      expect(AppSettings.interfaceScale.value, 1.0);
      final modifier = defaultTargetPlatform == TargetPlatform.macOS
          ? LogicalKeyboardKey.metaLeft
          : LogicalKeyboardKey.controlLeft;
      await tester.sendKeyDownEvent(modifier, platform: 'macos');
      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.equal,
        platform: 'macos',
      );
      await tester.sendKeyRepeatEvent(
        LogicalKeyboardKey.equal,
        platform: 'macos',
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.equal, platform: 'macos');
      await tester.sendKeyUpEvent(modifier, platform: 'macos');
      await tester.pumpAndSettle();
      expect(controller.value, 1.2);
      expect(AppSettings.interfaceScale.value, 1.2);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    }),
  );

  testWidgets(
    'mobile does not intercept desktop zoom shortcuts',
    (tester) async {
      final controller = await _mountApp(
        tester,
        const Scaffold(body: TextField(autofocus: true)),
      );
      await _sendZoomKey(tester, LogicalKeyboardKey.equal);
      expect(controller.value, 1.0);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets(
    'zoom preserves navigation, dialogs and editor selection',
    (tester) async {
      final text = TextEditingController(text: 'A draft')
        ..selection = const TextSelection.collapsed(offset: 3);
      addTearDown(text.dispose);
      const marker = ValueKey('dialog-content');
      final controller = await _mountApp(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                TextField(controller: text),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => Scaffold(
                        appBar: AppBar(title: const Text('Second page')),
                        body: Center(
                          child: TextButton(
                            onPressed: () => showDialog<void>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Scale dialog'),
                                content: const SizedBox(
                                  key: marker,
                                  width: 200,
                                  height: 80,
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(),
                                    child: const Text('Close'),
                                  ),
                                ],
                              ),
                            ),
                            child: const Text('Dialog'),
                          ),
                        ),
                      ),
                    ),
                  ),
                  child: const Text('Next'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dialog'));
      await tester.pumpAndSettle();
      final originalSize =
          tester.getBottomRight(find.byKey(marker)) -
          tester.getTopLeft(find.byKey(marker));
      await _sendZoomKey(tester, LogicalKeyboardKey.equal);
      expect(controller.value, 1.1);
      await controller.setScale(1.5);
      await tester.pumpAndSettle();
      final scaledSize =
          tester.getBottomRight(find.byKey(marker)) -
          tester.getTopLeft(find.byKey(marker));
      expect(scaledSize.dx, closeTo(originalSize.dx * 1.5, 0.01));
      expect(scaledSize.dy, closeTo(originalSize.dy * 1.5, 0.01));
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Second page'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(text.text, 'A draft');
      expect(text.selection.baseOffset, 3);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    }),
  );

  testWidgets('scrolling and clicking stay aligned after zoom changes', (
    tester,
  ) async {
    await AppSettings.interfaceScale.setItem(1.5);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    int? selected;
    final controller = await _mountApp(
      tester,
      Scaffold(
        body: ListView.builder(
          controller: scroll,
          itemExtent: 40,
          itemCount: 100,
          itemBuilder: (context, index) => ListTile(
            title: Text('Row $index'),
            onTap: () => selected = index,
          ),
        ),
      ),
    );
    await tester.drag(find.byType(ListView), const Offset(0, -180));
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(0));
    final offset = scroll.offset;
    await controller.reset();
    await tester.pumpAndSettle();
    expect(scroll.offset, closeTo(offset, 0.01));
    await tester.tap(find.text('Row 8'));
    expect(selected, 8);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the global zoom handler is removed on disposal', (tester) async {
    final controller = await _mountApp(
      tester,
      const Scaffold(body: TextField(autofocus: true)),
    );
    await controller.setScale(1.25);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await _sendZoomKey(tester, LogicalKeyboardKey.equal);
    expect(AppSettings.interfaceScale.value, 1.25);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
