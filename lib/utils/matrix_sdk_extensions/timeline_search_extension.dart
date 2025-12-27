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
    bool persistHistory = false,
  }) async* {
    assert(searchTerm != null || searchFunc != null);
    searchFunc ??= (event) =>
        event.body.toLowerCase().contains(searchTerm?.toLowerCase() ?? '');

    final found = <Event>[];
    var emitted = false;
    final encryption = room.client.encryption;

    Future<Event> prepareEvent(Event event) async {
      if (event.type == EventTypes.Encrypted && encryption != null) {
        event = await encryption.decryptRoomEvent(
          event,
          store: persistHistory,
          updateType: EventUpdateType.history,
        );
        if (event.type == EventTypes.Encrypted &&
            event.messageType == MessageTypes.BadEncrypted &&
            event.content['can_request_session'] == true) {
          await event.requestKey();
        }
      }
      return event;
    }

    if (includeLocal) {
      // Search in-memory events first.
      for (final event in events) {
        final candidate = await prepareEvent(event);
        if (searchFunc(candidate)) {
          found.add(candidate);
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
          final candidate = await prepareEvent(event);
          if (searchFunc(candidate)) {
            found.add(candidate);
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
        if (persistHistory && resp.chunk.isNotEmpty && resp.end != null) {
          await room.client.database.transaction(() async {
            room.prev_batch = resp.end;
            await room.client.database.setRoomPrevBatch(
              resp.end,
              room.id,
              room.client,
            );
            await room.client.handleSync(
              SyncUpdate(
                nextBatch: '',
                rooms: RoomsUpdate(
                  join: room.membership == Membership.join
                      ? {
                          room.id: JoinedRoomUpdate(
                            state: resp.state,
                            timeline: TimelineUpdate(
                              limited: false,
                              events: resp.chunk,
                              prevBatch: resp.end,
                            ),
                          ),
                        }
                      : null,
                  leave: room.membership != Membership.join
                      ? {
                          room.id: LeftRoomUpdate(
                            state: resp.state,
                            timeline: TimelineUpdate(
                              limited: false,
                              events: resp.chunk,
                              prevBatch: resp.end,
                            ),
                          ),
                        }
                      : null,
                ),
              ),
              direction: Direction.b,
            );
          });
        }
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
