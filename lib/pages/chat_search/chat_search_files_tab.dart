import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:hermes/l10n/l10n.dart';
import 'package:hermes/config/app_config.dart';
import 'package:hermes/utils/date_time_extension.dart';
import 'package:hermes/utils/matrix_sdk_extensions/event_extension.dart';
import 'package:hermes/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:hermes/widgets/matrix.dart';

class ChatSearchFilesTab extends StatelessWidget {
  final Room room;
  final Stream<(List<Event>, String?)>? searchStream;
  final void Function({
    String? prevBatch,
    List<Event>? previousSearchResult,
  }) startSearch;

  const ChatSearchFilesTab({
    required this.room,
    required this.startSearch,
    required this.searchStream,
    super.key,
  });

  void _openInChat(BuildContext context, Room room, Event event) {
    if (event.eventId.isEmpty) return;
    final matrix = Matrix.of(context);
    context.push(
      '/${Uri(
        pathSegments: ['rooms', room.id],
        queryParameters: {'event': event.eventId},
      )}',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      matrix.requestEventJump(
        roomId: room.id,
        eventId: event.eventId,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: searchStream,
      builder: (context, snapshot) {
        final theme = Theme.of(context);
        final events = snapshot.data?.$1;
        final nextBatch = snapshot.data?.$2;
        final canSearchMore = nextBatch != null;
        final isSearching = snapshot.connectionState != ConnectionState.done;
        final roomName = room.getLocalizedDisplayname(
          MatrixLocals(L10n.of(context)),
        );
        if (searchStream == null || events == null) {
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator.adaptive(strokeWidth: 2),
              const SizedBox(height: 8),
              Text(
                L10n.of(context).searchIn(
                  roomName,
                ),
              ),
            ],
          );
        }

        if (events.isEmpty) {
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isSearching)
                const CircularProgressIndicator.adaptive(strokeWidth: 2)
              else
                const Icon(Icons.file_present_outlined, size: 64),
              const SizedBox(height: 8),
              Text(
                isSearching
                    ? L10n.of(context).searchIn(roomName)
                    : L10n.of(context).nothingFound,
              ),
              if (!isSearching && canSearchMore)
                Padding(
                  padding: const EdgeInsets.only(top: 16.0),
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      backgroundColor: theme.colorScheme.secondaryContainer,
                      foregroundColor: theme.colorScheme.onSecondaryContainer,
                    ),
                    onPressed: () => startSearch(
                      prevBatch: nextBatch,
                      previousSearchResult: events,
                    ),
                    icon: const Icon(
                      Icons.arrow_downward_outlined,
                    ),
                    label: Text(L10n.of(context).searchMore),
                  ),
                ),
            ],
          );
        }

        return SelectionArea(
          child: ListView.builder(
            padding: const EdgeInsets.all(8.0),
            itemCount: events.length + 1,
          itemBuilder: (context, i) {
            if (i == events.length) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(16.0),
                    child: Center(
                      child: CircularProgressIndicator.adaptive(
                        strokeWidth: 2,
                      ),
                    ),
                );
              }
              if (nextBatch == null) {
                return const SizedBox.shrink();
              }
              return Center(
                child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        backgroundColor: theme.colorScheme.secondaryContainer,
                        foregroundColor: theme.colorScheme.onSecondaryContainer,
                      ),
                      onPressed: () => startSearch(
                        prevBatch: nextBatch,
                        previousSearchResult: events,
                      ),
                      icon: const Icon(
                        Icons.arrow_downward_outlined,
                      ),
                      label: Text(L10n.of(context).searchMore),
                    ),
                  ),
                );
              }
              final event = events[i];
              final filename = event.content.tryGet<String>('filename') ??
                  event.content.tryGet<String>('body') ??
                  L10n.of(context).unknownEvent('File');
              final filetype = (filename.contains('.')
                  ? filename.split('.').last.toUpperCase()
                  : event.content
                          .tryGetMap<String, dynamic>('info')
                          ?.tryGet<String>('mimetype')
                          ?.toUpperCase() ??
                      'UNKNOWN');
              final sizeString = event.sizeString;
              final prevEvent = i > 0 ? events[i - 1] : null;
              final sameEnvironment = prevEvent == null
                  ? false
                  : prevEvent.originServerTs
                      .sameEnvironment(event.originServerTs);
              return Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!sameEnvironment) ...[
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 1,
                              color: theme.dividerColor,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Text(
                              event.originServerTs.localizedTime(context),
                              style: theme.textTheme.labelSmall,
                              textAlign: TextAlign.center,
                            ),
                          ),
                          Expanded(
                            child: Container(
                              height: 1,
                              color: theme.dividerColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                    ],
                    Material(
                      borderRadius:
                          BorderRadius.circular(AppConfig.borderRadius),
                      color: theme.colorScheme.onInverseSurface,
                      clipBehavior: Clip.hardEdge,
                      child: ListTile(
                        leading: const Icon(Icons.file_present_outlined),
                        title: Text(
                          filename,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text('$sizeString | $filetype'),
                        onTap: () => event.saveFile(context),
                        trailing: IconButton(
                          icon: const Icon(Icons.chevron_right_outlined),
                          onPressed: () => _openInChat(context, room, event),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}
