// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/l10n/l10n.dart';
import 'package:hermes/pages/chat_list/chat_list_message_search.dart';
import 'package:hermes/pages/chat_search/chat_search_message_tab.dart';
import 'package:hermes/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

class _Database extends Fake implements DatabaseApi {
  final events = <String, List<Event>>{};
  final requests = <(String, int, int?)>[];
  Completer<List<Event>>? pending;
  bool fail = false;

  @override
  Future<List<Event>> getEventList(
    Room room, {
    int start = 0,
    bool onlySending = false,
    int? limit,
  }) async {
    requests.add((room.id, start, limit));
    if (fail) throw StateError('Database unavailable');
    if (pending != null) return pending!.future;
    final stored = events[room.id] ?? [];
    if (start >= stored.length) return [];
    return stored.sublist(start, min(stored.length, start + limit!));
  }
}

class _Client extends Fake implements Client {
  @override
  final _Database database = _Database();
  @override
  final rooms = <Room>[];
  @override
  String get userID => '@me:example.org';
  @override
  bool get formatLocalpart => false;
  @override
  bool get mxidLocalPartFallback => true;
}

class _Room extends Fake implements Room {
  _Room(
    this.client,
    this.id,
    this.name, {
    this.isSpace = false,
    this.membership = Membership.join,
  }) {
    client.rooms.add(this);
  }
  @override
  final _Client client;
  @override
  final String id;
  @override
  final String name;
  @override
  final bool isSpace;
  @override
  final Membership membership;
  @override
  final Map<String, Map<String, StrippedStateEvent>> states = {};
  @override
  String getLocalizedDisplayname([
    MatrixLocalizations i18n = const MatrixDefaultLocalizations(),
  ]) => name;
  @override
  User unsafeGetUserFromMemoryOrFallback(String id) =>
      User(id, room: this, displayName: 'Alice');
}

class _Matrix extends Fake with Diagnosticable implements MatrixState {
  _Matrix(this.client);
  @override
  final _Client client;
  String? openedRoom, openedEvent;
  @override
  void openEventInChat(
    BuildContext context, {
    required String roomId,
    required String eventId,
  }) {
    openedRoom = roomId;
    openedEvent = eventId;
  }
}

Event _event(
  Room room,
  String body, {
  String id = r'$message',
  int minute = 0,
  String type = EventTypes.Message,
  String? html,
}) => Event(
  room: room,
  eventId: id,
  senderId: '@alice:example.org',
  type: type,
  originServerTs: DateTime(2026, 10, 3, 12, minute),
  content: {
    'msgtype': MessageTypes.Text,
    'body': body,
    if (html != null) ...{
      'format': 'org.matrix.custom.html',
      'formatted_body': html,
    },
  },
);

