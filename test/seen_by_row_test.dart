// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/l10n/l10n.dart';
import 'package:hermes/pages/chat/read_receipts_dialog.dart';
import 'package:hermes/pages/chat/seen_by_row.dart';
import 'package:hermes/widgets/avatar.dart';
import 'package:hermes/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:provider/provider.dart';

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

class _Timeline extends Fake implements Timeline {
  _Timeline(this.room, this.events);
  @override
  final Room room;
  @override
  final List<Event> events;
}

class _Matrix extends Fake with Diagnosticable implements MatrixState {
  _Matrix(this.client);
  @override
  final Client client;
}

Future<void> _mountReaders(WidgetTester tester, int count) async {
  final room = _Room();
  addTearDown(room.client.onSync.close);
  final event = Event(
    room: room,
    eventId: r'$target',
    senderId: '@sender:example.org',
    originServerTs: DateTime(2026),
    type: EventTypes.Message,
    content: {'msgtype': MessageTypes.Text, 'body': 'Message'},
  );
  final time = event.originServerTs.millisecondsSinceEpoch;
  room.receiptState.global.otherUsers.addAll({
    for (var i = 0; i < count; i++)
      '@reader-$i:example.org': LatestReceiptStateData(event.eventId, time),
    '@sender:example.org': LatestReceiptStateData(event.eventId, time),
    '@me:example.org': LatestReceiptStateData(event.eventId, time),
  });
  await tester.pumpWidget(
    Provider<MatrixState>.value(
      value: _Matrix(room.client),
      child: MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: SeenByRow(event: event, timeline: _Timeline(room, [event])),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a reader avatar opens the shared read-details popup', (
    tester,
  ) async {
    await _mountReaders(tester, 2);
    expect(find.byType(Avatar), findsNWidgets(2));
    await tester.tap(find.byType(Avatar).first);
    await tester.pumpAndSettle();
    expect(find.byType(ReadReceiptsDialog), findsOneWidget);
    expect(find.text('reader-0'), findsOneWidget);
    expect(find.text('reader-1'), findsOneWidget);
    expect(find.text('@me:example.org'), findsNothing);
    expect(find.text('@sender:example.org'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the overflow bubble opens every reader in a scrollable list', (
    tester,
  ) async {
    await _mountReaders(tester, 10);
    expect(find.byType(Avatar), findsNWidgets(7));
    expect(find.text('+3'), findsOneWidget);
    await tester.tap(find.text('+3'));
    await tester.pumpAndSettle();
    expect(find.byType(ReadReceiptsDialog), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('reader-9'),
      200,
      scrollable: find.descendant(
        of: find.byType(ReadReceiptsDialog),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('reader-9'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
