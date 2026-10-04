// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/config/setting_keys.dart';
import 'package:hermes/l10n/l10n.dart';
import 'package:hermes/pages/chat/chat.dart';
import 'package:hermes/pages/chat/chat_emoji_picker.dart';
import 'package:hermes/pages/chat/sticker_picker_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Client extends Fake implements Client {
  @override
  final Map<String, BasicEvent> accountData = {};
}

class _Room extends Fake implements Room {
  @override
  final id = '!room:example.org';
  @override
  final client = _Client();
  @override
  final Map<String, Map<String, StrippedStateEvent>> states = {};
  @override
  bool encrypted = false;
  Completer<List<User>>? participants;
  Completer<String?>? sendResult;
  Map<String, dynamic>? sent;
  String? sentType;

  @override
  Future<List<User>> requestParticipants([
    List<Membership> membershipFilter = const [
      Membership.join,
      Membership.invite,
      Membership.knock,
    ],
    bool suppressWarning = false,
    bool? cache,
    bool enforceFetchFromServer = false,
  ]) => participants!.future;

  @override
  Future<String?> sendEvent(
    Map<String, dynamic> content, {
    String type = EventTypes.Message,
    String? txid,
    Event? inReplyTo,
    String? editEventId,
    String? threadRootEventId,
    String? threadLastEventId,
    bool displayPendingEvent = true,
  }) async {
    // These SDK options would overwrite relations and rewrite the body.
    expectSync(inReplyTo, isNull);
    expectSync(threadRootEventId, isNull);
    expectSync(threadLastEventId, isNull);
    sent = content;
    sentType = type;
    return sendResult == null ? r'$sent' : await sendResult!.future;
  }
}

class _Controller extends ChatController {
  @override
  final _Room room = _Room();
  @override
  String? threadLastEventId;
  bool isMounted = true;
  @override
  bool get mounted => isMounted;
  int cancelledReplies = 0;

  @override
  void cancelReplyEventAction() {
    cancelledReplies++;
    replyEvent = null;
  }
}

final _sticker = ImagePackImageContent(
  url: Uri.parse('mxc://example.org/sticker'),
  body: 'Happy fox',
  info: {'mimetype': 'image/png', 'w': 128, 'h': 128},
);

Event _reply(Room room, [String id = r'$reply']) => Event(
  room: room,
  eventId: id,
  senderId: '@alice:example.org',
  originServerTs: DateTime(2026),
  type: EventTypes.Message,
  content: {'msgtype': MessageTypes.Text, 'body': 'Hello'},
);

