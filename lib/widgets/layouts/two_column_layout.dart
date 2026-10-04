// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/gestures.dart';
import 'package:hermes/config/themes.dart';
import 'package:hermes/l10n/l10n.dart';
import 'package:hermes/utils/column_layout_controller.dart';
import 'package:material_ui/material_ui.dart';

class TwoColumnLayout extends StatefulWidget {
  final Widget mainView;
  final Widget sideView;
  final bool hasNavigationRail;

  const TwoColumnLayout({
    super.key,
    required this.mainView,
    required this.sideView,
    this.hasNavigationRail = true,
  });

  // Three standard icon-button widths, excluding the navigation rail.
  static const minimumPaneWidth = 144.0;
  // Chat toolbars and the composer need the existing column's usable width.
  static const minimumChatWidth = PantheonThemes.columnWidth;

  @override
  State<TwoColumnLayout> createState() => _TwoColumnLayoutState();
}

class _TwoColumnLayoutState extends State<TwoColumnLayout> {
  static const _handleWidth = 12.0;
  double? _dragPosition;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = ColumnLayoutScope.maybeOf(context)!;
    final railWidth = widget.hasNavigationRail
        ? PantheonThemes.navRailWidth
        : 0.0;

    return ScaffoldMessenger(
      child: Scaffold(
        body: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final mainWidth = (controller.columnWidth + railWidth).clamp(
              TwoColumnLayout.minimumPaneWidth + railWidth,
              width - TwoColumnLayout.minimumChatWidth - 1,
            );
            final collapsed = controller.value;
            final dividerPosition = switch (collapsed) {
              CollapsedPane.main => 0.0,
              CollapsedPane.side => width,
              null => mainWidth + 0.5,
            };
            final direction = Directionality.of(context) == TextDirection.rtl
                ? -1.0
                : 1.0;
            return Stack(
              children: [
                PositionedDirectional(
                  top: 0,
                  bottom: 0,
                  start: collapsed == null ? mainWidth + 1 : 0,
                  end: 0,
                  // Keep the routed navigator (and drafts/scroll positions)
                  // alive when the chat pane is collapsed.
                  child: Offstage(
                    offstage: collapsed == CollapsedPane.side,
                    child: ExcludeFocus(
                      excluding: collapsed == CollapsedPane.side,
                      child: TickerMode(
                        enabled: collapsed != CollapsedPane.side,
                        child: ClipRRect(child: widget.sideView),
                      ),
                    ),
                  ),
                ),
                if (collapsed != CollapsedPane.main)
                  PositionedDirectional(
                    top: 0,
                    bottom: 0,
                    start: 0,
                    width: collapsed == null ? mainWidth : width,
                    child: Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: const BoxDecoration(),
                      child: widget.mainView,
                    ),
                  ),
                PositionedDirectional(
                  key: const ValueKey('column-divider'),
                  top: 0,
                  bottom: 0,
                  start: (dividerPosition - _handleWidth / 2).clamp(
                    0,
                    width - _handleWidth,
                  ),
                  width: _handleWidth,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeColumn,
                    onEnter: (_) => setState(() => _hovered = true),
                    onExit: (_) => setState(() => _hovered = false),
                    child: Tooltip(
                      message: L10n.of(context).resizeChatColumns,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        dragStartBehavior: DragStartBehavior.down,
                        onTap: collapsed == null
                            ? null
                            : () => controller.value = null,
                        onDoubleTap: () => setState(() {
                          controller.columnWidth = PantheonThemes.columnWidth;
                          controller.value = null;
                        }),
                        onHorizontalDragStart: (_) => _dragPosition =
                            collapsed == null ? mainWidth : dividerPosition,
                        onHorizontalDragUpdate: (details) {
                          final position = _dragPosition =
                              (_dragPosition! + details.delta.dx * direction)
                                  .clamp(0, width);
                          setState(() {
                            if (position <
                                TwoColumnLayout.minimumPaneWidth + railWidth) {
                              controller.value = CollapsedPane.main;
                            } else if (width - position - 1 <
                                TwoColumnLayout.minimumChatWidth) {
                              controller.value = CollapsedPane.side;
                            } else {
                              controller.columnWidth = position - railWidth;
                              controller.value = null;
                            }
                          });
                        },
                        onHorizontalDragEnd: (_) => _dragPosition = null,
                        onHorizontalDragCancel: () => _dragPosition = null,
                        child: Center(
                          child: Container(
                            width: _hovered || collapsed != null ? 3 : 1,
                            color: _hovered || collapsed != null
                                ? theme.colorScheme.primary
                                : theme.dividerColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
