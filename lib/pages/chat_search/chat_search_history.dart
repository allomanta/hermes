// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

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
  final Room room;
  final String? initialCursor;

  ChatSearchHistory(this.room) : initialCursor = room.prev_batch;

  Future<List<Event>> loadLocal(int start) => room.client.database.getEventList(
    room,
    start: start,
    limit: localBatchSize,
  );

  Future<ChatSearchBatch> loadRemote(String cursor) async {
    final response = await room.client.getRoomEvents(
      room.id,
      Direction.b,
      from: cursor,
      limit: remoteBatchSize,
      filter: jsonEncode(
        StateFilter(types: [EventTypes.Message, EventTypes.Encrypted]).toJson(),
      ),
    );
    final events = <Event>[];
    final requestedSessions = <String>{};
    final encryption = room.client.encryption;
    for (final raw in response.chunk) {
      var event = Event.fromMatrixEvent(raw, room);
      if (event.type == EventTypes.Encrypted && encryption != null) {
        event = await encryption.decryptRoomEvent(
          event,
          store: false,
          updateType: EventUpdateType.history,
        );
        if (event.type == EventTypes.Encrypted) {
          final content = event.parsedRoomEncryptedContent;
          final sessionId = content.sessionId;
          if (sessionId != null && requestedSessions.add(sessionId)) {
            await encryption.keyManager.maybeAutoRequest(
              room.id,
              sessionId,
              content.senderKey,
              tryOnlineBackup: true,
              onlineKeyBackupOnly: true,
              awaitRequest: true,
            );
            event = await encryption.decryptRoomEvent(
              event,
              store: false,
              updateType: EventUpdateType.history,
            );
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
