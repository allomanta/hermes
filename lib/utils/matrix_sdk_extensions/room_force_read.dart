// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:hermes/config/setting_keys.dart';
import 'package:matrix/matrix.dart';

extension RoomForceRead on Room {
  /// Clears a stale unread count locally after sending the latest read marker.
  Future<bool> forceMarkRead() async {
    final latestEvent = lastEvent;
    final eventId = latestEvent?.eventId;
    final syncedEventId =
        latestEvent?.status.isSynced == true &&
            eventId != null &&
            eventId.isValidMatrixIdStrict()
        ? eventId
        : null;
    final sendPublicReceipt = AppSettings.sendPublicReadReceipts.value;

    if (syncedEventId != null) {
      await setReadMarker(
        syncedEventId,
        mRead: syncedEventId,
        public: sendPublicReceipt,
      );
    }
    if (markedUnread) await markUnread(false);
    if (lastEvent?.eventId != eventId) return false;

    final updatedReceiptState = LatestReceiptState.fromJson(
      receiptState.toJson(),
    );
    if (syncedEventId != null) {
      final timestamp = latestEvent!.originServerTs.millisecondsSinceEpoch;
      if ((updatedReceiptState.global.latestOwnReceipt?.ts ?? 0) <= timestamp) {
        final receipt = LatestReceiptStateData(syncedEventId, timestamp);
        updatedReceiptState.global.ownPrivate = receipt;
        if (sendPublicReceipt) updatedReceiptState.global.ownPublic = receipt;
        updatedReceiptState.global.latestOwnReceipt = receipt;
      }
    }

    await client.database.transaction(() async {
      await client.database.storeRoomUpdate(
        id,
        JoinedRoomUpdate(
          unreadNotifications: UnreadNotificationCounts(
            notificationCount: 0,
            highlightCount: 0,
          ),
        ),
        latestEvent,
        client,
      );
      if (syncedEventId != null) {
        await client.database.storeLatestReceiptState(id, updatedReceiptState);
      }
    });
    if (lastEvent?.eventId != eventId) return false;

    receiptState = updatedReceiptState;
    notificationCount = 0;
    highlightCount = 0;
    return true;
  }
}
