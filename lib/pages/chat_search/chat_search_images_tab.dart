import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart';
import 'package:hermes/l10n/l10n.dart';
import 'package:hermes/config/app_config.dart';
import 'package:hermes/pages/chat/events/video_player.dart';
import 'package:hermes/pages/image_viewer/image_viewer.dart';
import 'package:hermes/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:hermes/widgets/matrix.dart';
import 'package:hermes/widgets/mxc_image.dart';

class ChatSearchImagesTab extends StatelessWidget {
  final Room room;
  final Stream<(List<Event>, String?)>? searchStream;
  final void Function({
    String? prevBatch,
    List<Event>? previousSearchResult,
  }) startSearch;

  const ChatSearchImagesTab({
    required this.room,
    required this.startSearch,
    required this.searchStream,
    super.key,
  });

  void _openInChat(BuildContext context, Room room, Event event) {
    if (event.eventId.isEmpty) return;
    final matrix = Matrix.of(context);
    final router = GoRouter.of(context);
    if (router.canPop()) {
      context.pop();
    } else {
      context.go(
        '/${Uri(
          pathSegments: ['rooms', room.id],
          queryParameters: {'event': event.eventId},
        )}',
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      matrix.requestEventJump(
        roomId: room.id,
        eventId: event.eventId,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(AppConfig.borderRadius / 2);
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
                const Icon(Icons.photo_outlined, size: 64),
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
        final eventsByMonth = <DateTime, List<Event>>{};
        for (final event in events) {
          final month = DateTime(
            event.originServerTs.year,
            event.originServerTs.month,
          );
          eventsByMonth[month] ??= [];
          eventsByMonth[month]!.add(event);
        }
        final eventsByMonthList = eventsByMonth.entries.toList();

        const padding = 8.0;

        return ListView.builder(
          itemCount: eventsByMonth.length + 1,
          itemBuilder: (context, i) {
            if (i == eventsByMonth.length) {
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

            final monthEvents = eventsByMonthList[i].value;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 4),
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
                        DateFormat.yMMMM(
                          Localizations.localeOf(context).languageCode,
                        ).format(eventsByMonthList[i].key),
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
                GridView.count(
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  mainAxisSpacing: padding,
                  crossAxisSpacing: padding,
                  clipBehavior: Clip.hardEdge,
                  padding: const EdgeInsets.all(padding),
                  crossAxisCount: 3,
                  children: monthEvents.map(
                    (event) {
                      final mediaTile = event.messageType == MessageTypes.Video
                          ? Material(
                              clipBehavior: Clip.hardEdge,
                              borderRadius: borderRadius,
                              child: EventVideoPlayer(event),
                            )
                          : InkWell(
                              onTap: () => showDialog(
                                context: context,
                                builder: (_) => ImageViewer(
                                  event,
                                  outerContext: context,
                                ),
                              ),
                              borderRadius: borderRadius,
                              child: Material(
                                clipBehavior: Clip.hardEdge,
                                borderRadius: borderRadius,
                                child: MxcImage(
                                  event: event,
                                  width: 128,
                                  height: 128,
                                  fit: BoxFit.cover,
                                  animated: true,
                                  isThumbnail: true,
                                ),
                              ),
                            );

                      return Stack(
                        children: [
                          Positioned.fill(child: mediaTile),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: IconButton(
                              style: IconButton.styleFrom(
                                backgroundColor:
                                    theme.colorScheme.surfaceContainerHighest,
                                foregroundColor:
                                    theme.colorScheme.onSurfaceVariant,
                              ),
                              icon: const Icon(Icons.chevron_right_outlined),
                              onPressed: () => _openInChat(
                                context,
                                room,
                                event,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ).toList(),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
