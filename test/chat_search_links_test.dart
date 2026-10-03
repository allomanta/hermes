// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/l10n/l10n.dart';
import 'package:hermes/pages/chat/events/video_player.dart';
import 'package:hermes/pages/chat_search/chat_search_history.dart';
import 'package:hermes/pages/chat_search/chat_search_images_tab.dart';
import 'package:hermes/pages/chat_search/chat_search_links_tab.dart';
import 'package:hermes/pages/chat_search/chat_search_page.dart';
import 'package:hermes/utils/matrix_sdk_extensions/event_links_extension.dart';
import 'package:hermes/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:provider/provider.dart';

class _Client extends Fake implements Client {
  late _Room room;
  @override
  Room? getRoomById(String id) => room.id == id ? room : null;
  @override
  bool get formatLocalpart => false;
  @override
  bool get mxidLocalPartFallback => true;
  @override
  final _Database database = _Database();
  @override
  Encryption? encryption;
  @override
  final onTimelineEvent = CachedStreamController<Event>();
  @override
  final onHistoryEvent = CachedStreamController<Event>();
  @override
  Future<GetRoomEventsResponse> getRoomEvents(
    String roomId,
    Direction dir, {
    String? from,
    String? to,
    int? limit,
    String? filter,
  }) async {
    final result = await room.searchEvents(
      nextBatch: from == 'start' ? null : from,
      searchFunc: (_) => true,
    );
    return GetRoomEventsResponse.fromJson({
      'start': from,
      if (result.nextBatch != null) 'end': result.nextBatch,
      'chunk': result.events.map((event) => event.toJson()).toList(),
    });
  }
}

class _Database extends Fake implements DatabaseApi {
  int reads = 0;
  Completer<List<Event>>? pending;
  @override
  Future<List<Event>> getEventList(
    Room room, {
    int start = 0,
    bool onlySending = false,
    int? limit,
  }) async {
    reads++;
    if (pending != null) return pending!.future;
    return start == 0 ? (room as _Room).localEvents : [];
  }
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
  // ignore: non_constant_identifier_names
  String? prev_batch = 'start';
  final localEvents = <Event>[];
  @override
  String getLocalizedDisplayname([
    MatrixLocalizations i18n = const MatrixDefaultLocalizations(),
  ]) => 'Chat';
  @override
  User unsafeGetUserFromMemoryOrFallback(String id) =>
      User(id, room: this, displayName: 'Alice');

