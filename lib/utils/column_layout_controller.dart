// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/widgets.dart';

enum CollapsedPane { main, side }

class ColumnLayoutScope extends InheritedNotifier<ColumnLayoutController> {
  const ColumnLayoutScope({
    required ColumnLayoutController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static ColumnLayoutController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ColumnLayoutScope>()?.notifier;
}

class ColumnLayoutController extends ValueNotifier<CollapsedPane?> {
  double columnWidth;
  final Listenable? navigation;

  ColumnLayoutController({required this.columnWidth, this.navigation})
    : super(null) {
    navigation?.addListener(_onNavigation);
  }

  void _onNavigation() {
    // Opening a chat from the expanded list must reveal the routed page,
    // including when the user selects the chat that was already open.
    if (value == CollapsedPane.side) value = CollapsedPane.main;
  }

  @override
  void dispose() {
    navigation?.removeListener(_onNavigation);
    super.dispose();
  }
}
