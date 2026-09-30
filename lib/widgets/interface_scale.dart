// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ui' show DisplayFeature;

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
  void dispose() {
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
