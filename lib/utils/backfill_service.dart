import 'dart:async';

import 'package:matrix/matrix.dart';

import 'package:hermes/utils/matrix_sdk_extensions/event_extension.dart';

class BackfillService {
  /// Backfill message history for a single [room].
  ///
  /// This paginates older events via the Timeline API and relies on the
  /// SDK/database to persist them locally. Media is not fetched.
  ///
  /// [perRequest] controls how many events to request per pagination call,
  /// [maxEvents] caps the total number of events pulled to avoid unbounded work.
  static Future<void> backfillRoom(
    Room room, {
    void Function(double?)? setProgress,
    int perRequest = 200,
    int maxEvents = 2000,
    bool includeMedia = false,
  }) async {
    if (room.membership != Membership.join || room.isSpace) {
      setProgress?.call(1.0);
      return;
    }

    try {
      final timeline = await room.getTimeline(
        onUpdate: () {},
        onInsert: (_) {},
      );

      var fetched = 0;
      while (timeline.canRequestHistory &&
          (maxEvents <= 0 || fetched < maxEvents)) {
        final before = timeline.events.length;
        await timeline.requestHistory(historyCount: perRequest);
        final after = timeline.events.length;
        final diff = after - before;
        if (diff <= 0) break;

        if (includeMedia) {
          final newEvents = timeline.events.sublist(before, after);
          await _prefetchMedia(newEvents);
        }

        fetched += diff;
        setProgress?.call(maxEvents > 0 ? fetched / maxEvents : null);
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      timeline.cancelSubscriptions();
      setProgress?.call(1.0);
    } catch (e, s) {
      Logs().w('Backfill failed for room ${room.id}', e, s);
      setProgress?.call(1.0);
    }
  }

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

    final total = rooms.isEmpty ? 1 : rooms.length;
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
        while (timeline.canRequestHistory &&
            (maxPerRoom <= 0 || fetched < maxPerRoom)) {
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

  static Future<void> _prefetchMedia(Iterable<Event> events) async {
    for (final event in events) {
      if (!event.hasAttachment) continue;
      try {
        if (event.hasThumbnail && event.isThumbnailSmallEnough) {
          await event.downloadAndDecryptAttachment(getThumbnail: true);
        }
        if (event.isAttachmentSmallEnough) {
          await event.downloadAndDecryptAttachment();
        }
      } catch (e, s) {
        Logs().v('Media prefetch failed for ${event.eventId}', e, s);
      }
    }
  }
}
