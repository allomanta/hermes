// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/config/setting_keys.dart';
import 'package:hermes/utils/matrix_sdk_extensions/room_force_read.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Database extends Fake implements DatabaseApi {
  int? storedCount;
  int? storedHighlights;
  LatestReceiptState? storedReceipts;

  @override
  Future<void> transaction(Future<void> Function() action) => action();

  @override
  Future<void> storeRoomUpdate(
    String roomId,
    SyncRoomUpdate update,
    Event? lastEvent,
    Client client,
  ) async {
    final counts = (update as JoinedRoomUpdate).unreadNotifications!;
    storedCount = counts.notificationCount;
    storedHighlights = counts.highlightCount;
  }

  @override
  Future<void> storeLatestReceiptState(
    String roomId,
    LatestReceiptState receiptState,
  ) async {
    storedReceipts = receiptState;
  }
}

class _Client extends Fake implements Client {
  _Client(this.database);

  @override
  final _Database database;
}

class _Event extends Fake implements Event {
  _Event(this.eventId, this.originServerTs);

  @override
  final String eventId;
  @override
  final DateTime originServerTs;
  @override
  EventStatus get status => EventStatus.synced;
}

class _Room extends Fake implements Room {
  _Room(this.client, this.lastEvent);

  @override
  final _Client client;
  @override
  final String id = '!room:example.org';
  @override
  Event? lastEvent;
  @override
  int notificationCount = 3;
  @override
  int highlightCount = 1;
  @override
  LatestReceiptState receiptState = LatestReceiptState.empty();
  bool _markedUnread = true;
  String? readMarker;
  String? readReceipt;
  Future<void> Function()? onSetReadMarker;

  @override
  bool get markedUnread => _markedUnread;

  @override
  Future<void> markUnread(bool unread) async {
    _markedUnread = unread;
  }

  @override
  Future<void> setReadMarker(
    String? eventId, {
    String? mRead,
    bool? public,
  }) async {
    readMarker = eventId;
    readReceipt = mRead;
    await onSetReadMarker?.call();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
  });

  test(
    'forces the latest event read and clears the cached unread count',
    () async {
      final database = _Database();
      final event = _Event(
        r'$latest:example.org',
        DateTime.fromMillisecondsSinceEpoch(12345),
      );
      final room = _Room(_Client(database), event);

      expect(await room.forceMarkRead(), isTrue);
      expect(room.readMarker, event.eventId);
      expect(room.readReceipt, event.eventId);
      expect(room.markedUnread, isFalse);
      expect(room.notificationCount, 0);
      expect(room.highlightCount, 0);
      expect(database.storedCount, 0);
      expect(database.storedHighlights, 0);
      expect(room.receiptState.global.latestOwnReceipt?.eventId, event.eventId);
      expect(
        database.storedReceipts?.global.latestOwnReceipt?.eventId,
        event.eventId,
      );
    },
  );

  test('keeps a new unread event when it arrives during the request', () async {
    final database = _Database();
    final room = _Room(
      _Client(database),
      _Event(r'$old:example.org', DateTime.fromMillisecondsSinceEpoch(12345)),
    ).._markedUnread = false;
    final pending = Completer<void>();
    room.onSetReadMarker = () => pending.future;

    final forceRead = room.forceMarkRead();
    room.lastEvent = _Event(
      r'$new:example.org',
      DateTime.fromMillisecondsSinceEpoch(12346),
    );
    pending.complete();

    expect(await forceRead, isFalse);
    expect(room.notificationCount, 3);
    expect(database.storedCount, isNull);
  });
}