Future<StickerPickerDialog> _mountPicker(
  WidgetTester tester,
  _Controller controller,
) async {
  controller.showEmojiPicker = true;
  controller.emojiPickerIndex = 1;
  addTearDown(controller.scrollController.dispose);
  addTearDown(controller.sendController.dispose);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(body: ChatEmojiPicker(controller)),
    ),
  );
  await tester.pumpAndSettle();
  return tester.widget<StickerPickerDialog>(find.byType(StickerPickerDialog));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
  });

  for (final (name, reply, threadId, lastId, relation) in [
    ('ordinary sticker', false, null, null, null),
    (
      'sticker reply',
      true,
      null,
      null,
      {
        'm.in_reply_to': {'event_id': r'$reply'},
      },
    ),
    (
      'sticker reply in a thread',
      true,
      r'$thread',
      r'$last',
      {
        'event_id': r'$thread',
        'rel_type': RelationshipTypes.thread,
        'is_falling_back': false,
        'm.in_reply_to': {'event_id': r'$reply'},
      },
    ),
    (
      'thread sticker with a fallback',
      false,
      r'$thread',
      r'$last',
      {
        'event_id': r'$thread',
        'rel_type': RelationshipTypes.thread,
        'is_falling_back': true,
        'm.in_reply_to': {'event_id': r'$last'},
      },
    ),
    (
      'thread sticker without a fallback',
      false,
      r'$thread',
      null,
      {
        'event_id': r'$thread',
        'rel_type': RelationshipTypes.thread,
        'is_falling_back': true,
      },
    ),
  ]) {
    testWidgets('$name preserves sticker content and reply metadata', (
      tester,
    ) async {
      final controller = _Controller()
        ..activeThreadId = threadId
        ..threadLastEventId = lastId;
      if (reply) controller.replyEvent = _reply(controller.room);
      final picker = await _mountPicker(tester, controller);
      picker.onSelected(_sticker);
      await tester.pump();
      expect(controller.room.sentType, EventTypes.Sticker);
      expect(controller.room.sent, {
        'body': 'Happy fox',
        'info': _sticker.info,
        'url': 'mxc://example.org/sticker',
        'm.relates_to': ?relation,
        if (reply)
          'm.mentions': {
            'user_ids': ['@alice:example.org'],
          },
      });
      final sent = Event(
        room: controller.room,
        eventId: r'$sent',
        senderId: '@me:example.org',
        originServerTs: DateTime(2026),
        type: EventTypes.Sticker,
        content: controller.room.sent!,
      );
      expect(
        sent.inReplyToEventId(includingFallback: false),
        reply ? r'$reply' : null,
      );
      expect(controller.replyEvent, isNull);
      expect(controller.cancelledReplies, reply ? 1 : 0);
    });
  }

  testWidgets('failed send preserves the reply selection', (tester) async {
    final controller = _Controller();
    final reply = controller.replyEvent = _reply(controller.room);
    controller.room.sendResult = Completer<String?>();
    final picker = await _mountPicker(tester, controller);
    picker.onSelected(_sticker);
    await tester.pump();
    expect(controller.replyEvent, same(reply));
    controller.room.sendResult!.complete(null);
    await tester.pump();
    expect(controller.replyEvent, same(reply));
    expect(controller.cancelledReplies, 0);
  });

  testWidgets('delayed send preserves a newer reply selection', (tester) async {
    final controller = _Controller();
    controller.replyEvent = _reply(controller.room);
    controller.room.sendResult = Completer<String?>();
    final picker = await _mountPicker(tester, controller);
    picker.onSelected(_sticker);
    await tester.pump();
    final newerReply = controller.replyEvent = _reply(controller.room, r'$new');
    controller.room.sendResult!.complete(r'$sent');
    await tester.pump();
    expect(controller.replyEvent, same(newerReply));
    expect(controller.cancelledReplies, 0);
  });

  testWidgets('delayed send does not update a disposed controller', (
    tester,
  ) async {
    final controller = _Controller();
    controller.replyEvent = _reply(controller.room);
    controller.room.sendResult = Completer<String?>();
    final picker = await _mountPicker(tester, controller);
    picker.onSelected(_sticker);
    await tester.pump();
    controller.isMounted = false;
    controller.room.sendResult!.complete(r'$sent');
    await tester.pump();
    expect(controller.cancelledReplies, 0);
  });

  testWidgets('verification delay keeps the original reply and thread', (
    tester,
  ) async {
    final controller = _Controller()
      ..activeThreadId = r'$thread'
      ..threadLastEventId = r'$last';
    controller.replyEvent = _reply(controller.room);
    controller.room.encrypted = true;
    controller.room.participants = Completer<List<User>>();
    final picker = await _mountPicker(tester, controller);
    picker.onSelected(_sticker);
    await tester.pump();
    expect(controller.room.sent, isNull);
    final newerReply = controller.replyEvent = _reply(controller.room, r'$new');
    controller.activeThreadId = null;
    controller.threadLastEventId = null;
    controller.room.participants!.complete([]);
    await tester.pump();
    expect(controller.room.sent!['m.relates_to'], {
      'event_id': r'$thread',
      'rel_type': RelationshipTypes.thread,
      'is_falling_back': false,
      'm.in_reply_to': {'event_id': r'$reply'},
    });
    expect(controller.replyEvent, same(newerReply));
    expect(controller.cancelledReplies, 0);
  });
}