  final batches = <String?>[];
  final queries = <String?>[];
  final cursors = <String?, String?>{};
  bool fail = false;
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
    queries.add(searchTerm);
    if (fail) throw StateError('Search failed');
    if (pending != null) return pending!.future;
    final page = nextBatch == null
        ? 0
        : nextBatch == 'older'
        ? 1
        : int.parse(nextBatch);
    return (
      events: pages[page].where(searchFunc!).toList(),
      nextBatch: cursors.containsKey(nextBatch)
          ? cursors[nextBatch]
          : page + 1 < pages.length
          ? (page == 0 ? 'older' : '${page + 1}')
          : null,
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

class _Encryption extends Fake implements Encryption {
  final pending = Completer<Event>();
  int calls = 0;
  @override
  Future<Event> decryptRoomEvent(
    Event event, {
    bool store = false,
    EventUpdateType updateType = EventUpdateType.timeline,
  }) {
    calls++;
    return pending.future;
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
        [
          first,
          for (var i = 0; i < 19; i++)
            _event(room, 'https://filler$i.org', id: 'filler$i'),
          _event(room, 'No links'),
        ],
        [first, second],
      ]);
      final matrix = await _mountSearch(tester, room);
      await tester.tap(find.widgetWithText(Tab, 'Links'));
      await tester.pumpAndSettle();
      expect(room.batches, [null]);
      expect(find.text('https://first.org'), findsOneWidget);
      expect(find.textContaining('Alice |'), findsWidgets);
      expect(find.text('No links'), findsNothing);
      final scrollable = find.descendant(
        of: find.byType(ChatSearchLinksTab),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('Search more...'),
        500,
        scrollable: scrollable,
      );
      await tester.tap(find.text('Search more...'));
      await tester.pumpAndSettle();
      expect(room.batches, [null, 'older']);
      final controller = tester.state<ChatSearchController>(
        find.byType(ChatSearchPage),
      );
      expect(
        controller.links.where((event) => event.eventId == r'$first'),
        hasLength(1),
      );
      expect(find.text('https://second.org'), findsOneWidget);
      expect(find.text('No more results found'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('https://first.org'),
        -500,
        scrollable: scrollable,
      );
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
          : 'returning to Messages preserves a pending link search',
      (tester) async {
        final room = _Room();
        final pending = room.pending = Completer();
        await _mountSearch(tester, room);
        await tester.tap(find.widgetWithText(Tab, 'Links'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1));
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
        expect(controller.links, dispose ? isEmpty : hasLength(1));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'tab changes preserve results and do not restart completed searches',
    (tester) async {
      final room = _Room();
      room.pages.add([_event(room, 'https://kept.org')]);
      await _mountSearch(tester, room);
      await tester.tap(find.widgetWithText(Tab, 'Links'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(Tab, 'Messages'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(Tab, 'Links'));
      await tester.pumpAndSettle();
      expect(room.batches, [null]);
      expect(find.text('https://kept.org'), findsOneWidget);
    },
  );

  testWidgets('pagination uses the submitted query, not unsent field edits', (
    tester,
  ) async {
    final room = _Room();
    room.pages.addAll([
      [
        _event(room, 'First match', id: r'$first'),
        for (var i = 0; i < 19; i++)
          _event(room, 'First filler $i', id: 'filler$i'),
      ],
      [
        _event(room, 'First older', id: r'$older'),
        _event(room, 'Second match'),
      ],
    ]);
    await _mountSearch(tester, room);
    final controller = tester.state<ChatSearchController>(
      find.byType(ChatSearchPage),
    );
    controller.searchController.text = 'first';
    controller.restartSearch();
    await tester.pumpAndSettle();
    controller.searchController.text = 'second';
    await controller.startSearch();
    await tester.pumpAndSettle();
    expect(controller.searchQuery, 'first');
    expect(
      controller.messages.map((event) => event.body),
      contains('First older'),
    );
    expect(
      controller.messages.map((event) => event.body),
      isNot(contains('Second match')),
    );
  });

  testWidgets('failed searches release loading and can be retried', (
    tester,
  ) async {
    final room = _Room()..fail = true;
    await _mountSearch(tester, room);
    final controller = tester.state<ChatSearchController>(
      find.byType(ChatSearchPage),
    );
    controller.searchController.text = 'match';
    controller.restartSearch();
    await tester.pumpAndSettle();
    expect(controller.searches[0].isLoading, isFalse);
    expect(find.text('Try again'), findsOneWidget);
    room.fail = false;
    // The failed call did not consume a history page.
    room.pages.add([_event(room, 'Retry match')]);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Retry match'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cached results appear while remote history is pending', (
    tester,
  ) async {
    final room = _Room();
    room.localEvents.add(_event(room, 'Local match'));
    final pending = room.pending = Completer();
    await _mountSearch(tester, room);
    final controller = tester.state<ChatSearchController>(
      find.byType(ChatSearchPage),
    );
    controller.searchController.text = 'match';
    controller.restartSearch();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.text('Local match'), findsOneWidget);
    expect(controller.searches[0].isLoading, isTrue);
    await tester.pumpWidget(const SizedBox());
    pending.complete((events: <Event>[], nextBatch: null, searchedUntil: null));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'typing debounces and clearing cancels a scheduled message search',
    (tester) async {
      final room = _Room()..pages.add([]);
      await _mountSearch(tester, room);
      final field = find.byType(TextField);
      await tester.enterText(field, 'first');
      await tester.pump(const Duration(milliseconds: 299));
      expect(room.batches, isEmpty);
      await tester.enterText(field, '');
      await tester.pump(const Duration(milliseconds: 400));
      expect(room.batches, isEmpty);
      await tester.enterText(field, 'latest');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(room.batches, [null]);
    },
  );

  testWidgets(
    'empty history batches continue, stop at the page budget, and resume',
    (tester) async {
      final room = _Room();
      room.pages.addAll([
        for (var i = 0; i < 7; i++) <Event>[],
        [_event(room, 'https://late.org')],
      ]);
      await _mountSearch(tester, room);
      final controller = tester.state<ChatSearchController>(
        find.byType(ChatSearchPage),
      );
      final first = controller.startSearch(3);
      await tester.pumpAndSettle();
      await first;
      expect(room.batches.length, ChatSearchController.maxRemotePages);
      expect(controller.searches[3].isLoading, isFalse);
      expect(controller.searches[3].endReached, isFalse);
      final more = controller.startSearch(3);
      await tester.pumpAndSettle();
      await more;
      expect(controller.links.single.body, 'https://late.org');
      expect(controller.searches[3].endReached, isTrue);
    },
  );

  for (final cycle in [false, true]) {
    testWidgets(
      cycle
          ? 'cycling cursors stop with retry'
          : 'repeated cursors stop with retry',
      (tester) async {
        final room = _Room()..pages.addAll([[], []]);
        room.cursors[cycle ? 'older' : null] = 'start';
        await _mountSearch(tester, room);
        final controller = tester.state<ChatSearchController>(
          find.byType(ChatSearchPage),
        );
        final search = controller.startSearch(3);
        await tester.pumpAndSettle();
        await search;
        expect(room.batches.length, cycle ? 2 : 1);
        expect(controller.searches[3].hasError, isTrue);
        expect(controller.searches[3].isLoading, isFalse);
        expect(controller.searches[3].endReached, isFalse);
        room.cursors[cycle ? 'older' : null] = null;
        final retry = controller.startSearch(3);
        await tester.pumpAndSettle();
        await retry;
        expect(room.batches.length, cycle ? 3 : 2);
        expect(controller.searches[3].hasError, isFalse);
        expect(controller.searches[3].endReached, isTrue);
      },
    );
  }

  testWidgets(
    'cancel releases the UI immediately and ignores a late response',
    (tester) async {
      final room = _Room();
      final pending = room.pending = Completer();
      await _mountSearch(tester, room);
      await tester.tap(find.widgetWithText(Tab, 'Links'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      final controller = tester.state<ChatSearchController>(
        find.byType(ChatSearchPage),
      );
      expect(controller.searches[3].isLoading, isTrue);
      expect(room.batches, [null]);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(controller.searches[3].isLoading, isFalse);
      pending.complete((
        events: [_event(room, 'https://cancelled.org')],
        nextBatch: null,
        searchedUntil: null,
      ));
      await tester.pumpAndSettle();
      expect(controller.links, isEmpty);
      expect(find.text('Search more...'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a hung server request times out and ignores its late response', (
    tester,
  ) async {
    final room = _Room();
    final pending = room.pending = Completer();
    await _mountSearch(tester, room);
    final controller = tester.state<ChatSearchController>(
      find.byType(ChatSearchPage),
    );
    final search = controller.startSearch(3);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(
      ChatSearchHistory.requestTimeout + const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();
    await search;
    expect(controller.searches[3].hasError, isTrue);
    expect(controller.searches[3].isLoading, isFalse);
    pending.complete((
      events: [_event(room, 'https://late.org')],
      nextBatch: null,
      searchedUntil: null,
    ));
    await tester.pumpAndSettle();
    expect(controller.links, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the overall deadline releases a hung local database read', (
    tester,
  ) async {
    final room = _Room();
    final pending = room.client.database.pending = Completer<List<Event>>();
    await _mountSearch(tester, room);
    final controller = tester.state<ChatSearchController>(
      find.byType(ChatSearchPage),
    );
    final search = controller.startSearch(3);
    await tester.pump(
      ChatSearchController.maxSearchDuration + const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();
    await search;
    expect(controller.searches[3].hasError, isTrue);
    expect(controller.searches[3].isLoading, isFalse);
    expect(room.batches, isEmpty);
    pending.complete([_event(room, 'https://late.org')]);
    await tester.pumpAndSettle();
    expect(controller.links, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hung decryption times out without advancing the cursor', (
    tester,
  ) async {
    final room = _Room();
    final encryption = room.client.encryption = _Encryption();
    room.pages.add([_event(room, '', type: EventTypes.Encrypted)]);
    await _mountSearch(tester, room);
    final controller = tester.state<ChatSearchController>(
      find.byType(ChatSearchPage),
    );
    final search = controller.startSearch(3);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(
      ChatSearchHistory.decryptionTimeout + const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();
    await search;
    expect(controller.searches[3].hasError, isTrue);
    expect(controller.searches[3].isLoading, isFalse);
    expect(controller.searches[3].nextBatch, 'start');
    encryption.pending.complete(_event(room, 'https://late.org'));
    await tester.pumpAndSettle();
    expect(controller.links, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'cached local and remote history are reused across tabs and queries',
    (tester) async {
      final room = _Room();
      room.localEvents.addAll([
        _event(room, 'Local alpha', id: 'a'),
        _event(room, 'Local beta', id: 'b'),
      ]);
      room.pages.add([
        _event(room, 'Remote alpha', id: 'ra'),
        _event(room, 'Remote beta', id: 'rb'),
        _event(room, 'https://link.org', id: 'link'),
      ]);
      await _mountSearch(tester, room);
      final controller = tester.state<ChatSearchController>(
        find.byType(ChatSearchPage),
      );
      controller.searchController.text = 'alpha';
      controller.restartSearch();
      await tester.pumpAndSettle();
      final reads = room.client.database.reads;
      controller.searchController.text = 'beta';
      controller.restartSearch();
      await tester.pumpAndSettle();
      final links = controller.startSearch(3);
      await tester.pumpAndSettle();
      await links;
      expect(room.client.database.reads, reads);
      expect(room.batches, [null]);
      expect(controller.messages.map((event) => event.body), [
        'Local beta',
        'Remote beta',
      ]);
      expect(controller.links.single.body, 'https://link.org');
    },
  );

  testWidgets(
    'a new query ignores stale results while reusing the pending history request',
    (tester) async {
      final room = _Room();
      final pending = room.pending = Completer();
      await _mountSearch(tester, room);
      final controller = tester.state<ChatSearchController>(
        find.byType(ChatSearchPage),
      );
      controller.searchController.text = 'alpha';
      controller.restartSearch();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 1));
      controller.searchController.text = 'beta';
      controller.restartSearch();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 1));
      expect(room.batches, [null]);
      pending.complete((
        events: [
          _event(room, 'Alpha match', id: 'alpha'),
          _event(room, 'Beta match', id: 'beta'),
        ],
        nextBatch: null,
        searchedUntil: null,
      ));
      await tester.pumpAndSettle();
      expect(controller.messages.single.body, 'Beta match');
      expect(controller.searches[0].isLoading, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the history cache evicts old pages while retaining recently used pages',
    (tester) async {
      final room = _Room();
      final history = ChatSearchHistory(room);
      addTearDown(history.dispose);
      for (var i = 0; i < ChatSearchHistory.maxCachedPages; i++) {
        await history.loadLocal(i * ChatSearchHistory.localBatchSize);
      }
      await history.loadLocal(0);
      await history.loadLocal(
        ChatSearchHistory.maxCachedPages * ChatSearchHistory.localBatchSize,
      );
      final reads = room.client.database.reads;
      await history.loadLocal(0);
      expect(room.client.database.reads, reads);
      await history.loadLocal(ChatSearchHistory.localBatchSize);
      expect(room.client.database.reads, reads + 1);
    },
  );

  testWidgets(
    'concurrent tabs share a pending fetch and can cancel independently',
    (tester) async {
      final room = _Room();
      final pending = room.pending = Completer();
      await _mountSearch(tester, room);
      final controller = tester.state<ChatSearchController>(
        find.byType(ChatSearchPage),
      );
      final links = controller.startSearch(3);
      final files = controller.startSearch(2);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 1));
      expect(room.batches, [null]);
      controller.stopSearch(3);
      final file = _event(room, 'report.txt')
        ..content['msgtype'] = MessageTypes.File;
      pending.complete((events: [file], nextBatch: null, searchedUntil: null));
      await tester.pumpAndSettle();
      await Future.wait([links, files]);
      expect(controller.links, isEmpty);
      expect(controller.files.single.body, 'report.txt');
      expect(controller.searches[2].isLoading, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'new room events refresh local cache and redactions refresh remote cache',
    (tester) async {
      final room = _Room();
      final history = ChatSearchHistory(room);
      addTearDown(history.dispose);
      room.localEvents.add(_event(room, 'Old body'));
      room.pages.add([_event(room, 'https://old.org')]);
      await history.loadLocal(0);
      await history.loadRemote('start');
      room.localEvents[0] = _event(room, 'New body');
      room.client.onTimelineEvent.add(room.localEvents[0]);
      await tester.pump();
      expect((await history.loadLocal(0)).single.body, 'New body');
      expect(room.client.database.reads, 2);
      room.pages[0] = [_event(room, 'Removed')];
      room.client.onTimelineEvent.add(
        _event(room, '', type: EventTypes.Redaction),
      );
      await tester.pump();
      expect((await history.loadRemote('start')).events.single.body, 'Removed');
      expect(room.batches, [null, null]);
    },
  );

  testWidgets(
    'unreadable encrypted pages are retried and successful decryption is cached',
    (tester) async {
      final room = _Room();
      room.pages.add([_event(room, '', type: EventTypes.Encrypted)]);
      final history = ChatSearchHistory(room);
      addTearDown(history.dispose);
      expect((await history.loadRemote('start')).hasUndecryptedEvents, isTrue);
      final encryption = room.client.encryption = _Encryption();
      encryption.pending.complete(_event(room, 'https://decrypted.org'));
      final decoded = await history.loadRemote('start');
      expect(decoded.events.single.body, 'https://decrypted.org');
      expect(decoded.hasUndecryptedEvents, isFalse);
      expect(identical(await history.loadRemote('start'), decoded), isTrue);
      expect(encryption.calls, 1);
      expect(room.batches, [null, null]);
    },
  );

  testWidgets('changing accounts clears search results and history cache', (
    tester,
  ) async {
    final oldRoom = _Room()..prev_batch = null;
    oldRoom.localEvents.add(_event(oldRoom, 'Old account match'));
    await _mountSearch(tester, oldRoom);
    final controller = tester.state<ChatSearchController>(
      find.byType(ChatSearchPage),
    );
    controller.searchController.text = 'match';
    controller.restartSearch();
    await tester.pumpAndSettle();
    final newRoom = _Room()..prev_batch = null;
    newRoom.localEvents.add(_event(newRoom, 'New account match'));
    await _mountSearch(tester, newRoom);
    expect(controller.messages.single.body, 'New account match');
    expect(
      identical(controller.messages.single.room.client, newRoom.client),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'a large gallery builds visible video cells lazily in ${brightness.name}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final room = _Room();
        final events = [
          for (var i = 0; i < 200; i++)
            _event(room, 'Clip $i', id: '$i')
              ..content['msgtype'] = MessageTypes.Video
              ..content['info'] = {'w': 1920, 'h': 1080},
        ];
        final matrix = _Matrix(room.client);
        await tester.pumpWidget(
          Provider<MatrixState>.value(
            value: matrix,
            child: MaterialApp(
              theme: ThemeData(brightness: brightness),
              localizationsDelegates: L10n.localizationsDelegates,
              supportedLocales: L10n.supportedLocales,
              home: Scaffold(
                body: ChatSearchImagesTab(
                  room: room,
                  events: events,
                  onStartSearch: () {},
                  endReached: true,
                  isLoading: false,
                  searchedUntil: null,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(GridView), findsNothing);
        expect(
          tester
              .widget<SliverGrid>(find.byType(SliverGrid))
              .delegate
              .estimatedChildCount,
          200,
        );
        expect(find.byType(EventVideoPlayer).evaluate().length, lessThan(30));
        expect(find.byType(EventVideoPlayer), findsWidgets);
        await tester.tap(find.byIcon(Icons.chevron_right_outlined).first);
        expect(matrix.openedEvent, '0');
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
        await tester.pumpAndSettle();
        expect(find.byType(EventVideoPlayer).evaluate().length, lessThan(30));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
