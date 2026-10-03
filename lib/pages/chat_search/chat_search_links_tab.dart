// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:hermes/config/app_config.dart';
import 'package:hermes/l10n/l10n.dart';
import 'package:hermes/pages/chat_search/search_footer.dart';
import 'package:hermes/utils/date_time_extension.dart';
import 'package:hermes/utils/matrix_sdk_extensions/event_links_extension.dart';
import 'package:hermes/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:hermes/utils/url_launcher.dart';
import 'package:hermes/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class ChatSearchLinksTab extends StatelessWidget {
  final Room room;
  final List<Event> events;
  final void Function() onStartSearch;
  final void Function()? onCancel;
  final bool endReached, isLoading;
  final bool hasError;
  final DateTime? searchedUntil;

  const ChatSearchLinksTab({
    required this.room,
    required this.events,
    required this.onStartSearch,
    required this.endReached,
    required this.isLoading,
    this.hasError = false,
    this.onCancel,
    required this.searchedUntil,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locals = MatrixLocals(L10n.of(context));
    final links = [
      for (final event in events)
        for (final link in event.sharedLinks) (event: event, link: link),
    ];
    return SelectionArea(
      child: ListView.builder(
        padding: const EdgeInsets.all(8.0),
        itemCount: links.length + 1,
        itemBuilder: (context, i) {
          if (i == links.length) {
            return SearchFooter(
              searchedUntil: searchedUntil,
              endReached: endReached,
              isLoading: isLoading,
              hasError: hasError,
              onStartSearch: onStartSearch,
              onCancel: onCancel,
            );
          }
          final event = links[i].event;
          final link = links[i].link;
          final sender = event.senderFromMemoryOrFallback.calcDisplayname(
            i18n: locals,
          );
          return Padding(
            padding: const EdgeInsets.all(8.0),
            child: Material(
              borderRadius: BorderRadius.circular(AppConfig.borderRadius),
              color: theme.colorScheme.onInverseSurface,
              clipBehavior: Clip.hardEdge,
              child: ListTile(
                leading: const Icon(Icons.link_outlined),
                title: Text(
                  link.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${link.url}\n$sender | ${event.originServerTs.localizedTime(context)}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                isThreeLine: true,
                onTap: () =>
                    UrlLauncher(context, link.url, link.name).launchUrl(),
                trailing: IconButton(
                  icon: const Icon(Icons.chevron_right_outlined),
                  onPressed: () => Matrix.of(context).openEventInChat(
                    context,
                    roomId: room.id,
                    eventId: event.eventId,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
