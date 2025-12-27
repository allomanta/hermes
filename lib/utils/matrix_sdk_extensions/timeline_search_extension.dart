import 'dart:convert';

import 'package:matrix/matrix.dart';

extension TimelineSearchExtension on Timeline {
  /// Like [Timeline.startSearch] but always emits a page token so search can
  /// continue even when no matches were found in the scanned history.
  Stream<(List<Event>, String?)> startSearchWithPagination({
    String? searchTerm,
    int requestHistoryCount = 100,
    int maxHistoryRequests = 10,
    String? prevBatch,
    int? limit,
    bool Function(Event)? searchFunc,
    bool includeLocal = true,
  }) async* {
    assert(searchTerm != null || searchFunc != null);
    searchFunc ??= (event) =>
        event.body.toLowerCase().contains(searchTerm?.toLowerCase() ?? '');

    final found = <Event>[];
    var emitted = false;

    if (includeLocal) {
      // Search in-memory events first.
      for (final event in events) {
        if (searchFunc(event)) {
          found.add(event);
          yield (List<Event>.from(found), null);
          emitted = true;
        }
      }

      // Search stored events.
      var start = events.length;
      while (true) {
        final eventsFromStore = await room.client.database.getEventList(
          room,
          start: start,
          limit: requestHistoryCount,
        );
        if (eventsFromStore.isEmpty) break;
        start += eventsFromStore.length;
        for (final event in eventsFromStore) {
          if (searchFunc(event)) {
            found.add(event);
            yield (List<Event>.from(found), null);
            emitted = true;
          }
        }
      }
    }

    var nextBatch = prevBatch ?? room.prev_batch;
    if (nextBatch == null || maxHistoryRequests <= 0) {
      if (!emitted) {
        yield (List<Event>.from(found), null);
      }
      return;
    }

    final encryption = room.client.encryption;
    for (var i = 0; i < maxHistoryRequests; i++) {
      if (nextBatch == null) break;
      if (limit != null && found.length >= limit) break;
      try {
        final resp = await room.client.getRoomEvents(
          room.id,
          Direction.b,
          from: nextBatch,
          limit: requestHistoryCount,
          filter: jsonEncode(StateFilter(lazyLoadMembers: true).toJson()),
        );
        var limitReached = false;
        for (final matrixEvent in resp.chunk) {
          var event = Event.fromMatrixEvent(matrixEvent, room);
          if (event.type == EventTypes.Encrypted && encryption != null) {
            event = await encryption.decryptRoomEvent(event);
            if (event.type == EventTypes.Encrypted &&
                event.messageType == MessageTypes.BadEncrypted &&
                event.content['can_request_session'] == true) {
              // Await requestKey() to ensure decrypted message bodies.
              await event.requestKey();
            }
          }
          if (searchFunc(event)) {
            found.add(event);
            if (limit != null && found.length >= limit) {
              limitReached = true;
              break;
            }
          }
        }
        nextBatch = resp.end;
        if (resp.chunk.isEmpty || nextBatch == null) {
          nextBatch = null;
        }
        yield (List<Event>.from(found), nextBatch);
        emitted = true;
        if (limitReached) break;
      } on MatrixException catch (e) {
        if (e.error == MatrixError.M_FORBIDDEN) {
          break;
        }
        rethrow;
      }
    }

    if (!emitted) {
      yield (List<Event>.from(found), nextBatch);
    }
  }
}
