// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Lets focused controls handle Escape before falling back to navigation.
class EscapeBackHandler extends StatelessWidget {
  final VoidCallback onBack;
  final Widget child;

  const EscapeBackHandler({
    required this.onBack,
    required this.child,
    super.key,
  });

  @override
  Widget build(BuildContext context) => Focus(
    skipTraversal: true,
    onKeyEvent: (_, event) {
      if (event.logicalKey != LogicalKeyboardKey.escape) {
        return KeyEventResult.ignored;
      }
      if (event is KeyDownEvent) onBack();
      return KeyEventResult.handled;
    },
    child: child,
  );
}
