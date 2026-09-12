// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/l10n/l10n.dart';
import 'package:hermes/utils/push_helper.dart';
import 'package:matrix/matrix.dart';

class _Room extends Fake implements Room {
  _Room(this.id, {this.isUnreadOrInvited = true});

  @override
  final String id;

  @override
  bool isUnreadOrInvited;
}

class _Client extends Fake implements Client {
  _Client(this.rooms);

  @override
  String get clientName => 'account';

  @override
  final List<Room> rooms;

  @override
  Room? getRoomById(String roomId) =>
      rooms.where((room) => room.id == roomId).firstOrNull;
}

class _Notifications extends Fake implements FlutterLocalNotificationsPlugin {
  final active = <ActiveNotification>[];
  final cancelled = <int>[];
  final shown = <int>[];
  var enumerationCalls = 0;
  void Function()? onEnumerate;

  @override
  Future<List<ActiveNotification>> getActiveNotifications() async {
    enumerationCalls++;
    onEnumerate?.call();
    return [...active];
  }

  @override
  Future<void> cancel({required int id, String? tag}) async {
    cancelled.add(id);
    active.removeWhere((notification) => notification.id == id);
  }

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails,
    String? payload,
  }) async {
    shown.add(id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    trackedRoomNotifications.clear();
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    trackedRoomNotifications.clear();
  });

  test('macOS identifies delivered notifications by their payload', () async {
    final room = _Room('!room:example.org', isUnreadOrInvited: false);
    final client = _Client([room]);
    final notifications = _Notifications()
      ..active.addAll([
        ActiveNotification(
          id: 1,
          payload: HermesPushPayload(
            client.clientName,
            room.id,
            r'$event',
          ).toString(),
        ),
        ActiveNotification(
          id: 2,
          payload: HermesPushPayload(
            'otherAccount',
            room.id,
            r'$event',
          ).toString(),
        ),
      ]);

    await clearReadNotifications(
      client: client,
      flutterLocalNotificationsPlugin: notifications,
    );

    expect(notifications.cancelled, [1]);
  });

  test(
    'a new unread update during enumeration keeps the notification',
    () async {
      final room = _Room('!room:example.org', isUnreadOrInvited: false);
      final client = _Client([room]);
      final notifications = _Notifications()
        ..onEnumerate = () {
          room.isUnreadOrInvited = true;
        }
        ..active.add(
          ActiveNotification(
            id: 1,
            payload: HermesPushPayload(
              client.clientName,
              room.id,
              r'$new',
            ).toString(),
          ),
        );

      await clearReadNotifications(
        client: client,
        flutterLocalNotificationsPlugin: notifications,
      );

      expect(notifications.cancelled, isEmpty);
    },
  );

  for (final platform in [TargetPlatform.linux, TargetPlatform.windows]) {
    test(
      '$platform clears tracked notifications without account metadata from the OS',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        final room = _Room('!room:example.org', isUnreadOrInvited: false);
        final client = _Client([room]);
        final notifications = _Notifications()
          ..active.add(const ActiveNotification(id: 1));
        trackedRoomNotifications[1] = (
          clientName: client.clientName,
          roomId: room.id,
          close: null,
        );

        await clearReadNotifications(
          client: client,
          flutterLocalNotificationsPlugin: notifications,
        );

        expect(notifications.cancelled, [1]);
        expect(trackedRoomNotifications, isEmpty);
        if (platform == TargetPlatform.linux) {
          expect(notifications.enumerationCalls, 0);
        }
      },
    );
  }

  test(
    'browser close handles are used instead of native cancellation',
    () async {
      final room = _Room('!room:example.org');
      final client = _Client([room]);
      final notifications = _Notifications();
      var closed = false;
      trackedRoomNotifications[1] = (
        clientName: client.clientName,
        roomId: room.id,
        close: () => closed = true,
      );

      await clearReadNotifications(
        client: client,
        openedRoomId: room.id,
        flutterLocalNotificationsPlugin: notifications,
      );

      expect(closed, isTrue);
      expect(notifications.cancelled, isEmpty);
      expect(trackedRoomNotifications, isEmpty);
    },
  );

  test(
    'iOS receives only the current account and eligible rooms for APNs cleanup',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      const channel = MethodChannel('im.hermes/notifications');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => calls.add(call));
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      final readRoom = _Room('!read:example.org', isUnreadOrInvited: false);
      final unreadRoom = _Room('!unread:example.org');
      final client = _Client([readRoom, unreadRoom]);
      final notifications = _Notifications();

      await clearReadNotifications(
        client: client,
        flutterLocalNotificationsPlugin: notifications,
      );
      await clearReadNotifications(
        client: client,
        openedRoomId: unreadRoom.id,
        flutterLocalNotificationsPlugin: notifications,
      );

      expect(
        calls.map((call) => call.method),
        everyElement('clearRoomNotifications'),
      );
      expect(calls.map((call) => call.arguments), [
        {
          'clientName': client.clientName,
          'roomIds': [readRoom.id],
        },
        {
          'clientName': client.clientName,
          'roomIds': [unreadRoom.id],
        },
      ]);
      expect(notifications.enumerationCalls, 0);
    },
  );

  test('opening a room clears both push IDs for that account only', () async {
    final room = _Room('!opened:example.org');
    final otherRoom = _Room('!other:example.org', isUnreadOrInvited: false);
    final client = _Client([room, otherRoom]);
    final notifications = _Notifications()
      ..active.addAll([
        ActiveNotification(
          id: '${client.clientName}_${room.id}'.hashCode,
          groupKey: client.clientName,
        ),
        ActiveNotification(id: room.id.hashCode, groupKey: client.clientName),
        ActiveNotification(
          id: '${client.clientName}_${otherRoom.id}'.hashCode,
          groupKey: client.clientName,
        ),
        ActiveNotification(
          id: 'anotherAccount_${room.id}'.hashCode,
          groupKey: 'anotherAccount',
        ),
      ]);

    await clearReadNotifications(
      client: client,
      openedRoomId: room.id,
      flutterLocalNotificationsPlugin: notifications,
    );

    expect(notifications.cancelled, [
      '${client.clientName}_${room.id}'.hashCode,
      room.id.hashCode,
    ]);
    expect(notifications.active, hasLength(2));
  });

  test(
    'general cleanup follows read updates and preserves unread rooms',
    () async {
      final room = _Room('!room:example.org');
      final client = _Client([room]);
      final id = '${client.clientName}_${room.id}'.hashCode;
      final notifications = _Notifications()
        ..active.add(ActiveNotification(id: id, groupKey: client.clientName));

      await clearReadNotifications(
        client: client,
        flutterLocalNotificationsPlugin: notifications,
      );
      expect(notifications.cancelled, isEmpty);

      room.isUnreadOrInvited = false;
      await clearReadNotifications(
        client: client,
        flutterLocalNotificationsPlugin: notifications,
      );
      expect(notifications.cancelled, [id]);
    },
  );

  test('summary is removed when only one chat notification remains', () async {
    const clientName = 'account';
    final notifications = _Notifications()
      ..active.addAll([
        ActiveNotification(id: clientName.hashCode, groupKey: clientName),
        const ActiveNotification(id: 1, groupKey: clientName),
      ]);

    await updateSummaryNotification(
      clientName: clientName,
      l10n: await L10n.delegate.load(const Locale('en')),
      flutterLocalNotificationsPlugin: notifications,
    );

    expect(notifications.cancelled, [clientName.hashCode]);
    expect(notifications.active.single.id, 1);
    expect(notifications.shown, isEmpty);
  });
}
