import 'dart:async';

import 'package:matrix/matrix.dart';

class BackfillService {
  /// Backfill message history for all joined chats in the given [client].
  ///
  /// This paginates older events per room via the Timeline API and relies on
  /// the SDK/database to persist them locally. Media is not fetched.
  ///
  /// [perRequest] controls how many events to request per pagination call,
  /// [maxPerRoom] caps the total number of events pulled per room to avoid
  /// unbounded work.
  ///
  /// You can pass [setProgress] to update a progress indicator in [0,1].
  static Future<void> backfillAllChats(
    Client client, {
    void Function(double?)? setProgress,
    int perRequest = 200,
    int maxPerRoom = 2000,
  }) async {
    await client.roomsLoading;

    // Only joined rooms; skip invites/left and spaces by default.
    final rooms = client.rooms
        .where((r) => r.membership == Membership.join && !r.isSpace)
        .toList();

    final total = rooms.length == 0 ? 1 : rooms.length;
    var index = 0;

    for (final room in rooms) {
      index++;
      try {
        setProgress?.call(index / total);

        final timeline = await room.getTimeline(
          onUpdate: () {},
          onInsert: (_) {},
        );

        var fetched = 0;
        // Paginate older chunks until no more history or we hit our cap.
        while (timeline.canRequestHistory && fetched < maxPerRoom) {
          final before = timeline.events.length;
          await timeline.requestHistory(historyCount: perRequest);
          final after = timeline.events.length;

          // If no new events were added, break to avoid tight loops.
          final diff = after - before;
          if (diff <= 0) break;

          fetched += diff;
          // Yield to avoid starving the event loop.
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }

        // Detach listeners to avoid leaks when not displayed.
        timeline.cancelSubscriptions();
      } catch (e, s) {
        Logs().w('Backfill failed for room ${room.id}', e, s);
      }
    }

    setProgress?.call(1.0);
  }
}

