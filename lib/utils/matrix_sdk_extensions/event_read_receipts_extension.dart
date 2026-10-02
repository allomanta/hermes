// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

extension EventReadReceiptsExtension on Event {
  List<Receipt> readReceiptsForMessage({
    Timeline? timeline,
    bool includeLater = true,
  }) {
    final positions = <String, int>{};
    if (includeLater && timeline?.room == room) {
      final events = timeline!.events;
      for (var i = 0; i < events.length; i++) {
        positions[events[i].eventId] = i;
      }
    }
    final position = positions[eventId];
    final state = room.receiptState;
    final scoped = relationshipType == RelationshipTypes.thread
        ? state.byThread[relationshipEventId]
        : state.mainThread;
    final receipts = <String, Receipt>{};
    for (final scope in [state.global, ?scoped]) {
      for (final entry in scope.otherUsers.entries) {
        if (entry.key == room.client.userID || entry.key == senderId) continue;
        final data = entry.value;
        final receiptPosition = positions[data.eventId];
        if (data.eventId != eventId &&
            (position == null ||
                receiptPosition == null ||
                receiptPosition > position)) {
          continue;
        }
        final previous = receipts[entry.key];
        if (previous != null && !data.timestamp.isAfter(previous.time)) {
          continue;
        }
        receipts[entry.key] = Receipt(
          room.unsafeGetUserFromMemoryOrFallback(entry.key),
          data.timestamp,
        );
      }
    }
    return receipts.values.toList()..sort((a, b) {
      final byTime = b.time.compareTo(a.time);
      return byTime == 0 ? a.user.id.compareTo(b.user.id) : byTime;
    });
  }
}
