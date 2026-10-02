// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/l10n/l10n.dart';
import 'package:hermes/pages/chat/events/message_timestamp.dart';
import 'package:hermes/pages/chat/read_receipts_dialog.dart';
import 'package:hermes/utils/date_time_extension.dart';
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
  User unsafeGetUserFromMemoryOrFallback(String id) => User(id, room: this);
}

class _Timeline extends Fake implements Timeline {
  _Timeline(this.room, this.events);
  @override
  final Room room;
  @override
  final List<Event> events;
}

void main() {
  for (final detailed in [false, true]) {
    testWidgets(
      'timestamp opens read details without the message menu ($detailed)',
      (tester) async {
        final room = _Room();
        addTearDown(room.client.onSync.close);
        final event = Event(
          room: room,
          eventId: r'$target',
          senderId: room.client.userID!,
          originServerTs: DateTime(2026, 10, 1, 12, 34, 56),
          type: EventTypes.Message,
          content: {'msgtype': MessageTypes.Text, 'body': 'Message'},
        );
        room.receiptState.global.otherUsers['@alice:example.org'] =
            LatestReceiptStateData(
              event.eventId,
              event.originServerTs.millisecondsSinceEpoch + 1000,
            );
        var menus = 0;
        late BuildContext timestampContext;
        const shadows = [Shadow(color: Colors.black, blurRadius: 2)];
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: Scaffold(
              body: Stack(
                children: [
                  Positioned.fill(child: InkWell(onTap: () => menus++)),
                  Align(
                    alignment: Alignment.topLeft,
                    child: Builder(
                      builder: (context) {
                        timestampContext = context;
                        return MessageTimestamp(
                          event: event,
                          timeline: _Timeline(room, [event]),
                          detailed: detailed,
                          color: Colors.purple,
                          shadows: shadows,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final timestamp = tester.widget<Text>(
          find.descendant(
            of: find.byType(MessageTimestamp),
            matching: find.byType(Text),
          ),
        );
        expect(
          timestamp.data,
          ' ${detailed ? event.originServerTs.localizedDetailedTime(timestampContext) : event.originServerTs.localizedTimeOfDay(timestampContext)}',
        );
        expect(timestamp.style!.fontSize, 11);
        expect(timestamp.style!.color, Colors.purple);
        expect(timestamp.style!.shadows, shadows);
        await tester.tap(find.byType(MessageTimestamp));
        await tester.pumpAndSettle();
        expect(find.byType(ReadReceiptsDialog), findsOneWidget);
        expect(find.text('alice'), findsOneWidget);
        expect(menus, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
