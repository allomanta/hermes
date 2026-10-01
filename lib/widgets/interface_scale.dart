// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:ui' show DisplayFeature;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:hermes/config/setting_keys.dart';
import 'package:provider/provider.dart';

class InterfaceScaleController extends ValueNotifier<double> {
  static const minScale = 0.75;
  static const maxScale = 1.5;

  InterfaceScaleController() : super(1.0) {
    final savedScale = AppSettings.interfaceScale.value;
    value = savedScale.isFinite ? savedScale.clamp(minScale, maxScale) : 1.0;
  }

  static InterfaceScaleController of(BuildContext context) =>
      Provider.of<InterfaceScaleController>(context);

  Future<void> setScale(double scale) async {
    final boundedScale = scale.isFinite ? scale.clamp(minScale, maxScale) : 1.0;
    final newScale = (boundedScale * 100).round() / 100;
    if (value == newScale) return;
    value = newScale;
    await AppSettings.interfaceScale.setItem(newScale);
  }

  Future<void> zoomIn() => setScale(value + 0.1);

  Future<void> zoomOut() => setScale(value - 0.1);

  Future<void> reset() => setScale(1.0);
}

class InterfaceScale extends StatefulWidget {
  final Widget child;

  const InterfaceScale({required this.child, super.key});

  @override
  State<InterfaceScale> createState() => _InterfaceScaleState();
}

class _InterfaceScaleState extends State<InterfaceScale> {
  final controller = InterfaceScaleController();

  @override
  void initState() {
    super.initState();
    // Modal routes can stop normal focus bubbling, so zoom is handled first.
    FocusManager.instance.addEarlyKeyEventHandler(_onZoomKey);
  }

  KeyEventResult _onZoomKey(KeyEvent event) {
    if (kIsWeb ||
        !{
          TargetPlatform.macOS,
          TargetPlatform.windows,
          TargetPlatform.linux,
        }.contains(defaultTargetPlatform) ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    final isMacOS = defaultTargetPlatform == TargetPlatform.macOS;
    final modifier = isMacOS
        ? keyboard.isMetaPressed
        : keyboard.isControlPressed;
    final otherModifier = isMacOS
        ? keyboard.isControlPressed
        : keyboard.isMetaPressed;
    if (!modifier || otherModifier || keyboard.isAltPressed) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if ({
      LogicalKeyboardKey.equal,
      LogicalKeyboardKey.add,
      LogicalKeyboardKey.numpadAdd,
    }.contains(key)) {
      unawaited(controller.zoomIn());
    } else if (!keyboard.isShiftPressed &&
        {
          LogicalKeyboardKey.minus,
          LogicalKeyboardKey.numpadSubtract,
        }.contains(key)) {
      unawaited(controller.zoomOut());
    } else if (!keyboard.isShiftPressed &&
        {LogicalKeyboardKey.digit0, LogicalKeyboardKey.numpad0}.contains(key)) {
      unawaited(controller.reset());
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_onZoomKey);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider.value(
    value: controller,
    child: ValueListenableBuilder<double>(
      valueListenable: controller,
      child: widget.child,
      builder: (context, scale, child) => LayoutBuilder(
        builder: (context, constraints) {
          final data = MediaQuery.of(context);
          final size = constraints.biggest / scale;
          return FittedBox(
            fit: BoxFit.fill,
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: MediaQuery(
                data: data.copyWith(
                  size: size,
                  devicePixelRatio: data.devicePixelRatio * scale,
                  padding: data.padding / scale,
                  viewPadding: data.viewPadding / scale,
                  viewInsets: data.viewInsets / scale,
                  systemGestureInsets: data.systemGestureInsets / scale,
                  displayFeatures: [
                    for (final feature in data.displayFeatures)
                      DisplayFeature(
                        bounds: Rect.fromLTWH(
                          feature.bounds.left / scale,
                          feature.bounds.top / scale,
                          feature.bounds.width / scale,
                          feature.bounds.height / scale,
                        ),
                        type: feature.type,
                        state: feature.state,
                      ),
                  ],
                ),
                child: child!,
              ),
            ),
          );
        },
      ),
    ),
  );
}
