// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/pages/chat/chat.dart';
import 'package:hermes/utils/android_share_shortcuts.dart';
import 'package:hermes/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:hermes/widgets/share_scaffold_dialog.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Locals extends Fake implements MatrixLocals {}

class _Database extends Fake implements DatabaseApi {
  int reads = 0;
  bool fail = false;
  Completer<Uint8List>? pending;
  final started = Completer<void>();

  @override
  Future<Uint8List?> getFile(Uri uri) async {
    reads++;
    if (!started.isCompleted) started.complete();
    if (fail) throw StateError('Temporary download failure');
    return pending?.future ?? Uint8List.fromList([reads]);
  }
}

class _Client extends Fake implements Client {
  _Client(this.clientName);
  @override
  final String clientName;
  @override
  final _Database database = _Database();
  @override
  final homeserver = Uri.parse('https://example.org');
  @override
  final rooms = <Room>[];
  @override
  Future<void>? roomsLoading;
  bool loggedIn = true;
  @override
  bool isLogged() => loggedIn;
}

class _Room extends Fake implements Room {
  _Room(this.client, this.id) {
    client.rooms.add(this);
  }
  @override
  final _Client client;
  @override
  final String id;
  @override
  Uri? avatar;
  @override
  bool get encrypted => false;
  final sent = <Object?>[];
  Future<String?> sendResult = Future.value(r'$event');
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #sendTextEvent ||
        invocation.memberName == #sendEvent) {
      sent.add(invocation.positionalArguments.first);
      return sendResult;
    }
    return super.noSuchMethod(invocation);
  }

  @override
  Membership membership = Membership.join;
  @override
  bool isSpace = false;
  @override
  bool canSendDefaultMessages = true;
  @override
  String getLocalizedDisplayname([
    MatrixLocalizations i18n = const MatrixDefaultLocalizations(),
  ]) => id;
}

// Exercise share handling without starting chat synchronization.
class _ShareController extends ChatController {
  @override
  Room get room => sendingRoom ?? widget.room;
  Room? sendingRoom;
  @override
  late ChatPageWithRoom widget;
  @override
  late BuildContext context;
  @override
  bool get mounted => context.mounted;
}

