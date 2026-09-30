// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/l10n/l10n.dart';
import 'package:hermes/pages/chat_search/chat_search_page.dart';
import 'package:hermes/utils/matrix_sdk_extensions/event_links_extension.dart';
import 'package:hermes/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

class _Client extends Fake implements Client {
  late _Room room;
  @override
  Room? getRoomById(String id) => room.id == id ? room : null;
  @override
  bool get formatLocalpart => false;
  @override
  bool get mxidLocalPartFallback => true;
}

class _Room extends Fake implements Room {
  _Room() {
    client.room = this;
  }
  @override
  final _Client client = _Client();
  @override
  String get id => '!chat:example.org';
  @override
  String getLocalizedDisplayname([
    MatrixLocalizations i18n = const MatrixDefaultLocalizations(),
  ]) => 'Chat';
  @override
  User unsafeGetUserFromMemoryOrFallback(String id) =>
      User(id, room: this, displayName: 'Alice');

  final batches = <String?>[];
  final pages = <List<Event>>[];
  Completer<({List<Event> events, String? nextBatch, DateTime? searchedUntil})>?
  pending;

  @override
  Future<({List<Event> events, String? nextBatch, DateTime? searchedUntil})>
  searchEvents({
    String? searchTerm,
    bool Function(Event)? searchFunc,
    String? nextBatch,
    int limit = 1000,
    Set<String> includeEventTypes = const {
      EventTypes.Message,
      EventTypes.Encrypted,
    },
  }) async {
    batches.add(nextBatch);
    if (pending != null) return pending!.future;
    final page = batches.length - 1;
    return (
      events: pages[page].where(searchFunc!).toList(),
      nextBatch: page + 1 < pages.length ? 'older' : null,
      searchedUntil: DateTime(2026, 9, 1),
    );
  }
}

class _Matrix extends Fake with Diagnosticable implements MatrixState {
  _Matrix(this.client);
  @override
  final Client client;
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
  String? html,
  String id = r'$message',
  String type = EventTypes.Message,
}) => Event(
  room: room,
  eventId: id,
  senderId: '@alice:example.org',
  type: type,
  originServerTs: DateTime(2026, 9, 1, 12),
  content: {
    'msgtype': MessageTypes.Text,
    'body': body,
    if (html != null) ...{
      'format': 'org.matrix.custom.html',
      'formatted_body': html,
    },
  },
);

