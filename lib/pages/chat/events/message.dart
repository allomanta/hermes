import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:matrix/matrix.dart';

import 'package:hermes/config/setting_keys.dart';
import 'package:hermes/l10n/l10n.dart';
import 'package:hermes/utils/adaptive_bottom_sheet.dart';
import 'package:hermes/config/themes.dart';
import 'package:hermes/pages/chat/events/room_creation_state_event.dart';
import 'package:hermes/utils/date_time_extension.dart';
import 'package:hermes/utils/file_description.dart';
import 'package:hermes/utils/string_color.dart';
import 'package:hermes/widgets/avatar.dart';
import 'package:hermes/widgets/matrix.dart';
import 'package:hermes/widgets/member_actions_popup_menu_button.dart';
import 'package:hermes/utils/platform_infos.dart';
import 'package:hermes/utils/reply_swipe.dart';
import 'package:hermes/utils/matrix_sdk_extensions/matrix_locals.dart';
import '../../../config/app_config.dart';
import 'message_content.dart';
import 'message_reactions.dart';
import 'reply_content.dart';
import 'state_message.dart';

enum _MessageAction {
  reply,
  copy,
  forward,
  pin,
  edit,
  redact,
}

class Message extends StatelessWidget {
  final Event event;
  final Event? nextEvent;
  final Event? previousEvent;
  final bool displayReadMarker;
  final void Function(Event) onSelect;
  final void Function(Event) onInfoTab;
  final void Function(String) scrollToEventId;
  final void Function() onReply;
  final void Function() onForward;
  final void Function() onCopy;
  final void Function() onPin;
  final void Function() onRedact;
  final void Function() onMention;
  final void Function() onEdit;
  final void Function(String eventId)? enterThread;
  final bool longPressSelect;
  final bool selected;
  final bool singleSelected;
  final Timeline timeline;
  final bool highlightMarker;
  final bool animateIn;
  final void Function()? resetAnimateIn;
  final bool wallpaperMode;
  final ScrollController scrollController;
  final List<Color> colors;
  final void Function()? onExpand;
  final bool isCollapsed;

  const Message(
    this.event, {
    this.nextEvent,
    this.previousEvent,
    this.displayReadMarker = false,
    this.longPressSelect = false,
    required this.onSelect,
    required this.onInfoTab,
    required this.scrollToEventId,
    required this.onReply,
    required this.onForward,
    required this.onCopy,
    required this.onPin,
    required this.onRedact,
    this.selected = false,
    required this.onEdit,
    required this.singleSelected,
    required this.timeline,
    this.highlightMarker = false,
    this.animateIn = false,
    this.resetAnimateIn,
    this.wallpaperMode = false,
    required this.onMention,
    required this.scrollController,
    required this.colors,
    this.onExpand,
    required this.enterThread,
    this.isCollapsed = false,
    super.key,
  });

