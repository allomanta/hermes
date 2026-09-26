// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;

import 'package:badges/badges.dart';
import 'package:hermes/config/themes.dart';
import 'package:hermes/l10n/l10n.dart';
import 'package:hermes/widgets/unread_rooms_badge.dart';
import 'package:material_ui/material_ui.dart';

enum ChatFilterSelection { all, unread, none }

class ChatFilterToggle extends StatefulWidget {
  final bool hasUnreadChats;
  final ChatFilterSelection selection;
  final VoidCallback onAllTap;
  final VoidCallback onUnreadTap;

  const ChatFilterToggle({
    required this.hasUnreadChats,
    required this.selection,
    required this.onAllTap,
    required this.onUnreadTap,
    super.key,
  });

  @override
  State<ChatFilterToggle> createState() => _ChatFilterToggleState();
}

class _ChatFilterToggleState extends State<ChatFilterToggle>
    with TickerProviderStateMixin {
  static const double _rowHeight = 52;
  static const double _diameter = 48;
  static const double _topInset = (_rowHeight - _diameter) / 2;

  late final AnimationController _travel;
  late final AnimationController _unreadVisibility;
  late final AnimationController _selectionVisibility;
  late final Listenable _animations;
  late double _from;
  late double _to;
  bool _hoveredAll = false;
  bool _hoveredUnread = false;

  ChatFilterSelection get _effectiveSelection =>
      widget.selection == ChatFilterSelection.unread && !widget.hasUnreadChats
      ? ChatFilterSelection.all
      : widget.selection;

  double get _targetPosition =>
      _effectiveSelection == ChatFilterSelection.unread ? 1 : 0;

  double get _position =>
      _from + (_to - _from) * Curves.easeInOutCubic.transform(_travel.value);

  @override
  void initState() {
    super.initState();
    _from = _to = _targetPosition;
    _travel = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      value: 1,
    );
    _unreadVisibility = AnimationController(
      vsync: this,
      duration: PantheonThemes.animationDuration,
      value: widget.hasUnreadChats ? 1 : 0,
    );
    _selectionVisibility = AnimationController(
      vsync: this,
      duration: PantheonThemes.animationDuration,
      value: _effectiveSelection == ChatFilterSelection.none ? 0 : 1,
    );
    _animations = Listenable.merge([
      _travel,
      _unreadVisibility,
      _selectionVisibility,
    ]);
  }

  @override
  void didUpdateWidget(covariant ChatFilterToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hasUnreadChats != widget.hasUnreadChats) {
      _unreadVisibility.animateTo(
        widget.hasUnreadChats ? 1 : 0,
        curve: Curves.easeInOutCubic,
      );
      if (!widget.hasUnreadChats) _hoveredUnread = false;
    }
    if (_effectiveSelection == ChatFilterSelection.none) {
      if (oldWidget.selection != ChatFilterSelection.none) {
        _from = _to = _position;
        _travel.stop();
        _travel.value = 1;
      }
    } else if (_targetPosition != _to) {
      _from = _position;
      _to = _targetPosition;
      _travel.forward(from: 0);
    }
    if ((oldWidget.selection == ChatFilterSelection.none) !=
        (_effectiveSelection == ChatFilterSelection.none)) {
      _selectionVisibility.animateTo(
        _effectiveSelection == ChatFilterSelection.none ? 0 : 1,
        curve: Curves.easeInOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _travel.dispose();
    _unreadVisibility.dispose();
    _selectionVisibility.dispose();
    super.dispose();
  }

  Widget _button(bool unread, double position) {
    final selected =
        _effectiveSelection ==
        (unread ? ChatFilterSelection.unread : ChatFilterSelection.all);
    final hovered = unread ? _hoveredUnread : _hoveredAll;
    final theme = Theme.of(context);
    final selectionColorAmount = _effectiveSelection == ChatFilterSelection.none
        ? 0.0
        : (1 - (position - (unread ? 1 : 0)).abs()).clamp(0.0, 1.0);
    final baseColor = Color.lerp(
      theme.colorScheme.onSurface,
      theme.colorScheme.onPrimaryContainer,
      selectionColorAmount,
    )!;
    final icon = TweenAnimationBuilder<double>(
      tween: Tween(end: hovered ? 1 : 0),
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      builder: (context, hover, _) => Transform.scale(
        key: Key(
          unread
              ? 'chat_filter_unread_icon_scale'
              : 'chat_filter_all_icon_scale',
        ),
        scale: 1 + 0.1 * hover,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 140),
          child: Icon(
            unread
                ? selected
                      ? Icons.mark_chat_unread
                      : Icons.mark_chat_unread_outlined
                : selected
                ? Icons.forum
                : Icons.forum_outlined,
            key: ValueKey(selected),
            size: 24,
            color: Color.lerp(baseColor, Colors.white, 0.22 * hover),
          ),
        ),
      ),
    );
    return SizedBox(
      height: _rowHeight,
      width: PantheonThemes.navRailWidth,
      child: Center(
        child: Tooltip(
          message: unread ? L10n.of(context).unread : L10n.of(context).chats,
          child: MouseRegion(
            onEnter: (_) => setState(() {
              if (unread) {
                _hoveredUnread = true;
              } else {
                _hoveredAll = true;
              }
            }),
            onExit: (_) => setState(() {
              if (unread) {
                _hoveredUnread = false;
              } else {
                _hoveredAll = false;
              }
            }),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                key: Key(unread ? 'chat_filter_unread' : 'chat_filter_all'),
                customBorder: const CircleBorder(),
                overlayColor: const WidgetStatePropertyAll(Colors.transparent),
                splashFactory: NoSplash.splashFactory,
                onTap: unread ? widget.onUnreadTap : widget.onAllTap,
                child: SizedBox(
                  height: _diameter,
                  width: _diameter,
                  child: unread
                      ? UnreadRoomsBadge(
                          filter: (room) => !room.isSpace,
                          badgePosition: BadgePosition.topEnd(top: -4, end: -6),
                          child: Center(child: icon),
                        )
                      : Center(child: icon),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 8),
    child: AnimatedBuilder(
      animation: _animations,
      builder: (context, _) {
        final visibility = _unreadVisibility.value;
        final position = _position;
        // Stretch the thumb along its travel without changing the track color.
        final stretch = _travel.isAnimating
            ? math.sin(math.pi * _travel.value) *
                  (_to - _from).abs().clamp(0.0, 1.0)
            : 0.0;
        return ClipRect(
          child: Stack(
            children: [
              Positioned(
                top: _topInset,
                left: 0,
                right: 0,
                child: Center(
                  child: SizedBox(
                    key: const Key('chat_filters_capsule'),
                    width: _diameter,
                    height: _diameter + _rowHeight * visibility,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(_diameter / 2),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: _topInset + _rowHeight * position,
                left: 0,
                right: 0,
                child: Center(
                  child: Opacity(
                    key: const Key('chat_filters_selection_opacity'),
                    opacity: _selectionVisibility.value,
                    child: Transform.scale(
                      key: const Key('chat_filters_thumb_transform'),
                      scaleX: 1 - 0.1 * stretch,
                      scaleY: 1 + 0.28 * stretch,
                      child: SizedBox(
                        key: const Key('chat_filters_selection'),
                        width: _diameter,
                        height: _diameter,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(_diameter / 2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Column(
                children: [
                  _button(false, position),
                  ClipRect(
                    key: const Key('unread_rail_destination'),
                    child: Align(
                      alignment: Alignment.topCenter,
                      heightFactor: visibility,
                      child: Transform.translate(
                        offset: Offset(0, (visibility - 1) * _rowHeight),
                        child: IgnorePointer(
                          ignoring: !widget.hasUnreadChats,
                          child: ExcludeSemantics(
                            excluding: !widget.hasUnreadChats,
                            child: _button(true, position),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ),
  );
}