String _id(Room room) =>
    'hermes-share:${jsonEncode([room.client.clientName, room.id])}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('im.hermes.hermes/direct_share_shortcuts');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final locals = _Locals();
  final calls = <MethodCall>[];
  var publishSucceeds = true;
  String? pendingId;

  List<Map<dynamic, dynamic>> published() =>
      (calls
                  .lastWhere((call) => call.method == 'publishShareShortcuts')
                  .arguments
              as List)
          .cast<Map<dynamic, dynamic>>();

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    publishSucceeds = true;
    pendingId = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'publishShareShortcuts') return publishSucceeds;
      if (call.method == 'takePendingShortcut') return pendingId;
      return null;
    });
    await AndroidShareShortcuts.clear();
    calls.clear();
    debugDefaultTargetPlatformOverride = null;
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await AndroidShareShortcuts.clear();
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  for (final success in [true, false]) {
    testWidgets(
      'an open chat handles a new share and records only success ($success)',
      (tester) async {
        final client = _Client('account');
        final room = _Room(client, '!room:example.org');
        final sent = Completer<String?>();
        room.sendResult = sent.future;
        await AndroidShareShortcuts.schedulePublish([client], locals);
        calls.clear();
        final controller = _ShareController()
          ..widget = ChatPageWithRoom(room: room)
          ..sendingRoom = _Room(_Client('other account'), room.id);
        addTearDown(controller.scrollController.dispose);
        addTearDown(controller.sendController.dispose);
        await tester.pumpWidget(
          Builder(
            builder: (context) {
              controller.context = context;
              return const SizedBox();
            },
          ),
        );
        final oldWidget = controller.widget;
        controller.widget = ChatPageWithRoom(
          room: room,
          shareItems: [
            TextShareItem('shared text'),
            ContentShareItem({'body': 'forwarded message'}),
          ],
        );
        controller.didUpdateWidget(oldWidget);
        tester.binding.scheduleFrame();
        await tester.pump();
        expect(room.sent, [
          'shared text',
          {'body': 'forwarded message'},
        ]);
        expect(calls, isEmpty, reason: 'Sending has not succeeded yet');
        sent.complete(success ? r'$event' : null);
        await tester.pumpAndSettle();
        if (success) {
          expect(published().single['id'], _id(room));
        } else {
          expect(calls, isEmpty);
        }
        controller.didUpdateWidget(controller.widget);
        await tester.pump();
        expect(
          room.sent,
          hasLength(2),
          reason: 'Unrelated rebuilds must not resend shares',
        );
        final recreatedController = _ShareController()
          ..widget = ChatPageWithRoom(
            room: room,
            shareItems: controller.widget.shareItems,
          )
          ..sendingRoom = room
          ..context = controller.context;
        addTearDown(recreatedController.scrollController.dispose);
        addTearDown(recreatedController.sendController.dispose);
        recreatedController.didUpdateWidget(ChatPageWithRoom(room: room));
        tester.binding.scheduleFrame();
        await tester.pump();
        expect(
          room.sent,
          hasLength(2),
          reason: 'A remount must not resend a share',
        );
        final previous = controller.widget;
        controller.widget = ChatPageWithRoom(
          room: room,
          shareItems: [TextShareItem('next share')],
        );
        controller.didUpdateWidget(previous);
        tester.binding.scheduleFrame();
        await tester.pumpAndSettle();
        expect(room.sent.last, 'next share');
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }

  group('publisher', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
    test(
      'supplies only the five most recently shared chats across accounts',
      () async {
        final first = _Client('first');
        final second = _Client('second');
        final rooms = List.generate(
          7,
          (i) => _Room(i.isEven ? first : second, '!$i:example.org'),
        );
        await AndroidShareShortcuts.schedulePublish([first, second], locals);
        expect(published(), isEmpty);
        for (final room in rooms) {
          await AndroidShareShortcuts.recordShare(room);
        }
        expect(
          published().map((s) => s['id']),
          rooms.reversed.take(5).map(_id),
        );
        await AndroidShareShortcuts.recordShare(rooms[3]);
        expect(
          published().map((s) => s['id']),
          [3, 6, 5, 4, 2].map((i) => _id(rooms[i])),
        );
        final usages = calls
            .where((call) => call.method == 'reportShareShortcutUsed')
            .length;
        calls.clear();
        await AndroidShareShortcuts.schedulePublish([second, first], locals);
        expect(
          calls,
          isEmpty,
          reason: 'Account switching and sync are not share activity',
        );
        expect(usages, 8);
      },
    );

    test(
      'restores saved order and republishes an empty selection after leaving',
      () async {
        final client = _Client('account');
        final room = _Room(client, '!room:example.org');
        await AndroidShareShortcuts.schedulePublish([client], locals);
        await AndroidShareShortcuts.recordShare(room);
        await AndroidShareShortcuts.clear();
        await AndroidShareShortcuts.schedulePublish([client], locals);
        expect(published().single['id'], _id(room));
        room.membership = Membership.leave;
        await AndroidShareShortcuts.schedulePublish([client], locals);
        expect(published(), isEmpty);
      },
    );

    test(
      'same room in two accounts has separate IDs; logout removes only its history',
      () async {
        final first = _Client('account one');
        final second = _Client('account two');
        final firstRoom = _Room(first, '!shared:example.org');
        final secondRoom = _Room(second, firstRoom.id);
        await AndroidShareShortcuts.schedulePublish([first, second], locals);
        await AndroidShareShortcuts.recordShare(firstRoom);
        await AndroidShareShortcuts.recordShare(secondRoom);
        expect(published().map((s) => s['id']).toSet(), {
          _id(firstRoom),
          _id(secondRoom),
        });
        pendingId = _id(firstRoom);
        expect(await AndroidShareShortcuts.takePendingShortcut(), (
          clientName: first.clientName,
          roomId: firstRoom.id,
        ));
        first.loggedIn = false;
        await AndroidShareShortcuts.clear(clientName: first.clientName);
        expect(published().map((s) => s['id']), [_id(secondRoom)]);
        await AndroidShareShortcuts.recordShare(firstRoom);
        first.loggedIn = true;
        await AndroidShareShortcuts.schedulePublish([first, second], locals);
        expect(published().map((s) => s['id']), [_id(secondRoom)]);
      },
    );

    test('rejects legacy room-only IDs and malformed destinations', () async {
      for (final id in [
        null,
        '!room:example.org',
        'hermes-share:invalid',
        'hermes-share:[1,2]',
        'hermes-share:["", "room"]',
      ]) {
        pendingId = id;
        expect(await AndroidShareShortcuts.takePendingShortcut(), isNull);
      }
    });

    test(
      'logout releases a publish waiting for rooms so another account can publish',
      () async {
        final client = _Client('account');
        final other = _Client('other');
        final loaded = Completer<void>();
        client.roomsLoading = loaded.future;
        final publish = AndroidShareShortcuts.schedulePublish([
          client,
          other,
        ], locals);
        client.loggedIn = false;
        await AndroidShareShortcuts.clear(clientName: client.clientName);
        await publish;
        expect(published(), isEmpty);
        loaded.complete();
        expect(
          calls.where((c) => c.method == 'publishShareShortcuts'),
          hasLength(1),
        );
      },
    );

    test(
      'clear invalidates an avatar download and cannot repopulate its cache',
      () async {
        final client = _Client('account');
        final room = _Room(client, '!room:example.org')
          ..avatar = Uri.parse('mxc://example.org/avatar');
        await AndroidShareShortcuts.schedulePublish([client], locals);
        client.database.pending = Completer<Uint8List>();
        final share = AndroidShareShortcuts.recordShare(room);
        await client.database.started.future;
        await AndroidShareShortcuts.clear();
        calls.clear();
        client.database.pending!.complete(Uint8List.fromList([1]));
        await share;
        expect(calls, isEmpty);
        await AndroidShareShortcuts.schedulePublish([client], locals);
        expect(client.database.reads, 2);
        expect(published().single['icon'], base64Encode([1]));
      },
    );

    test(
      'avatar failures retry; successful avatars are cached and bounded',
      () async {
        final client = _Client('account');
        final room = _Room(client, '!room:example.org')
          ..avatar = Uri.parse('mxc://example.org/0');
        await AndroidShareShortcuts.schedulePublish([client], locals);
        client.database.fail = true;
        await AndroidShareShortcuts.recordShare(room);
        expect(published().single['icon'], isNull);
        client.database.fail = false;
        await AndroidShareShortcuts.schedulePublish([client], locals);
        expect(published().single['icon'], isNotNull);
        await AndroidShareShortcuts.schedulePublish([client], locals);
        expect(client.database.reads, 2);
        for (var i = 1; i <= 5; i++) {
          room.avatar = Uri.parse('mxc://example.org/$i');
          await AndroidShareShortcuts.schedulePublish([client], locals);
        }
        room.avatar = Uri.parse('mxc://example.org/0');
        await AndroidShareShortcuts.schedulePublish([client], locals);
        expect(
          client.database.reads,
          8,
          reason: 'The oldest avatar should have been evicted',
        );
      },
    );

    test(
      'retries a rate-limited publish and reports only the actual shared target',
      () async {
        final client = _Client('account');
        final room = _Room(client, '!room:example.org');
        await AndroidShareShortcuts.schedulePublish([client], locals);
        calls.clear();
        publishSucceeds = false;
        await AndroidShareShortcuts.recordShare(room);
        expect(
          calls.where((c) => c.method == 'reportShareShortcutUsed'),
          isEmpty,
        );
        publishSucceeds = true;
        await AndroidShareShortcuts.schedulePublish([client], locals);
        expect(
          calls.where((c) => c.method == 'publishShareShortcuts'),
          hasLength(2),
        );
        expect(
          calls
              .where((c) => c.method == 'reportShareShortcutUsed')
              .single
              .arguments,
          _id(room),
        );
        calls.clear();
        await AndroidShareShortcuts.recordShare(room);
        expect(calls.single.method, 'reportShareShortcutUsed');
      },
    );
  });
}