Future<_Matrix> _mount(
  WidgetTester tester,
  _Client client,
  String query, {
  Brightness brightness = Brightness.light,
}) async {
  final matrix = _Matrix(client);
  await tester.pumpWidget(
    Provider<MatrixState>.value(
      value: matrix,
      child: MaterialApp(
        theme: ThemeData(brightness: brightness),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: CustomScrollView(
            slivers: [ChatListMessageSearch(client: client, query: query)],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return matrix;
}

void main() {
  testWidgets('searches all local pages and joined chats, newest first', (
    tester,
  ) async {
    final client = _Client();
    final first = _Room(client, '!first:example.org', 'First chat');
    final second = _Room(client, '!second:example.org', 'Second chat');
    _Room(client, '!space:example.org', 'Space', isSpace: true);
    _Room(client, '!left:example.org', 'Left', membership: Membership.leave);
    _Room(
      client,
      '!invite:example.org',
      'Invite',
      membership: Membership.invite,
    );
    final older = _event(first, 'Project PHOENIX', id: r'$older');
    final newer = _event(second, 'Project Phoenix update', minute: 5);
    final redacted = _event(first, 'Removed Phoenix', id: r'$removed')
      ..setRedactionEvent(_event(first, '', type: EventTypes.Redaction));
    client.database.events[first.id] = [
      for (var i = 0; i < 500; i++) _event(first, 'Other text', id: '$i'),
      older,
      older,
      redacted,
      _event(first, 'Phoenix', id: r'$state', type: EventTypes.RoomName),
      _event(first, 'Phoenix', id: r'$encrypted', type: EventTypes.Encrypted),
    ];
    client.database.events[second.id] = [newer];
    final matrix = await _mount(tester, client, '  phoenix  ');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(client.database.requests, [
      (first.id, 0, 500),
      (first.id, 500, 500),
      (first.id, 1000, 500),
      (second.id, 0, 500),
      (second.id, 500, 500),
    ]);
    final tiles = tester.widgetList<MessageSearchResultListTile>(
      find.byType(MessageSearchResultListTile),
    );
    expect(tiles.map((tile) => tile.event), [newer, older]);
    expect(find.text('First chat'), findsOneWidget);
    expect(find.text('Second chat'), findsOneWidget);
    expect(find.text('Project PHOENIX'), findsOneWidget);
    await tester.tap(find.text('Project PHOENIX'));
    expect(matrix.openedRoom, first.id);
    expect(matrix.openedEvent, older.eventId);
    await tester.tap(find.byIcon(Icons.chevron_right_outlined).first);
    expect(matrix.openedRoom, second.id);
    expect(matrix.openedEvent, newer.eventId);
    expect(tester.takeException(), isNull);
  });

  testWidgets('debounces typing and searches the latest query only', (
    tester,
  ) async {
    final client = _Client();
    final room = _Room(client, '!room:example.org', 'Chat');
    client.database.events[room.id] = [_event(room, 'Latest query')];
    await _mount(tester, client, 'First');
    await tester.pump(const Duration(milliseconds: 299));
    expect(client.database.requests, isEmpty);
    await _mount(tester, client, 'Latest');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(client.database.requests.length, 2);
    expect(find.text('Latest query'), findsOneWidget);
  });

  for (final change in ['query', 'account', 'dispose']) {
    testWidgets('ignores a pending search after $change changes', (
      tester,
    ) async {
      final client = _Client();
      final room = _Room(client, '!old:example.org', 'Old account');
      final pending = client.database.pending = Completer<List<Event>>();
      await _mount(tester, client, 'old');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(client.database.requests.length, 1);
      client.database.pending = null;
      final next = change == 'account' ? _Client() : client;
      final nextRoom = change == 'account'
          ? _Room(next, '!new:example.org', 'New account')
          : room;
      final nextBody = change == 'account'
          ? 'Old account new match'
          : 'New match';
      next.database.events[nextRoom.id] = [_event(nextRoom, nextBody)];
      if (change == 'dispose') {
        await tester.pumpWidget(const SizedBox.shrink());
      } else {
        await _mount(tester, next, change == 'account' ? 'old' : 'new');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
        expect(find.text(nextBody), findsOneWidget);
      }
      pending.complete([_event(room, 'Old stale match')]);
      await tester.pumpAndSettle();
      expect(find.text('Old stale match'), findsNothing);
      if (change != 'dispose') expect(find.text(nextBody), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('empty queries do not read the database', (tester) async {
    final client = _Client();
    _Room(client, '!room:example.org', 'Chat');
    await _mount(tester, client, '   ');
    await tester.pumpAndSettle();
    expect(client.database.requests, isEmpty);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a local database error can be retried', (tester) async {
    final client = _Client();
    final room = _Room(client, '!room:example.org', 'Chat');
    client.database
      ..events[room.id] = [_event(room, 'Retry match')]
      ..fail = true;
    await _mount(tester, client, 'retry');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Try again'), findsOneWidget);
    client.database.fail = false;
    await tester.tap(find.text('Try again'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Retry match'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('more results are revealed without rereading local history', (
    tester,
  ) async {
    final client = _Client();
    final room = _Room(client, '!room:example.org', 'Chat');
    client.database.events[room.id] = [
      for (var i = 0; i < 52; i++)
        _event(room, 'Match $i', id: '$i', minute: i),
    ];
    await _mount(tester, client, 'match');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SliverList>(find.byType(SliverList))
          .delegate
          .estimatedChildCount,
      50,
    );
    final requestCount = client.database.requests.length;
    await tester.scrollUntilVisible(find.text('Search more...'), 500);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search more...'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SliverList>(find.byType(SliverList))
          .delegate
          .estimatedChildCount,
      52,
    );
    expect(client.database.requests.length, requestCount);
    expect(find.text('Search more...'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('rich text results fit a phone in ${brightness.name}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = _Client();
      final room = _Room(client, '!room:example.org', 'A long chat name ' * 8);
      client.database.events[room.id] = [
        _event(room, 'Fallback body', html: '<p>Project <b>Phoenix</b></p>'),
      ];
      await _mount(tester, client, 'phoenix', brightness: brightness);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.text('Project Phoenix'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
