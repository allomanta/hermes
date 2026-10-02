// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/l10n/l10n.dart';
import 'package:hermes/pages/chat/read_receipts_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';

class _Client extends Fake implements Client {
  @override
  String get userID => '@me:example.org';
  @override
  bool get formatLocalpart => false;
  @override
  bool get mxidLocalPartFallback => true;
  @override
  final onSync = CachedStreamController<SyncUpdate>();
}

class _Room extends Fake implements Room {
  @override
  String get id => '!room:example.org';
  @override
  final client = _Client();
  @override
  final receiptState = LatestReceiptState.empty();
  @override
  User unsafeGetUserFromMemoryOrFallback(String id) =>
      User(id, room: this, displayName: id.localpart);
}

Event _event(_Room room) => Event(
  room: room,
  eventId: r'$target',
  senderId: '@sender:example.org',
  originServerTs: DateTime(2026, 10, 1),
  type: EventTypes.Message,
  content: {'msgtype': MessageTypes.Text, 'body': 'Message'},
);

Future<void> _mountPopup(
  WidgetTester tester,
  Event event, {
  Locale locale = const Locale('en'),
}) async {
  await tester.runAsync(() => lookupL10n(locale));
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: [
        ...L10n.localizationsDelegates,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: L10n.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => event.showReadReceiptsDialog(context),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows reader identities and reported time, and refreshes live', (
    tester,
  ) async {
    final room = _Room();
    addTearDown(room.client.onSync.close);
    final event = _event(room);
    final time = DateTime(2026, 10, 1, 12, 34, 56).millisecondsSinceEpoch;
    room.receiptState.global.otherUsers['@alice:example.org'] =
        LatestReceiptStateData(event.eventId, time);
    await _mountPopup(tester, event);
    expect(find.text('Read by'), findsOneWidget);
    expect(find.text('alice'), findsOneWidget);
    expect(find.text('@alice:example.org'), findsOneWidget);
    expect(find.textContaining('12:34:56'), findsOneWidget);
    room.receiptState.global.otherUsers['@bob:example.org'] =
        LatestReceiptStateData(event.eventId, time + 1000);
    room.client.onSync.add(
      SyncUpdate(
        nextBatch: 'receipts',
        rooms: RoomsUpdate(join: {room.id: JoinedRoomUpdate()}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('bob'), findsOneWidget);
    await tester.tap(find.byType(CloseButton));
    await tester.pumpAndSettle();
    expect(find.byType(ReadReceiptsDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty receipts and missing times are described accurately', (
    tester,
  ) async {
    final room = _Room();
    addTearDown(room.client.onSync.close);
    final event = _event(room);
    await _mountPopup(tester, event);
    expect(find.text('No read receipts available'), findsOneWidget);
    room.receiptState.global.otherUsers['@alice:example.org'] =
        LatestReceiptStateData(event.eventId, 0);
    room.client.onSync.add(
      SyncUpdate(
        nextBatch: 'receipt',
        rooms: RoomsUpdate(join: {room.id: JoinedRoomUpdate()}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No read receipts available'), findsNothing);
    expect(find.textContaining('Read time unavailable'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fits a narrow screen with Dutch labels and long user names', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final room = _Room();
    addTearDown(room.client.onSync.close);
    final event = _event(room);
    room
            .receiptState
            .global
            .otherUsers['@long-name-long-name-long-name:example.org'] =
        LatestReceiptStateData(
          event.eventId,
          DateTime(2026, 10, 1).millisecondsSinceEpoch,
        );
    await _mountPopup(tester, event, locale: const Locale('nl'));
    expect(find.text('Gelezen door'), findsOneWidget);
    expect(
      find.textContaining('Laatst gemelde leesbevestiging'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
