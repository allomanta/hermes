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
});

class ChatSearchHistory {
  static const localBatchSize = 500;
  static const remoteBatchSize = 200;
  static const requestTimeout = Duration(seconds: 10);
  static const decryptionTimeout = Duration(seconds: 15);
  final Room room;
  final String? initialCursor;

  ChatSearchHistory(this.room) : initialCursor = room.prev_batch;

  Future<List<Event>> loadLocal(int start) => room.client.database.getEventList(
    room,
    start: start,
    limit: localBatchSize,
  );

  Future<ChatSearchBatch> loadRemote(String cursor) async {
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
    );
  }
}
