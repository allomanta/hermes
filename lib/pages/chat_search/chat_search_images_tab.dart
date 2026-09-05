import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart';
import 'package:hermes/l10n/l10n.dart';
import 'package:hermes/config/app_config.dart';
import 'package:hermes/pages/chat/events/video_player.dart';
import 'package:hermes/pages/image_viewer/image_viewer.dart';
import 'package:hermes/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:hermes/widgets/matrix.dart';
import 'package:hermes/widgets/mxc_image.dart';
import 'package:hermes/pages/chat_search/search_footer.dart';
import 'package:material_ui/material_ui.dart';

class ChatSearchImagesTab extends StatelessWidget {
  final Room room;
  final List<Event> events;
  final void Function() onStartSearch;
  final bool endReached, isLoading;
  final DateTime? searchedUntil;

  const ChatSearchImagesTab({
    required this.room,
    required this.events,
    required this.onStartSearch,
    required this.endReached,
    required this.isLoading,
    super.key,
    required this.searchedUntil,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(AppConfig.borderRadius / 2);
    final theme = Theme.of(context);

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
          return SearchFooter(
            searchedUntil: searchedUntil,
            endReached: endReached,
            isLoading: isLoading,
            onStartSearch: onStartSearch,
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
                  child: Container(height: 1, color: theme.dividerColor),
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
                  child: Container(height: 1, color: theme.dividerColor),
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
              children: monthEvents.map((event) {
                final mediaTile = event.messageType == MessageTypes.Video
                    ? Material(
                        clipBehavior: Clip.hardEdge,
                        borderRadius: borderRadius,
                        child: EventVideoPlayer(event),
                      )
                    : InkWell(
                        onTap: () => showDialog(
                          context: context,
                          builder: (_) =>
                              ImageViewer(event, outerContext: context),
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
                      top: 0,
                      right: 0,
                      child: IconButton.filledTonal(
                        iconSize: 20,
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.chevron_right_outlined),
                        onPressed: () => Matrix.of(context).openEventInChat(
                          context,
                          roomId: room.id,
                          eventId: event.eventId,
                        ),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ],
        );
      },
    );
  }
}
