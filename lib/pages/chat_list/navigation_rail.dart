// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:hermes/config/app_config.dart';
import 'package:hermes/config/themes.dart';
import 'package:hermes/l10n/l10n.dart';
import 'package:hermes/pages/chat_list/chat_filter_toggle.dart';
import 'package:hermes/pages/chat_list/navi_rail_item.dart';
import 'package:hermes/pages/chat_list/start_chat_fab.dart';
import 'package:hermes/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:hermes/utils/stream_extension.dart';
import 'package:hermes/utils/well_formed_text.dart';
import 'package:hermes/widgets/avatar.dart';
import 'package:hermes/widgets/matrix.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class SpacesNavigationRail extends StatefulWidget {
  final String? activeSpaceId;
  final bool unreadSelected;
  final void Function() onGoToChats;
  final void Function() onGoToUnread;
  final void Function(String) onGoToSpaceId;

  const SpacesNavigationRail({
    required this.activeSpaceId,
    required this.unreadSelected,
    required this.onGoToChats,
    required this.onGoToUnread,
    required this.onGoToSpaceId,
    super.key,
  });

  @override
  State<SpacesNavigationRail> createState() => _SpacesNavigationRailState();
}

class _SpacesNavigationRailState extends State<SpacesNavigationRail> {
  final ScrollController _scrollController = ScrollController();
  String? _spaceOrderKey;
  List<String> _spaceOrder = [];

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeSpaceId = widget.activeSpaceId;
    final unreadSelected = widget.unreadSelected;
    final onGoToChats = widget.onGoToChats;
    final onGoToUnread = widget.onGoToUnread;
    final onGoToSpaceId = widget.onGoToSpaceId;
    final matrix = Matrix.of(context);
    final client = matrix.client;
    final spaceOrderKey = 'chat.pantheon.space_order.${client.clientName}';
    if (_spaceOrderKey != spaceOrderKey) {
      _spaceOrderKey = spaceOrderKey;
      _spaceOrder = matrix.store.getStringList(spaceOrderKey) ?? [];
    }
    final isSettings = GoRouter.of(
      context,
    ).routeInformationProvider.value.uri.path.startsWith('/rooms/settings');
    final coloredMode = !PantheonThemes.isColumnMode(context);
    final theme = Theme.of(context);
    final useLongPressDrag =
        theme.platform == TargetPlatform.android ||
        theme.platform == TargetPlatform.iOS;
    return Material(
      color: coloredMode ? theme.colorScheme.surfaceContainer : null,
      child: SafeArea(
        child: StreamBuilder(
          key: ValueKey(client.userID.toString()),
          stream: client.onSync.stream
              .where((s) => s.hasRoomUpdate)
              .rateLimit(const Duration(seconds: 1)),
          builder: (context, _) {
            final allSpaces = client.rooms
                .where(
                  (room) => room.isSpace && room.membership == Membership.join,
                )
                .toList();
            final rootSpaces = allSpaces
                .where(
                  (space) => !allSpaces.any(
                    (parentSpace) => parentSpace.spaceChildren.any(
                      (child) => child.roomId == space.id,
                    ),
                  ),
                )
                .toList();
            final savedPositions = {
              for (var i = 0; i < _spaceOrder.length; i++) _spaceOrder[i]: i,
            };
            final originalPositions = {
              for (var i = 0; i < rootSpaces.length; i++) rootSpaces[i].id: i,
            };
            rootSpaces.sort(
              (a, b) =>
                  (savedPositions[a.id] ??
                          _spaceOrder.length + originalPositions[a.id]!)
                      .compareTo(
                        savedPositions[b.id] ??
                            _spaceOrder.length + originalPositions[b.id]!,
                      ),
            );
            final hasUnreadChats = client.rooms.any(
              (room) => !room.isSpace && room.isUnreadOrInvited,
            );
            final activeSpaceIndex = rootSpaces.indexWhere(
              (space) => space.id == activeSpaceId,
            );

            return SizedBox(
              width: PantheonThemes.isColumnMode(context)
                  ? PantheonThemes.navRailWidth
                  : PantheonThemes.navRailWidth - 8,
              child: Column(
                children: [
                  Expanded(
                    child: AnimatedBuilder(
                      animation: _scrollController,
                      builder: (context, child) => Stack(
                        children: [
                          child!,
                          _SlidingSpaceIndicator(
                            selectedTop: activeSpaceIndex >= 0 && !isSettings
                                ? 4 +
                                      (hasUnreadChats ? 120 : 68) +
                                      activeSpaceIndex * 60 +
                                      8
                                : null,
                            scrollOffset: _scrollController.hasClients
                                ? _scrollController.offset
                                : 0,
                            width: 4,
                            color: theme.colorScheme.primary,
                          ),
                        ],
                      ),
                      child: ReorderableListView.builder(
                        scrollController: _scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        scrollDirection: Axis.vertical,
                        buildDefaultDragHandles: false,
                        itemCount: rootSpaces.length,
                        onReorderItem: (oldIndex, newIndex) {
                          if (oldIndex == newIndex) return;
                          setState(() {
                            final moved = rootSpaces.removeAt(oldIndex);
                            rootSpaces.insert(newIndex, moved);
                            _spaceOrder = rootSpaces
                                .map((space) => space.id)
                                .toList();
                          });
                          unawaited(
                            matrix.store.setStringList(
                              spaceOrderKey,
                              _spaceOrder,
                            ),
                          );
                        },
                        header: ChatFilterToggle(
                          hasUnreadChats: hasUnreadChats,
                          selection: isSettings || activeSpaceId != null
                              ? ChatFilterSelection.none
                              : unreadSelected && hasUnreadChats
                              ? ChatFilterSelection.unread
                              : ChatFilterSelection.all,
                          onAllTap: onGoToChats,
                          onUnreadTap: onGoToUnread,
                        ),
                        footer: NaviRailItem(
                          isSelected: false,
                          onTap: () => context.go('/rooms/newspace'),
                          icon: const Padding(
                            padding: EdgeInsets.all(12.0),
                            child: Icon(Icons.add),
                          ),
                          toolTip: L10n.of(context).createNewSpace,
                        ),
                        itemBuilder: (context, i) {
                          final space = rootSpaces[i];
                          final displayname = wellFormedText(
                            space.getLocalizedDisplayname(
                              MatrixLocals(L10n.of(context)),
                            ),
                          );
                          final spaceChildrenIds = space.spaceChildren
                              .map((c) => c.roomId)
                              .toSet();
                          final item = NaviRailItem(
                            toolTip: displayname,
                            tooltipTriggerMode: useLongPressDrag
                                ? TooltipTriggerMode.manual
                                : null,
                            isSelected:
                                activeSpaceId == space.id && !isSettings,
                            showSelectionIndicator: false,
                            onTap: () => onGoToSpaceId(space.id),
                            unreadBadgeFilter: (room) =>
                                spaceChildrenIds.contains(room.id),
                            icon: Avatar(
                              mxContent: space.avatar,
                              name: displayname,
                              //size: 36,
                              shapeBorder: RoundedSuperellipseBorder(
                                side: BorderSide(
                                  width: 1,
                                  color: Theme.of(context).dividerColor,
                                ),
                                borderRadius: BorderRadius.circular(
                                  AppConfig.spaceBorderRadius,
                                ),
                              ),
                              borderRadius: BorderRadius.circular(
                                AppConfig.spaceBorderRadius,
                              ),
                            ),
                          );
                          return useLongPressDrag
                              ? ReorderableDelayedDragStartListener(
                                  key: ValueKey(space.id),
                                  index: i,
                                  child: item,
                                )
                              : ReorderableDragStartListener(
                                  key: ValueKey(space.id),
                                  index: i,
                                  child: item,
                                );
                        },
                      ),
                    ),
                  ),
                  if (PantheonThemes.isColumnMode(context))
                    Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: StartChatFab(),
                    ),
                  NaviRailItem(
                    isSelected: isSettings,
                    onTap: () => context.go('/rooms/settings'),
                    icon: const Padding(
                      padding: EdgeInsets.all(12.0),
                      child: Icon(Icons.settings_outlined),
                    ),
                    selectedIcon: const Padding(
                      padding: EdgeInsets.all(12.0),
                      child: Icon(Icons.settings),
                    ),
                    toolTip: L10n.of(context).settings,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SlidingSpaceIndicator extends StatefulWidget {
  final double? selectedTop;
  final double scrollOffset;
  final double width;
  final Color color;

  const _SlidingSpaceIndicator({
    required this.selectedTop,
    required this.scrollOffset,
    required this.width,
    required this.color,
  });

  @override
  State<_SlidingSpaceIndicator> createState() => _SlidingSpaceIndicatorState();
}

class _SlidingSpaceIndicatorState extends State<_SlidingSpaceIndicator>
    with TickerProviderStateMixin {
  late final AnimationController _travel;
  late final AnimationController _visibility;
  late final Listenable _animations;
  late double _from;
  late double _to;

  double get _position =>
      _from + (_to - _from) * Curves.easeInOutCubic.transform(_travel.value);

  @override
  void initState() {
    super.initState();
    _from = _to = widget.selectedTop ?? 0;
    _travel = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      value: 1,
    );
    _visibility = AnimationController(
      vsync: this,
      duration: PantheonThemes.animationDuration,
      value: widget.selectedTop == null ? 0 : 1,
    );
    _animations = Listenable.merge([_travel, _visibility]);
  }

  @override
  void didUpdateWidget(covariant _SlidingSpaceIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    final target = widget.selectedTop;
    if (target == null) {
      if (oldWidget.selectedTop != null) {
        _from = _to = _position;
        _travel.stop();
        _travel.value = 1;
        _visibility.animateTo(0, curve: Curves.easeInOutCubic);
      }
    } else {
      if (oldWidget.selectedTop == null && _visibility.value == 0) {
        _from = _to = target;
        _travel.stop();
        _travel.value = 1;
      } else if (target != _to) {
        _from = _position;
        _to = target;
        _travel.forward(from: 0);
      }
      if (oldWidget.selectedTop == null) {
        _visibility.animateTo(1, curve: Curves.easeInOutCubic);
      }
    }
  }

  @override
  void dispose() {
    _travel.dispose();
    _visibility.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _animations,
    builder: (context, _) {
      final stretch = _travel.isAnimating
          ? math.sin(math.pi * _travel.value) *
                ((_to - _from).abs() / 60).clamp(0.0, 1.0)
          : 0.0;
      return Positioned(
        top: _position - widget.scrollOffset,
        left: 0,
        child: IgnorePointer(
          child: Opacity(
            key: const Key('space_selection_opacity'),
            opacity: _visibility.value,
            child: Transform.scale(
              key: const Key('space_selection_scale'),
              scaleY: 1 + 0.16 * stretch,
              child: Container(
                key: const Key('space_selection_indicator'),
                width: widget.width,
                height: 44,
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(90),
                    bottomRight: Radius.circular(90),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