Future<_Matrix> _mountSearch(
  WidgetTester tester,
  _Room room, {
  Brightness brightness = Brightness.light,
}) async {
  final matrix = _Matrix(room.client);
  await tester.pumpWidget(
    Provider<MatrixState>.value(
      value: matrix,
      child: MaterialApp(
        theme: ThemeData(brightness: brightness),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: ChatSearchPage(roomId: room.id),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return matrix;
}

void main() {
  test('extracts plain web links and deduplicates within a message', () {
    final event = _event(
      _Room(),
      'https://example.org http://other.org www.example.net https://example.org',
    );
    expect(event.sharedLinks.map((link) => link.url), [
      'https://example.org',
      'http://other.org',
      'https://www.example.net',
    ]);
  });

  test('uses formatted link targets, labels and HTML entity decoding', () {
    final event = _event(
      _Room(),
      '[Read this](https://example.org/?a=1&b=2)',
      html:
          '<p><a href="https://example.org/?a=1&amp;b=2">Read this</a> '
          '<a href="https://actual.org">https://label.org</a> '
          'https://plain.org</p>',
    );
    expect(event.sharedLinks, [
      (url: 'https://example.org/?a=1&b=2', name: 'Read this'),
      (url: 'https://actual.org', name: 'https://label.org'),
      (url: 'https://plain.org', name: 'https://plain.org'),
    ]);
  });

  test('excludes quoted reply links in plain and formatted messages', () {
    final room = _Room();
    const body = '> <@bob:example.org> https://quoted.org\n\nhttps://new.org';
    const replyHtml =
        '<mx-reply><blockquote><a href="https://quoted.org">Old link</a>'
        '</blockquote></mx-reply><p>https://new.org</p>';
    for (final html in [null, replyHtml]) {
      expect(_event(room, body, html: html).sharedLinks, [
        (url: 'https://new.org', name: 'https://new.org'),
      ]);
    }
  });

  test('ignores non-web targets, redactions and non-message events', () {
    final room = _Room();
    expect(
      _event(
        room,
        'Targets',
        html:
            '<a href="javascript:alert(1)">Script</a>'
            '<a href="mailto:alice@example.org">Mail</a>'
            '<a href="mxc://example.org/file">Attachment</a>'
            '<a href="/relative">Relative</a>'
            '<a href="https:///">Invalid</a>',
      ).sharedLinks,
      isEmpty,
    );
    final redacted = _event(room, 'https://removed.org');
    redacted.setRedactionEvent(_event(room, '', type: EventTypes.Redaction));
    expect(redacted.sharedLinks, isEmpty);
    expect(
      _event(
        room,
        'https://encrypted.org',
        type: EventTypes.Encrypted,
      ).sharedLinks,
      isEmpty,
    );
  });

  testWidgets(
    'Links loads matching messages, paginates and jumps to a message',
    (tester) async {
      final room = _Room();
      final first = _event(room, 'https://first.org', id: r'$first');
      final second = _event(room, 'https://second.org', id: r'$second');
      room.pages.addAll([
        [first, _event(room, 'No links')],
        [first, second],
      ]);
      final matrix = await _mountSearch(tester, room);
      await tester.tap(find.widgetWithText(Tab, 'Links'));
      await tester.pumpAndSettle();
      expect(room.batches, [null]);
      expect(find.text('https://first.org'), findsOneWidget);
      expect(find.textContaining('Alice |'), findsOneWidget);
      expect(find.text('No links'), findsNothing);
      await tester.tap(find.text('Search more...'));
      await tester.pumpAndSettle();
      expect(room.batches, [null, 'older']);
      expect(find.text('https://first.org'), findsOneWidget);
      expect(find.text('https://second.org'), findsOneWidget);
      expect(find.text('No more results found'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.chevron_right_outlined).first);
      expect(matrix.openedRoom, room.id);
      expect(matrix.openedEvent, r'$first');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a formatted link shows its destination before opening it', (
    tester,
  ) async {
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    final launched = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'launch') {
        launched.add((call.arguments as Map)['url'] as String);
      }
      return true;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final room = _Room();
    room.pages.add([
      _event(
        room,
        '[Read this](https://example.org)',
        html: '<a href="https://example.org">Read this</a>',
      ),
    ]);
    await _mountSearch(tester, room);
    await tester.tap(find.widgetWithText(Tab, 'Links'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Read this'));
    await tester.pumpAndSettle();
    expect(launched, isEmpty);
    expect(find.text('https://example.org'), findsOneWidget);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(launched, ['https://example.org']);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('Links fits a phone viewport in ${brightness.name} mode', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final room = _Room();
      final url = 'https://example.org/${'long-path/' * 10}';
      room.pages.add([
        _event(
          room,
          'Two links',
          html:
              '<a href="$url">A very long custom link label that needs truncating</a>'
              '<a href="https://second.org">Second link</a>',
        ),
        _event(room, url, id: r'$another-message'),
      ]);
      await _mountSearch(tester, room, brightness: brightness);
      await tester.tap(find.widgetWithText(Tab, 'Links'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.link_outlined), findsNWidgets(3));
      expect(find.text('Second link'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final dispose in [false, true]) {
    testWidgets(
      dispose
          ? 'a pending link search is safe after disposal'
          : 'returning to Messages invalidates a pending link search',
      (tester) async {
        final room = _Room();
        final pending = room.pending = Completer();
        await _mountSearch(tester, room);
        await tester.tap(find.widgetWithText(Tab, 'Links'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();
        expect(room.batches, [null]);
        final controller = tester.state<ChatSearchController>(
          find.byType(ChatSearchPage),
        );
        await controller.startSearch();
        expect(room.batches, [
          null,
        ], reason: 'Only one request may be in flight');
        if (dispose) {
          await tester.pumpWidget(const SizedBox());
        } else {
          await tester.tap(find.widgetWithText(Tab, 'Messages'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pump();
        }
        pending.complete((
          events: [_event(room, 'https://stale.org')],
          nextBatch: null,
          searchedUntil: DateTime(2026, 9, 1),
        ));
        await tester.pumpAndSettle();
        expect(controller.links, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
