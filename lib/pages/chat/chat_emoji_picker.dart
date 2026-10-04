// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:hermes/config/themes.dart';
import 'package:hermes/l10n/l10n.dart';
import 'package:hermes/pages/chat/sticker_picker_dialog.dart';
import 'package:hermes/pages/chat/trust_user_key_dialog.dart';
import 'package:hermes/widgets/emoji_search_view.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'chat.dart';

class ChatEmojiPicker extends StatelessWidget {
  final ChatController controller;
  const ChatEmojiPicker(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pickerHeight = MediaQuery.sizeOf(context).height / 2;
    return AnimatedContainer(
      duration: PantheonThemes.animationDuration,
      curve: PantheonThemes.animationCurve,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(),
      height: controller.showEmojiPicker ? pickerHeight : 0,
      child: controller.showEmojiPicker
          ? OverflowBox(
              // Keep autofocus from scrolling a temporarily shortened viewport.
              alignment: Alignment.topCenter,
              minHeight: pickerHeight,
              maxHeight: pickerHeight,
              child: DefaultTabController(
                length: 2,
                initialIndex: controller.emojiPickerIndex,
                child: Column(
                  children: [
                    TabBar(
                      tabs: [
                        Tab(text: L10n.of(context).emojis, height: 32),
                        Tab(text: L10n.of(context).stickers, height: 32),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          EmojiPicker(
                            onEmojiSelected: controller.onEmojiSelected,
                            onBackspacePressed: controller.emojiPickerBackspace,
                            config: Config(
                              locale: Localizations.localeOf(context),
                              emojiViewConfig: EmojiViewConfig(
                                noRecents: const NoRecent(),
                                backgroundColor:
                                    theme.colorScheme.onInverseSurface,
                              ),
                              bottomActionBarConfig:
                                  const BottomActionBarConfig(enabled: false),
                              searchViewConfig: SearchViewConfig(
                                customSearchView: EmojiSearchView.new,
                                backgroundColor: theme.colorScheme.surface,
                                buttonIconColor: theme.colorScheme.primary,
                                hintText: L10n.of(context).search,
                              ),
                              categoryViewConfig: CategoryViewConfig(
                                extraTab: CategoryExtraTab.SEARCH,
                                backspaceColor: theme.colorScheme.primary,
                                iconColor: theme.colorScheme.primary.withAlpha(
                                  128,
                                ),
                                iconColorSelected: theme.colorScheme.primary,
                                indicatorColor: theme.colorScheme.primary,
                                backgroundColor: theme.colorScheme.surface,
                              ),
                              skinToneConfig: SkinToneConfig(
                                dialogBackgroundColor: Color.lerp(
                                  theme.colorScheme.surface,
                                  theme.colorScheme.primaryContainer,
                                  0.75,
                                )!,
                                indicatorColor: theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                          StickerPickerDialog(
                            room: controller.room,
                            onSelected: (sticker) async {
                              final room = controller.room;
                              final reply = controller.replyEvent;
                              final threadId = controller.activeThreadId;
                              final replyId =
                                  reply?.eventId ??
                                  controller.threadLastEventId;
                              final proceed = await showTrustUserInRoomDialog(
                                context,
                                room,
                              );
                              if (!proceed || !context.mounted) return;
                              final eventId = await room.sendEvent({
                                'body': sticker.body,
                                'info': sticker.info ?? {},
                                'url': sticker.url.toString(),
                                // SDK reply options add text fallbacks to the
                                // sticker's description. Only add relations.
                                if (replyId != null || threadId != null)
                                  'm.relates_to': {
                                    if (threadId != null) ...{
                                      'event_id': threadId,
                                      'rel_type': RelationshipTypes.thread,
                                      'is_falling_back': reply == null,
                                    },
                                    if (replyId != null)
                                      'm.in_reply_to': {'event_id': replyId},
                                  },
                                if (reply != null)
                                  'm.mentions': {
                                    'user_ids': [reply.senderId],
                                  },
                              }, type: EventTypes.Sticker);
                              if (eventId != null &&
                                  controller.mounted &&
                                  reply != null &&
                                  identical(controller.replyEvent, reply)) {
                                controller.cancelReplyEventAction();
                              }
                            },
                            onEscape: () {
                              controller.hideEmojiPicker();
                              controller.inputFocus.requestFocus();
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}

class NoRecent extends StatelessWidget {
  const NoRecent({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(
          L10n.of(context).emoteKeyboardNoRecents,
          style: Theme.of(context).textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
