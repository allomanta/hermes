// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:hermes/l10n/l10n.dart';
import 'package:hermes/pages/chat_search/search_footer.dart';
import 'package:hermes/utils/date_time_extension.dart';
import 'package:hermes/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:hermes/utils/url_launcher.dart';
import 'package:hermes/widgets/avatar.dart';
import 'package:hermes/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class ChatSearchMessageTab extends StatelessWidget {
  final String searchQuery;
  final Room room;
  final List<Event> events;
  final void Function() onStartSearch;
  final void Function()? onCancel;
  final bool endReached, isLoading;
  final bool hasError;
  final DateTime? searchedUntil;

  const ChatSearchMessageTab({
    required this.searchQuery,
    required this.room,
    required this.onStartSearch,
    required this.events,
    required this.searchedUntil,
    required this.endReached,
    required this.isLoading,
    this.hasError = false,
    this.onCancel,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (events.isEmpty && searchQuery.isEmpty) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.search_outlined, size: 64),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Text(
              L10n.of(context).searchIn(
                room.getLocalizedDisplayname(MatrixLocals(L10n.of(context))),
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      );
    }

    return SelectionArea(
      child: ListView.separated(
        itemCount: events.length + 1,
        separatorBuilder: (context, _) =>
            Divider(color: theme.dividerColor, height: 1),
        itemBuilder: (context, i) {
          if (i == events.length) {
            return SearchFooter(
              searchedUntil: searchedUntil,
              endReached: endReached,
              isLoading: isLoading,
              hasError: hasError,
              onStartSearch: onStartSearch,
              onCancel: onCancel,
            );
          }
          final event = events[i];
          final sender = event.senderFromMemoryOrFallback;
          final displayname = sender.calcDisplayname(
            i18n: MatrixLocals(L10n.of(context)),
          );
          return MessageSearchResultListTile(
            sender: sender,
            displayname: displayname,
            event: event,
            room: room,
          );
        },
      ),
    );
  }
}

class MessageSearchResultListTile extends StatelessWidget {
  const MessageSearchResultListTile({
    required this.sender,
    required this.displayname,
    required this.event,
    required this.room,
    this.showRoomName = false,
    super.key,
  });

  final User sender;
  final String displayname;
  final Event event;
  final Room room;
  final bool showRoomName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      onTap: () => Matrix.of(
        context,
      ).openEventInChat(context, roomId: room.id, eventId: event.eventId),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showRoomName)
            Text(
              room.getLocalizedDisplayname(MatrixLocals(L10n.of(context))),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          Row(
            children: [
              Avatar(mxContent: sender.avatarUrl, name: displayname, size: 16),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  displayname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: theme.colorScheme.onSurface),
                ),
              ),
              Expanded(
                child: Text(
                  ' | ${event.originServerTs.localizedTimeShort(context)}',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      subtitle: Linkify(
        textScaleFactor: MediaQuery.textScalerOf(context).scale(1),
        options: const LinkifyOptions(humanize: false),
        style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        linkStyle: TextStyle(
          color: theme.colorScheme.primary,
          decoration: TextDecoration.underline,
          decorationColor: theme.colorScheme.primary,
        ),
        onOpen: (url) => UrlLauncher(context, url.url).launchUrl(),
        text: event
            .calcLocalizedBodyFallback(
              plaintextBody: true,
              removeMarkdown: true,
              MatrixLocals(L10n.of(context)),
            )
            .trim(),
        maxLines: 7,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        icon: const Icon(Icons.chevron_right_outlined),
        onPressed: () => Matrix.of(
          context,
        ).openEventInChat(context, roomId: room.id, eventId: event.eventId),
      ),
    );
  }
}