  Future<void> _showContextMenu(
    BuildContext context,
    Offset globalPosition,
  ) async {
    final overlay = Overlay.of(context, rootOverlay: true)
        .context
        .findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final local = overlay.globalToLocal(globalPosition);
    final size = overlay.size;
    final client = Matrix.of(context).client;
    final ownMessage = client.userID == event.senderId;
    final l10n = L10n.of(context);
    final theme = Theme.of(context);

    final menuActions = <_ContextMenuAction>[
      _ContextMenuAction(
        action: _MessageAction.reply,
        icon: Icons.reply_outlined,
        label: l10n.reply,
      ),
      _ContextMenuAction(
        action: _MessageAction.copy,
        icon: Icons.copy_outlined,
        label: l10n.copy,
      ),
      _ContextMenuAction(
        action: _MessageAction.forward,
        icon: Icons.forward,
        label: l10n.forward,
      ),
      _ContextMenuAction(
        action: _MessageAction.pin,
        icon: Icons.push_pin_outlined,
        label: l10n.pin,
      ),
      if (ownMessage)
        _ContextMenuAction(
          action: _MessageAction.edit,
          icon: Icons.edit_outlined,
          label: l10n.edit,
        ),
      if (ownMessage)
        _ContextMenuAction(
          action: _MessageAction.redact,
          icon: Icons.delete_outlined,
          label: l10n.delete,
          isDestructive: true,
        ),
    ];

    final view = View.of(context);
    final keyboardHeight = view.viewInsets.bottom / view.devicePixelRatio;

    _MessageAction? result;
    if (PlatformInfos.isAndroid && keyboardHeight > 0) {
      result = await _showContextMenuOverlay(
        context: context,
        overlay: overlay,
        localPosition: local,
        keyboardHeight: keyboardHeight,
        actions: menuActions,
      );
    } else {
      final menuItems = menuActions
          .map(
            (action) => PopupMenuItem<_MessageAction>(
              value: action.action,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    action.icon,
                    size: 18,
                    color: action.isDestructive
                        ? theme.colorScheme.error
                        : theme.iconTheme.color,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    action.label,
                    style: action.isDestructive
                        ? TextStyle(color: theme.colorScheme.error)
                        : null,
                  ),
                ],
              ),
            ),
          )
          .toList();

      const menuScreenPadding = 8.0; // Matches Flutter's internal padding.
      final menuHeight = menuItems.fold<double>(
        menuScreenPadding * 2,
        (prev, entry) => prev + entry.height,
      );
      final keyboardTop = size.height - keyboardHeight - menuScreenPadding;
      var menuTop = local.dy;

      if (keyboardHeight > 0 &&
          (menuTop + menuHeight) >
              math.max(menuScreenPadding, keyboardTop)) {
        menuTop = math.max(
          menuScreenPadding,
          keyboardTop - menuHeight,
        );
      }

      result = await showMenu<_MessageAction>(
        context: context,
        useRootNavigator: true,
        position: RelativeRect.fromLTRB(
          local.dx,
          menuTop,
          size.width - local.dx,
          size.height - menuTop,
        ),
        requestFocus: false,
        items: menuItems,
      );
    }
    switch (result) {
      case _MessageAction.reply:
        onReply();
        break;
      case _MessageAction.copy:
        onCopy();
        break;
      case _MessageAction.forward:
        onForward();
        break;
      case _MessageAction.pin:
        onPin();
        break;
      case _MessageAction.edit:
        onEdit();
        break;
      case _MessageAction.redact:
        onRedact();
        break;
      case null:
        break;
      // handle others
    }
  }

  Future<_MessageAction?> _showContextMenuOverlay({
    required BuildContext context,
    required RenderBox overlay,
    required Offset localPosition,
    required double keyboardHeight,
    required List<_ContextMenuAction> actions,
  }) {
    final completer = Completer<_MessageAction?>();
    late final OverlayEntry entry;

    void dismiss([_MessageAction? action]) {
      if (completer.isCompleted) return;
      completer.complete(action);
      entry.remove();
    }

    entry = OverlayEntry(
      builder: (context) => _ContextMenuOverlay(
        position: localPosition,
        overlaySize: overlay.size,
        keyboardHeight: keyboardHeight,
        actions: actions,
        onSelected: dismiss,
        onDismiss: () => dismiss(null),
      ),
    );

    Overlay.of(context, rootOverlay: true).insert(entry);
    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!{
      EventTypes.Message,
      EventTypes.Sticker,
      EventTypes.Encrypted,
      EventTypes.CallInvite,
      PollEventContent.startType,
    }.contains(event.type)) {
      if (event.type.startsWith('m.call.')) {
        return const SizedBox.shrink();
      }
      if (event.type == EventTypes.RoomCreate) {
        return RoomCreationStateEvent(event: event);
      }
      return StateMessage(event, onExpand: onExpand, isCollapsed: isCollapsed);
    }

    if (event.type == EventTypes.Message &&
        event.messageType == EventTypes.KeyVerificationRequest) {
      return StateMessage(event);
    }

    final client = Matrix.of(context).client;
    final ownMessage = event.senderId == client.userID;
    final alignment = ownMessage ? Alignment.topRight : Alignment.topLeft;

    var color = theme.colorScheme.surfaceContainerHigh;
    final displayTime = event.type == EventTypes.RoomCreate ||
        nextEvent == null ||
        !event.originServerTs.sameEnvironment(nextEvent!.originServerTs);
    final nextEventSameSender = nextEvent != null &&
        {
          EventTypes.Message,
          EventTypes.Sticker,
          EventTypes.Encrypted,
        }.contains(nextEvent!.type) &&
        nextEvent!.senderId == event.senderId &&
        !displayTime;

    final previousEventSameSender = previousEvent != null &&
        {
          EventTypes.Message,
          EventTypes.Sticker,
          EventTypes.Encrypted,
        }.contains(previousEvent!.type) &&
        previousEvent!.senderId == event.senderId &&
        previousEvent!.originServerTs.sameEnvironment(event.originServerTs);

    final textColor =
        ownMessage ? theme.onBubbleColor : theme.colorScheme.onSurface;

    final linkColor = ownMessage
        ? theme.brightness == Brightness.light
            ? theme.colorScheme.primaryFixed
            : theme.colorScheme.onTertiaryContainer
        : theme.colorScheme.primary;

    final rowMainAxisAlignment =
        ownMessage ? MainAxisAlignment.end : MainAxisAlignment.start;

    final displayEvent = event.getDisplayEvent(timeline);
    const hardCorner = Radius.circular(4);
    const roundedCorner = Radius.circular(AppConfig.borderRadius);
    final borderRadius = BorderRadius.only(
      topLeft: !ownMessage && nextEventSameSender ? hardCorner : roundedCorner,
      topRight: ownMessage && nextEventSameSender ? hardCorner : roundedCorner,
      bottomLeft:
          !ownMessage && previousEventSameSender ? hardCorner : roundedCorner,
      bottomRight:
          ownMessage && previousEventSameSender ? hardCorner : roundedCorner,
    );
    final noBubble = ({
              MessageTypes.Video,
              MessageTypes.Image,
              MessageTypes.Sticker,
            }.contains(event.messageType) &&
            event.fileDescription == null &&
            !event.redacted) ||
        (event.messageType == MessageTypes.Text &&
            event.relationshipType == null &&
            event.onlyEmotes &&
            event.numberEmotes > 0 &&
            event.numberEmotes <= 3);

    if (ownMessage) {
      color =
          displayEvent.status.isError ? Colors.redAccent : theme.bubbleColor;
    }

    final resetAnimateIn = this.resetAnimateIn;
    var animateIn = this.animateIn;

    final sentReactions = <String>{};
    if (singleSelected) {
      sentReactions.addAll(
        event
            .aggregatedEvents(
              timeline,
              RelationshipTypes.reaction,
            )
            .where(
              (event) =>
                  event.senderId == event.room.client.userID &&
                  event.type == 'm.reaction',
            )
            .map(
              (event) => event.content
                  .tryGetMap<String, Object?>('m.relates_to')
                  ?.tryGet<String>('key'),
            )
            .whereType<String>(),
      );
    }

    final showReceiptsRow =
        event.hasAggregatedEvents(timeline, RelationshipTypes.reaction);

    final threadChildren =
        event.aggregatedEvents(timeline, RelationshipTypes.thread);

    final showReactionPicker =
        singleSelected && event.room.canSendDefaultMessages;

    final enterThread = this.enterThread;

    return Center(
      child: ReplySwipe(
        key: ValueKey(event.eventId),
        backgroundBuilder: (context, leftToRight, progress) => Padding(
          padding: const EdgeInsets.only(right: 20.0),
          child: Align(
            alignment: Alignment.centerRight,
            child: Opacity(
              opacity: progress,
              child: const Icon(Icons.reply_outlined),
            ),
          ),
        ),
        leftToRight: AppSettings.swipeRightToLeftToReply.value,
        onReply: onReply,
        child: Container(
          constraints: const BoxConstraints(
            maxWidth: PantheonThemes.maxTimelineWidth,
          ),
          padding: EdgeInsets.only(
            left: 8.0,
            right: 8.0,
            top: nextEventSameSender ? 1.0 : 4.0,
            bottom: previousEventSameSender ? 1.0 : 4.0,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment:
                ownMessage ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: <Widget>[
              if (displayTime || selected)
                Padding(
                  padding: displayTime
                      ? const EdgeInsets.symmetric(vertical: 8.0)
                      : EdgeInsets.zero,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Material(
                        borderRadius:
                            BorderRadius.circular(AppConfig.borderRadius * 2),
                        color: theme.colorScheme.surface.withAlpha(128),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8.0,
                            vertical: 2.0,
                          ),
                          child: Text(
                            event.originServerTs.localizedTime(context),
                            style: TextStyle(
                              fontSize: 12 * AppSettings.fontSizeFactor.value,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.secondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              StatefulBuilder(
                builder: (context, setState) {
                  if (animateIn && resetAnimateIn != null) {
                    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
                      animateIn = false;
                      setState(resetAnimateIn);
                    });
                  }
                  return AnimatedSize(
                    duration: PantheonThemes.animationDuration,
                    curve: PantheonThemes.animationCurve,
                    clipBehavior: Clip.none,
                    alignment: ownMessage
                        ? Alignment.bottomRight
                        : Alignment.bottomLeft,
                    child: animateIn
                        ? const SizedBox(height: 0, width: double.infinity)
                        : Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned(
                                top: 0,
                                bottom: 0,
                                left: 0,
                                right: 0,
                                child: InkWell(
                                  hoverColor: longPressSelect
                                      ? Colors.transparent
                                      : null,
                                  enableFeedback: !selected,
                                  onLongPress: () => onSelect(event),
                                  onTapUp: longPressSelect
                                      ? (_) => onSelect(event)
                                      : (details) => _showContextMenu(
                                            context,
                                            details.globalPosition,
                                          ),
                                  onSecondaryTapUp: (details) =>
                                      _showContextMenu(
                                    context,
                                    details.globalPosition,
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    AppConfig.borderRadius / 2,
                                  ),
                                  child: Material(
                                    borderRadius: BorderRadius.circular(
                                      AppConfig.borderRadius / 2,
                                    ),
                                    color: selected || highlightMarker
                                        ? theme.colorScheme.secondaryContainer
                                            .withAlpha(128)
                                        : Colors.transparent,
                                  ),
                                ),
                              ),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: rowMainAxisAlignment,
                                children: [
                                  if (longPressSelect && !event.redacted)
                                    SizedBox(
                                      height: 32,
                                      width: Avatar.defaultSize,
                                      child: IconButton(
                                        padding: EdgeInsets.zero,
                                        tooltip: L10n.of(context).select,
                                        icon: Icon(
                                          selected
                                              ? Icons.check_circle
                                              : Icons.circle_outlined,
                                        ),
                                        onPressed: () => onSelect(event),
                                      ),
                                    )
                                  else if (nextEventSameSender || ownMessage)
                                    SizedBox(
                                      width: Avatar.defaultSize,
                                      child: Center(
                                        child: SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: event.status ==
                                                  EventStatus.error
                                              ? const Icon(
                                                  Icons.error,
                                                  color: Colors.red,
                                                )
                                              : event.fileSendingStatus != null
                                                  ? const CircularProgressIndicator
                                                      .adaptive(
                                                      strokeWidth: 1,
                                                    )
                                                  : null,
                                        ),
                                      ),
                                    )
                                  else
                                    FutureBuilder<User?>(
                                      future: event.fetchSenderUser(),
                                      builder: (context, snapshot) {
                                        final user = snapshot.data ??
                                            event.senderFromMemoryOrFallback;
                                        return Avatar(
                                          mxContent: user.avatarUrl,
                                          name: user.calcDisplayname(),
                                          onTap: () =>
                                              showMemberActionsPopupMenu(
                                            context: context,
                                            user: user,
                                            onMention: onMention,
                                          ),
                                          presenceUserId: user.stateKey,
                                          presenceBackgroundColor: wallpaperMode
                                              ? Colors.transparent
                                              : null,
                                        );
                                      },
                                    ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (!nextEventSameSender)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              left: 8.0,
                                              bottom: 4,
                                            ),
                                            child: ownMessage ||
                                                    event.room.isDirectChat
                                                ? const SizedBox(height: 12)
                                                : FutureBuilder<User?>(
                                                    future:
                                                        event.fetchSenderUser(),
                                                    builder:
                                                        (context, snapshot) {
                                                      final displayname = snapshot
                                                              .data
                                                              ?.calcDisplayname() ??
                                                          event
                                                              .senderFromMemoryOrFallback
                                                              .calcDisplayname();
                                                      return Text(
                                                        displayname,
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: (theme.brightness ==
                                                                  Brightness
                                                                      .light
                                                              ? displayname
                                                                  .color
                                                              : displayname
                                                                  .lightColorText),
                                                          shadows:
                                                              !wallpaperMode
                                                                  ? null
                                                                  : [
                                                                      const Shadow(
                                                                        offset:
                                                                            Offset(
                                                                          0.0,
                                                                          0.0,
                                                                        ),
                                                                        blurRadius:
                                                                            3,
                                                                        color: Colors
                                                                            .black,
                                                                      ),
                                                                    ],
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      );
                                                    },
                                                  ),
                                          ),
                                        Container(
                                          alignment: alignment,
                                          padding:
                                              const EdgeInsets.only(left: 8),
                                          child: GestureDetector(
                                            behavior:
                                                HitTestBehavior.deferToChild,
                                            onLongPress: longPressSelect
                                                ? null
                                                : () {
                                                    HapticFeedback.vibrate();
                                                    onSelect(event);
                                                  },
                                            onTapUp: longPressSelect
                                                ? (_) => onSelect(event)
                                                : (details) => _showContextMenu(
                                                      context,
                                                      details.globalPosition,
                                                    ),
                                            onSecondaryTapUp: (details) =>
                                                _showContextMenu(
                                              context,
                                              details.globalPosition,
                                            ),
                                            child: AnimatedOpacity(
                                              opacity: animateIn
                                                  ? 0
                                                  : event.messageType ==
                                                              MessageTypes
                                                                  .BadEncrypted ||
                                                          event.status.isSending
                                                      ? 0.5
                                                      : 1,
                                              duration: PantheonThemes
                                                  .animationDuration,
                                              curve:
                                                  PantheonThemes.animationCurve,
                                              child: Container(
                                                decoration: BoxDecoration(
                                                  color: noBubble
                                                      ? Colors.transparent
                                                      : color,
                                                  borderRadius: borderRadius,
                                                ),
                                                clipBehavior: Clip.antiAlias,
                                                child: BubbleBackground(
                                                  colors: colors,
                                                  ignore: noBubble ||
                                                      !ownMessage ||
                                                      MediaQuery.highContrastOf(
                                                        context,
                                                      ),
                                                  scrollController:
                                                      scrollController,
                                                  child: Container(
                                                    decoration: BoxDecoration(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                        AppConfig.borderRadius,
                                                      ),
                                                    ),
                                                    constraints:
                                                        const BoxConstraints(
                                                      maxWidth: PantheonThemes
                                                              .columnWidth *
                                                          1.5,
                                                    ),
                                                    child: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: <Widget>[
                                                        if (event
                                                                .inReplyToEventId(
                                                              includingFallback:
                                                                  false,
                                                            ) !=
                                                            null)
                                                          FutureBuilder<Event?>(
                                                            future: event
                                                                .getReplyEvent(
                                                              timeline,
                                                            ),
                                                            builder: (
                                                              BuildContext
                                                                  context,
                                                              snapshot,
                                                            ) {
                                                              final replyEvent =
                                                                  snapshot
                                                                          .hasData
                                                                      ? snapshot
                                                                          .data!
                                                                      : Event(
                                                                          eventId:
                                                                              event.inReplyToEventId() ?? '\$fake_event_id',
                                                                          content: {
                                                                            'msgtype':
                                                                                'm.text',
                                                                            'body':
                                                                                '...',
                                                                          },
                                                                          senderId:
                                                                              event.senderId,
                                                                          type:
                                                                              'm.room.message',
                                                                          room:
                                                                              event.room,
                                                                          status:
                                                                              EventStatus.sent,
                                                                          originServerTs:
                                                                              DateTime.now(),
                                                                        );
                                                              return Padding(
                                                                padding:
                                                                    const EdgeInsets
                                                                        .only(
                                                                  left: 16,
                                                                  right: 16,
                                                                  top: 8,
                                                                ),
                                                                child: Material(
                                                                  color: Colors
                                                                      .transparent,
                                                                  borderRadius:
                                                                      ReplyContent
                                                                          .borderRadius,
                                                                  child:
                                                                      InkWell(
                                                                    borderRadius:
                                                                        ReplyContent
                                                                            .borderRadius,
                                                                    onTap: () =>
                                                                        scrollToEventId(
                                                                      replyEvent
                                                                          .eventId,
                                                                    ),
                                                                    child:
                                                                        AbsorbPointer(
                                                                      child:
                                                                          ReplyContent(
                                                                        replyEvent,
                                                                        ownMessage:
                                                                            ownMessage,
                                                                        timeline:
                                                                            timeline,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ),
                                                              );
                                                            },
                                                          ),
                                                        MessageContent(
                                                          displayEvent,
                                                          textColor: textColor,
                                                          linkColor: linkColor,
                                                          onInfoTab: onInfoTab,
                                                          borderRadius:
                                                              borderRadius,
                                                          timeline: timeline,
                                                          selected: selected,
                                                        ),
                                                        Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .only(
                                                            bottom: 8.0,
                                                            left: 16.0,
                                                            right: 16.0,
                                                          ),
                                                          child: Row(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            spacing: 4.0,
                                                            children: [
                                                              if (event
                                                                  .hasAggregatedEvents(
                                                                timeline,
                                                                RelationshipTypes
                                                                    .edit,
                                                              ))
                                                                Icon(
                                                                  Icons
                                                                      .edit_outlined,
                                                                  color: textColor
                                                                      .withAlpha(
                                                                    164,
                                                                  ),
                                                                  size: 14,
                                                                ),
                                                              Text(
                                                                displayEvent
                                                                    .originServerTs
                                                                    .localizedTimeShort(
                                                                  context,
                                                                ),
                                                                style:
                                                                    TextStyle(
                                                                  color: textColor
                                                                      .withAlpha(
                                                                    164,
                                                                  ),
                                                                  fontSize: 11,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        Align(
                                          alignment: ownMessage
                                              ? Alignment.bottomRight
                                              : Alignment.bottomLeft,
                                          child: AnimatedSize(
                                            duration: PantheonThemes
                                                .animationDuration,
                                            curve:
                                                PantheonThemes.animationCurve,
                                            child: showReactionPicker
                                                ? Padding(
                                                    padding:
                                                        const EdgeInsets.all(
                                                      4.0,
                                                    ),
                                                    child: Material(
                                                      elevation: 4,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                        AppConfig.borderRadius,
                                                      ),
                                                      shadowColor: theme
                                                          .colorScheme.surface
                                                          .withAlpha(128),
                                                      child:
                                                          SingleChildScrollView(
                                                        scrollDirection:
                                                            Axis.horizontal,
                                                        child: Row(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            ...AppConfig
                                                                .defaultReactions
                                                                .map(
                                                              (emoji) =>
                                                                  IconButton(
                                                                padding:
                                                                    EdgeInsets
                                                                        .zero,
                                                                icon: Center(
                                                                  child:
                                                                      Opacity(
                                                                    opacity: sentReactions
                                                                            .contains(
                                                                      emoji,
                                                                    )
                                                                        ? 0.33
                                                                        : 1,
                                                                    child: Text(
                                                                      emoji,
                                                                      style:
                                                                          const TextStyle(
                                                                        fontSize:
                                                                            20,
                                                                      ),
                                                                      textAlign:
                                                                          TextAlign
                                                                              .center,
                                                                    ),
                                                                  ),
                                                                ),
                                                                onPressed:
                                                                    sentReactions
                                                                            .contains(
                                                                  emoji,
                                                                )
                                                                        ? null
                                                                        : () {
                                                                            onSelect(
                                                                              event,
                                                                            );
                                                                            event.room.sendReaction(
                                                                              event.eventId,
                                                                              emoji,
                                                                            );
                                                                          },
                                                              ),
                                                            ),
                                                            IconButton(
                                                              icon: const Icon(
                                                                Icons
                                                                    .add_reaction_outlined,
                                                              ),
                                                              tooltip: L10n.of(
                                                                context,
                                                              ).customReaction,
                                                              onPressed:
                                                                  () async {
                                                                final emoji =
                                                                    await showAdaptiveBottomSheet<
                                                                        String>(
                                                                  context:
                                                                      context,
                                                                  builder:
                                                                      (context) =>
                                                                          Scaffold(
                                                                    appBar:
                                                                        AppBar(
                                                                      title:
                                                                          Text(
                                                                        L10n.of(context)
                                                                            .customReaction,
                                                                      ),
                                                                      leading:
                                                                          CloseButton(
                                                                        onPressed:
                                                                            () =>
                                                                                Navigator.of(
                                                                          context,
                                                                        ).pop(
                                                                          null,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                    body:
                                                                        SizedBox(
                                                                      height: double
                                                                          .infinity,
                                                                      child:
                                                                          EmojiPicker(
                                                                        onEmojiSelected: (
                                                                          _,
                                                                          emoji,
                                                                        ) =>
                                                                            Navigator.of(
                                                                          context,
                                                                        ).pop(
                                                                          emoji
                                                                              .emoji,
                                                                        ),
                                                                        config:
                                                                            Config(
                                                                          locale:
                                                                              Localizations.localeOf(context),
                                                                          emojiViewConfig:
                                                                              const EmojiViewConfig(
                                                                            backgroundColor:
                                                                                Colors.transparent,
                                                                          ),
                                                                          bottomActionBarConfig:
                                                                              const BottomActionBarConfig(
                                                                            enabled:
                                                                                false,
                                                                          ),
                                                                          categoryViewConfig:
                                                                              CategoryViewConfig(
                                                                            initCategory:
                                                                                Category.SMILEYS,
                                                                            backspaceColor:
                                                                                theme.colorScheme.primary,
                                                                            iconColor:
                                                                                theme.colorScheme.primary.withAlpha(
                                                                              128,
                                                                            ),
                                                                            iconColorSelected:
                                                                                theme.colorScheme.primary,
                                                                            indicatorColor:
                                                                                theme.colorScheme.primary,
                                                                            backgroundColor:
                                                                                theme.colorScheme.surface,
                                                                          ),
                                                                          skinToneConfig:
                                                                              SkinToneConfig(
                                                                            dialogBackgroundColor:
                                                                                Color.lerp(
                                                                              theme.colorScheme.surface,
                                                                              theme.colorScheme.primaryContainer,
                                                                              0.75,
                                                                            )!,
                                                                            indicatorColor:
                                                                                theme.colorScheme.onSurface,
                                                                          ),
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ),
                                                                );
                                                                if (emoji ==
                                                                    null) {
                                                                  return;
                                                                }
                                                                if (sentReactions
                                                                    .contains(
                                                                  emoji,
                                                                )) {
                                                                  return;
                                                                }
                                                                onSelect(event);

                                                                await event.room
                                                                    .sendReaction(
                                                                  event.eventId,
                                                                  emoji,
                                                                );
                                                              },
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  )
                                                : const SizedBox.shrink(),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                  );
                },
              ),
              AnimatedSize(
                duration: PantheonThemes.animationDuration,
                curve: PantheonThemes.animationCurve,
                alignment: Alignment.bottomCenter,
                child: !showReceiptsRow
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: EdgeInsets.only(
                          top: 4.0,
                          left: (ownMessage ? 0 : Avatar.defaultSize) + 12.0,
                          right: ownMessage ? 0 : 12.0,
                        ),
                        child: MessageReactions(event, timeline),
                      ),
              ),
              if (enterThread != null)
                AnimatedSize(
                  duration: PantheonThemes.animationDuration,
                  curve: PantheonThemes.animationCurve,
                  alignment: Alignment.bottomCenter,
                  child: threadChildren.isEmpty
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(
                            top: 2.0,
                            bottom: 8.0,
                            left: Avatar.defaultSize + 8,
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: PantheonThemes.columnWidth * 1.5,
                            ),
                            child: TextButton.icon(
                              style: TextButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                foregroundColor:
                                    theme.colorScheme.onSecondaryContainer,
                                backgroundColor:
                                    theme.colorScheme.secondaryContainer,
                              ),
                              onPressed: () => enterThread(event.eventId),
                              icon: const Icon(Icons.message),
                              label: Text(
                                '${L10n.of(context).countReplies(threadChildren.length)} | ${threadChildren.first.calcLocalizedBodyFallback(
                                  MatrixLocals(L10n.of(context)),
                                  withSenderNamePrefix: true,
                                )}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                ),
              if (displayReadMarker)
                Row(
                  children: [
                    Expanded(
                      child: Divider(
                        color: theme.colorScheme.surfaceContainerHighest,
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 16.0,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        borderRadius:
                            BorderRadius.circular(AppConfig.borderRadius / 3),
                        color: theme.colorScheme.surface.withAlpha(128),
                      ),
                      child: Text(
                        L10n.of(context).readUpToHere,
                        style: TextStyle(
                          fontSize: 12 * AppSettings.fontSizeFactor.value,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Divider(
                        color: theme.colorScheme.surfaceContainerHighest,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContextMenuAction {
  final _MessageAction action;
  final IconData icon;
  final String label;
  final bool isDestructive;

  const _ContextMenuAction({
    required this.action,
    required this.icon,
    required this.label,
    this.isDestructive = false,
  });
}

class _ContextMenuOverlay extends StatelessWidget {
  final Offset position;
  final Size overlaySize;
  final double keyboardHeight;
  final List<_ContextMenuAction> actions;
  final ValueChanged<_MessageAction> onSelected;
  final VoidCallback onDismiss;

  const _ContextMenuOverlay({
    required this.position,
    required this.overlaySize,
    required this.keyboardHeight,
    required this.actions,
    required this.onSelected,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxHeight =
        math.max(0.0, overlaySize.height - keyboardHeight - 16);

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onDismiss,
              onSecondaryTap: onDismiss,
            ),
          ),
          CustomSingleChildLayout(
            delegate: _ContextMenuLayoutDelegate(
              position: position,
              keyboardHeight: keyboardHeight,
            ),
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(12),
              color: theme.colorScheme.surface,
              clipBehavior: Clip.hardEdge,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: 200,
                  maxWidth: 280,
                  maxHeight: maxHeight,
                ),
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    for (final action in actions)
                      ListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        leading: Icon(
                          action.icon,
                          color: action.isDestructive
                              ? theme.colorScheme.error
                              : null,
                        ),
                        title: Text(
                          action.label,
                          maxLines: 1,
                          style: action.isDestructive
                              ? TextStyle(color: theme.colorScheme.error)
                              : null,
                        ),
                        onTap: () => onSelected(action.action),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContextMenuLayoutDelegate extends SingleChildLayoutDelegate {
  final Offset position;
  final double keyboardHeight;

  _ContextMenuLayoutDelegate({
    required this.position,
    required this.keyboardHeight,
  });

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints.loose(constraints.biggest);
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    const padding = 8.0;
    final keyboardTop = size.height - keyboardHeight - padding;
    var dx = position.dx;
    var dy = position.dy;

    if (dx + childSize.width > size.width - padding) {
      dx = size.width - padding - childSize.width;
    }
    if (dx < padding) {
      dx = padding;
    }
    if (dy + childSize.height > keyboardTop) {
      dy = keyboardTop - childSize.height;
    }
    if (dy < padding) {
      dy = padding;
    }
    return Offset(dx, dy);
  }

  @override
  bool shouldRelayout(covariant _ContextMenuLayoutDelegate oldDelegate) =>
      position != oldDelegate.position ||
      keyboardHeight != oldDelegate.keyboardHeight;
}

class BubbleBackground extends StatelessWidget {
  const BubbleBackground({
    super.key,
    required this.scrollController,
    required this.colors,
    required this.ignore,
    required this.child,
  });

  final ScrollController scrollController;
  final List<Color> colors;
  final bool ignore;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return child;
  }
}
