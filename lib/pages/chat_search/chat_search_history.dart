// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:matrix/matrix.dart';

typedef ChatSearchBatch = ({
  List<Event> events,
  String? nextBatch,
  DateTime? searchedUntil,
  bool hasUndecryptedEvents,
});

class ChatSearchHistory {
  static const localBatchSize = 500;
  static const remoteBatchSize = 200;
  static const requestTimeout = Duration(seconds: 10);
  static const decryptionTimeout = Duration(seconds: 15);
  static const cacheTimeout = Duration(seconds: 30);
  static const maxCachedPages = 32;
  final Room room;
  String? get initialCursor => room.prev_batch;
  final _localPages = <int, Future<List<Event>>>{};
  final _remotePages = <String, Future<ChatSearchBatch>>{};
  late final StreamSubscription<Event> _timelineUpdates;
  late final StreamSubscription<Event> _historyUpdates;

  ChatSearchHistory(this.room) {
    _timelineUpdates = room.client.onTimelineEvent.stream.listen(_invalidate);
    _historyUpdates = room.client.onHistoryEvent.stream.listen(_invalidate);
  }

  void _invalidate(Event event) {
    if (event.room.id != room.id ||
        !identical(event.room.client, room.client)) {
      return;
    }
    _localPages.clear();
    if (event.type == EventTypes.Redaction ||
        event.relationshipType == RelationshipTypes.edit) {
      invalidateRemote();
    }
  }

  void invalidateRemote() {
    _remotePages.clear();
  }

  Future<T> _cached<K, T>(
    Map<K, Future<T>> cache,
    K key,
    Future<T> Function() load, {
    bool Function(T)? cacheable,
  }) {
    final cached = cache.remove(key);
    if (cached != null) {
      cache[key] = cached;
      return cached;
    }
    late final Future<T> pending;
    pending = load()
        .timeout(cacheTimeout)
        .then<T>(
          (value) {
            if (cacheable != null &&
                !cacheable(value) &&
                identical(cache[key], pending)) {
              cache.remove(key);
            }
            return value;
          },
          onError: (Object error, StackTrace stack) {
            if (identical(cache[key], pending)) cache.remove(key);
            Error.throwWithStackTrace(error, stack);
          },
        );
    cache[key] = pending;
    while (cache.length > maxCachedPages) {
      cache.remove(cache.keys.first);
    }
    return pending;
  }

  void dispose() {
    _timelineUpdates.cancel();
    _historyUpdates.cancel();
    _localPages.clear();
    _remotePages.clear();
  }

  Future<List<Event>> loadLocal(int start) => _cached(
    _localPages,
    start,
    () => room.client.database.getEventList(
      room,
      start: start,
      limit: localBatchSize,
    ),
    cacheable: (events) =>
        events.every((event) => event.type != EventTypes.Encrypted),
  );

  Future<ChatSearchBatch> loadRemote(String cursor) =>
      _cached(_remotePages, cursor, () async {
        final response = await room.client
            .getRoomEvents(
              room.id,
              Direction.b,
              from: cursor,
              limit: remoteBatchSize,
              filter: jsonEncode(
                StateFilter(
                  types: [EventTypes.Message, EventTypes.Encrypted],
                ).toJson(),
              ),
            )
            .timeout(requestTimeout);
        final stopwatch = Stopwatch()..start();
        Duration remaining() {
          final duration = decryptionTimeout - stopwatch.elapsed;
          if (duration <= Duration.zero) {
            throw TimeoutException('History decryption timed out');
          }
          return duration;
        }

        final events = <Event>[];
        final requestedSessions = <String>{};
        final encryption = room.client.encryption;
        for (final raw in response.chunk) {
          remaining();
          var event = Event.fromMatrixEvent(raw, room);
          if (event.type == EventTypes.Encrypted && encryption != null) {
            event = await encryption
                .decryptRoomEvent(
                  event,
                  store: false,
                  updateType: EventUpdateType.history,
                )
                .timeout(remaining());
            if (event.type == EventTypes.Encrypted) {
              final content = event.parsedRoomEncryptedContent;
              final sessionId = content.sessionId;
              if (sessionId != null && requestedSessions.add(sessionId)) {
                await Future<void>.sync(
                  () => encryption.keyManager.maybeAutoRequest(
                    room.id,
                    sessionId,
                    content.senderKey,
                    tryOnlineBackup: true,
                    onlineKeyBackupOnly: true,
                    awaitRequest: true,
                  ),
                ).timeout(remaining());
                event = await encryption
                    .decryptRoomEvent(
                      event,
                      store: false,
                      updateType: EventUpdateType.history,
                    )
                    .timeout(remaining());
              }
            }
          }
          if (event.type != EventTypes.Encrypted) events.add(event);
        }
        return (
          events: events,
          nextBatch: response.end,
          searchedUntil: response.chunk.lastOrNull?.originServerTs,
          hasUndecryptedEvents: events.length != response.chunk.length,
        );
      }, cacheable: (batch) => !batch.hasUndecryptedEvents);
}
