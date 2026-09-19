// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/l10n/l10n.dart';
import 'package:hermes/pages/chat/chat.dart';
import 'package:hermes/widgets/matrix.dart';
import 'package:hermes/widgets/share_scaffold_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

class _Client extends Fake implements Client {
  _Client(this.userID);
  @override
  final String userID;
  late _Room room;
  @override
  List<Room> get rooms => [];
  @override
  Room? getRoomById(String id) => id == room.id ? room : null;
}

class _Room extends Fake implements Room {
  _Room(this.client);
  @override
  final _Client client;
  @override
  String get id => '!room:example.org';
  @override
  Membership membership = Membership.join;
  @override
  final List<String> pinnedEventIds = [];
  final redacted = <String>[];
  List<String>? sentPins;
  bool allowPin = true;
  @override
  bool canChangeStateEvent(String type) => allowPin;
  @override
  Future<String> setPinnedEvents(List<String> ids) async {
    sentPins = ids;
    return r'$pins';
  }

  @override
  Future<String?> redactEvent(
    String eventId, {
    String? reason,
    String? txid,
    bool redactAllEdits = false,
  }) async {
    redacted.add(eventId);
    return r'$redaction';
  }
}

class _Event extends Event {
  _Event(
    Room room,
    String id,
    String sender, {
    super.status = EventStatus.sent,
    this.canRedact = false,
  }) : super(
         room: room,
         eventId: id,
         senderId: sender,
         type: EventTypes.Message,
         originServerTs: DateTime.now(),
         content: {
           'msgtype': MessageTypes.Text,
           'body': id,
           'info': {'label': 'original'},
         },
       );
  @override
  final bool canRedact;
  bool cancelled = false;
  @override
  Future<void> cancelSend() async => cancelled = true;
}

class _Timeline extends Fake implements Timeline {
  @override
  final Map<String, Map<String, Set<Event>>> aggregatedEvents = {};
}

class _Matrix extends Fake with Diagnosticable implements MatrixState {
  _Matrix(this.client);
  @override
  final Client client;
}

// Use real action/dialog implementations without starting chat synchronization.
class _Controller extends ChatController {
  _Controller(this.room, this.currentRoomBundle);
  @override
  final _Room room;
  @override
  String get roomId => room.id;
  @override
  final List<Client?> currentRoomBundle;
  late BuildContext actionContext;
  @override
  BuildContext get context => actionContext;
  @override
  bool get mounted => actionContext.mounted;
  @override
  void setState(VoidCallback fn) => fn();
}

Future<_Controller> _mountActions(WidgetTester tester) async {
  final first = _Client('@first:example.org');
  final second = _Client('@second:example.org');
  first.room = _Room(first);
  second.room = _Room(second);
  final controller = _Controller(first.room, [first, second])
    ..timeline = _Timeline();
  addTearDown(controller.scrollController.dispose);
  addTearDown(controller.sendController.dispose);
  await tester.pumpWidget(
    Provider<MatrixState>.value(
      value: _Matrix(first),
      child: MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Builder(
          builder: (context) {
            controller.actionContext = context;
            return const Scaffold();
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  testWidgets('single and selected copy use the same message bodies', (
    tester,
  ) async {
    final controller = await _mountActions(tester);
    final a = _Event(controller.room, 'first', '@first:example.org');
    final b = _Event(controller.room, 'second', '@first:example.org');
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    controller.selectedEvents = [b];
    controller.copyEventsAction([a]);
    controller.selectedEvents = [a, b];
    controller.copyEventsAction();
    await tester.pump();
    expect(copied, ['first', 'first\n\nsecond']);
  });

  testWidgets('single forwarding copies content without using the selection', (
    tester,
  ) async {
    final controller = await _mountActions(tester);
    final target = _Event(controller.room, 'target', '@first:example.org');
    controller.selectedEvents = [
      _Event(controller.room, 'other', '@first:example.org'),
    ];
    final pending = controller.forwardEventsAction([target]);
    await tester.pumpAndSettle();
    final dialog = tester.widget<ShareScaffoldDialog>(
      find.byType(ShareScaffoldDialog),
    );
    final shared = (dialog.items.single as ContentShareItem).value;
    expect(shared['body'], 'target');
    (shared['info'] as Map)['label'] = 'changed';
    expect((target.content['info'] as Map)['label'], 'original');
    Navigator.of(controller.context).pop();
    await tester.pumpAndSettle();
    await pending;
  });

  testWidgets('bulk deletion snapshots targets and uses each sender account', (
    tester,
  ) async {
    final controller = await _mountActions(tester);
    final a = _Event(controller.room, 'first', '@first:example.org');
    final b = _Event(controller.room, 'second', '@second:example.org');
    controller.selectedEvents = [a, b];
    final pending = controller.redactEventsAction();
    await tester.pumpAndSettle();
    controller.selectedEvents = [];
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await pending;
    expect(controller.room.redacted, ['first']);
    expect((controller.currentRoomBundle.last! as _Client).room.redacted, [
      'second',
    ]);
  });

  testWidgets(
    'single deletion works with no selection and cancel does nothing',
    (tester) async {
      final controller = await _mountActions(tester);
      final target = _Event(controller.room, 'target', '@second:example.org');
      final cancelled = controller.redactEventsAction([target]);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await cancelled;
      final targetRoom = (controller.currentRoomBundle.last! as _Client).room;
      expect(targetRoom.redacted, isEmpty);
      final pending = controller.redactEventsAction([target]);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      await pending;
      expect(targetRoom.redacted, ['target']);
    },
  );

  testWidgets('unsent messages are cancelled without a redaction prompt', (
    tester,
  ) async {
    final controller = await _mountActions(tester);
    final target = _Event(
      controller.room,
      'failed',
      '@first:example.org',
      status: EventStatus.error,
    );
    final pending = controller.redactEventsAction([target]);
    await tester.pump(const Duration(milliseconds: 400));
    await pending;
    expect(target.cancelled, isTrue);
    expect(controller.room.redacted, isEmpty);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets(
    'actions share permission checks and pinning does not mutate cached state',
    (tester) async {
      final controller = await _mountActions(tester);
      final own = _Event(controller.room, 'own', '@second:example.org');
      final foreign = _Event(controller.room, 'foreign', '@other:example.org');
      final moderated = _Event(
        controller.room,
        'moderated',
        '@other:example.org',
        canRedact: true,
      );
      expect(controller.canEditEvent(own), isTrue);
      expect(controller.canEditEvent(foreign), isFalse);
      expect(controller.canRedactEvent(moderated), isTrue);
      expect(controller.canRedactEvent(foreign), isFalse);
      controller.activeThreadId = 'thread';
      expect(controller.canPinEvent(own), isFalse);
      controller.activeThreadId = null;
      controller.room.allowPin = false;
      controller.pinEvent(own);
      expect(controller.room.sentPins, isNull);
      controller.room.allowPin = true;
      controller.room.pinnedEventIds.add('old');
      controller.pinEvent(own);
      await tester.pump(const Duration(milliseconds: 400));
      expect(controller.room.sentPins, ['old', 'own']);
      expect(controller.room.pinnedEventIds, ['old']);
      controller.room.membership = Membership.leave;
      expect(controller.canEditEvent(own), isFalse);
      expect(controller.canRedactEvent(own), isFalse);
      expect(controller.canPinEvent(own), isFalse);
    },
  );
}
