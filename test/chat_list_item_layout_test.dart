// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/l10n/l10n.dart';
import 'package:hermes/pages/chat/chat.dart';
import 'package:hermes/pages/chat/reply_display.dart';
import 'package:hermes/pages/chat_list/chat_list_item.dart';
import 'package:hermes/pages/chat_list/dummy_chat_list_item.dart';
import 'package:hermes/utils/date_time_extension.dart';
import 'package:hermes/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

class _Client extends Fake implements Client {
  @override
  String get userID => '@me:example.org';
}

class _Room extends Fake implements Room {
  @override
  final _Client client = _Client();
  @override
  final id = '!room:example.org';
  @override
  final name = 'A long chat name';
  @override
  Membership membership = Membership.join;
  @override
  PushRuleState pushRuleState = PushRuleState.dontNotify;
  @override
  bool isFavourite = true;
  @override
  bool get isSpace => false;
  @override
  bool get isUnread => true;
  @override
  bool get hasNewMessages => true;
  @override
  bool get markedUnread => false;
  @override
  int notificationCount = 42;
  @override
  int get highlightCount => 0;
  @override
  String? get directChatMatrixID => null;
  @override
  Uri? get avatar => null;
  @override
  List<User> get typingUsers => [];
  @override
  DateTime get latestEventReceivedTime => DateTime(2026, 10, 4, 12, 34);
  @override
  Event? lastEvent;
  @override
  String getLocalizedDisplayname([
    MatrixLocalizations i18n = const MatrixDefaultLocalizations(),
  ]) => name;
  @override
  StrippedStateEvent? getState(String typeKey, [String stateKey = '']) =>
      StrippedStateEvent(type: typeKey, content: {}, senderId: client.userID);
}

class _Matrix extends Fake with Diagnosticable implements MatrixState {
  _Matrix(this.client);
  @override
  final Client client;
}

class _Timeline extends Fake implements Timeline {
  @override
  final Map<String, Map<String, Set<Event>>> aggregatedEvents = {};
}

Future<void> _mountItem(
  WidgetTester tester,
  _Room room,
  ValueNotifier<double> width, {
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    Provider<MatrixState>.value(
      value: _Matrix(room.client),
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: [
          ...L10n.localizationsDelegates,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: ValueListenableBuilder(
              valueListenable: width,
              builder: (_, value, _) => SizedBox(
                width: value,
                child: ChatListItem(room, onTap: () {}),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final locale in [const Locale('en'), const Locale('fr')]) {
      for (final delegate in [
        ...L10n.localizationsDelegates,
        ...GlobalMaterialLocalizations.delegates,
      ]) {
        if (delegate.isSupported(locale)) await delegate.load(locale);
      }
    }
  });

  testWidgets('loading rows fit at the list collapse threshold', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 144,
              child: DummyChatListItem(opacity: 1, animate: false),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('long edit previews fit inside a narrow chat pane', (
    tester,
  ) async {
    final room = _Room();
    final controller = ChatController()
      ..timeline = _Timeline()
      ..editEvent = Event(
        room: room,
        eventId: r'$edit',
        senderId: '@me:example.org',
        originServerTs: DateTime.now(),
        content: {
          'msgtype': MessageTypes.Text,
          'body': 'A long edited message preview ' * 20,
        },
        type: EventTypes.Message,
      );
    addTearDown(controller.scrollController.dispose);
    addTearDown(controller.sendController.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 380, child: ReplyDisplay(controller)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a narrow row hides its timestamp before the name and badges', (
    tester,
  ) async {
    final room = _Room();
    final width = ValueNotifier(380.0);
    addTearDown(width.dispose);
    await _mountItem(tester, room, width);
    final context = tester.element(find.byType(ChatListItem));
    final timestamp = room.latestEventReceivedTime.localizedTimeShort(context);
    expect(find.text(timestamp), findsOneWidget);
    width.value = 220;
    await tester.pumpAndSettle();
    expect(find.text(timestamp), findsNothing);
    expect(find.text(room.name), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(tester.takeException(), isNull);
    width.value = 380;
    await tester.pumpAndSettle();
    expect(find.text(timestamp), findsOneWidget);
  });

  for (final locale in [const Locale('en'), const Locale('fr')]) {
    testWidgets('decorated threaded rows resize without overflow in $locale', (
      tester,
    ) async {
      final room = _Room();
      room.lastEvent = Event(
        room: room,
        eventId: r'$last',
        senderId: '@me:example.org',
        originServerTs: DateTime(2026),
        status: EventStatus.sending,
        content: {
          'msgtype': MessageTypes.Text,
          'body': 'A long threaded message preview',
          'm.relates_to': {
            'rel_type': RelationshipTypes.thread,
            'event_id': r'$thread',
          },
        },
        type: EventTypes.Message,
      );
      room.notificationCount = 9999;
      final width = ValueNotifier(380.0);
      addTearDown(width.dispose);
      await _mountItem(tester, room, width, locale: locale);
      for (final size in [300.0, 264.0, 240.0, 200.0, 170.0, 145.0, 144.0]) {
        width.value = size;
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'at width $size');
        await tester.pump(const Duration(milliseconds: 125));
        expect(tester.takeException(), isNull, reason: 'animating at $size');
        await tester.pump(const Duration(milliseconds: 125));
        expect(tester.takeException(), isNull, reason: 'settled at $size');
        expect(find.text('9999'), findsOneWidget);
        expect(tester.getRect(find.text('9999')).height, greaterThan(10));
        if (size == 264) {
          final context = tester.element(find.byType(ChatListItem));
          expect(
            find.text(room.latestEventReceivedTime.localizedTimeShort(context)),
            findsNothing,
          );
          expect(find.byIcon(Icons.message_outlined), findsOneWidget);
        } else if (size <= 240) {
          expect(find.byIcon(Icons.message_outlined), findsNothing);
        }
      }
    });
  }
}
