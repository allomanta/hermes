// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart' as flutter_material;
import 'package:material_ui/material_ui.dart';

class EmojiSearchView extends StatelessWidget {
  final Config config;
  final EmojiViewState state;
  final VoidCallback showEmojiView;

  const EmojiSearchView(
    this.config,
    this.state,
    this.showEmojiView, {
    super.key,
  });

  @override
  Widget build(BuildContext context) =>
      // The picker uses Flutter Material widgets, including its TextField.
      // ignore: deprecated_member_use
      MaterialUiCompatibilityBridge(
        child: flutter_material.Material(
          type: flutter_material.MaterialType.transparency,
          child: DefaultSearchView(config, state, showEmojiView),
        ),
      );
}
