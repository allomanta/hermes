// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/config/setting_keys.dart';
import 'package:hermes/l10n/l10n.dart';
import 'package:hermes/pages/chat/events/html_message.dart';
import 'package:hermes/utils/matrix_sdk_extensions/room_send_text_extension.dart';
import 'package:html/parser.dart' as parser;
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/markdown.dart' as sdk;
import 'package:shared_preferences/shared_preferences.dart';

class _Client extends Fake implements Client {
  @override
  String get userID => '@me:example.org';
  @override
  bool get convertLinebreaksInFormatting => true;
  @override
  bool get enableLatexMarkdown => true;
  @override
  final Map<String, BasicEvent> accountData = {};
  @override
  final Map<String, CommandExecutionCallback> commands = {};
}

class _Room extends Room {
  _Room() : super(id: '!room:example.org', client: _Client());
  Map<String, dynamic>? sent;
  Event? reply;
  String? editId, transactionId, threadId, threadLastId;
  bool? pending;

  @override
  String? getMention(String mention) =>
      mention == '@alice' ? '@alice:example.org' : null;

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
    sent = content;
    reply = inReplyTo;
    editId = editEventId;
    transactionId = txid;
    threadId = threadRootEventId;
    threadLastId = threadLastEventId;
    pending = displayPendingEvent;
    return r'$sent';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
  });

  for (final (input, expected) in [
    ('`<T>`', '<T>'),
    ('`x > y`', 'x > y'),
    ('`a < b && c > d`', 'a < b && c > d'),
    ('`<b>not bold</b>`', '<b>not bold</b>'),
    ('`` `<T>` ``', '`<T>`'),
    ('```dart\nList<T> values;\n```', 'List<T> values;\n'),
    ('    List<T> values;\n', 'List<T> values;\n'),
    ('> ```\n> List<T> values;\n> ```', 'List<T> values;\n'),
    ('`&lt;T&gt;`', '&lt;T&gt;'),
    ('`\uE000; <T> \uE001;`', '\uE000; <T> \uE001;'),
  ]) {
    test('preserves code text for $input', () async {
      final room = _Room();
      await room.sendTextEventWithFormatting(input, parseCommands: false);
      expect(room.sent!['body'], input);
      final document = parser.parseFragment(
        room.sent!['formatted_body'] as String,
      );
      expect(document.querySelector('code')!.text, expected);
      expect(document.querySelector('code')!.children, isEmpty);
    });
  }

  test(
    'keeps actual angles and literal entity text distinct in one message',
    () async {
      final room = _Room();
      await room.sendTextEventWithFormatting(
        '`<T>` and `&lt;T&gt;`',
        parseCommands: false,
      );
      final document = parser.parseFragment(
        room.sent!['formatted_body'] as String,
      );
      expect(document.querySelectorAll('code').map((node) => node.text), [
        '<T>',
        '&lt;T&gt;',
      ]);
    },
  );

  test(
    'tag-shaped prose stays literal even alongside rich formatting',
    () async {
      final room = _Room();
      await room.sendTextEventWithFormatting(
        '**bold** <script>alert("x")</script> <img src="x">',
        parseCommands: false,
      );
      final document = parser.parseFragment(
        room.sent!['formatted_body'] as String,
      );
      expect(document.querySelector('strong')!.text, 'bold');
      expect(document.querySelector('script'), isNull);
      expect(document.querySelector('img'), isNull);
      expect(
        document.text,
        contains('<script>alert("x")</script> <img src="x">'),
      );
      await room.sendTextEventWithFormatting('<T>', parseCommands: false);
      expect(room.sent!['body'], '<T>');
      expect(room.sent!.containsKey('formatted_body'), isFalse);
    },
  );

  test('ordinary Markdown retains the SDK formatting', () async {
    final room = _Room();
    for (final input in [
      '**bold** and __italic__ and ~~strike~~',
      '> quote',
      '>> nested quote',
      '- [ ] task\n- list item',
      '[link](https://example.org)',
      '||spoiler||',
      '**text**\nnext line',
      '**bold** <T>',
    ]) {
      await room.sendTextEventWithFormatting(input, parseCommands: false);
      expect(room.sent!['formatted_body'], sdk.markdown(input));
    }
  });

  test(
    'mentions and reply, edit, thread and pending options are preserved',
    () async {
      final room = _Room();
      final reply = Event(
        room: room,
        eventId: r'$reply',
        senderId: '@reply:example.org',
        originServerTs: DateTime(2026),
        type: EventTypes.Message,
        content: {'msgtype': MessageTypes.Text, 'body': 'Original'},
      );
      await room.sendTextEventWithFormatting(
        '@alice @room @me:example.org `<T>`',
        parseCommands: false,
        inReplyTo: reply,
        editEventId: r'$edit',
        txid: 'tx',
        threadRootEventId: r'$thread',
        threadLastEventId: r'$last',
        displayPendingEvent: false,
        msgtype: MessageTypes.Emote,
      );
      expect(room.sent!['msgtype'], MessageTypes.Emote);
      expect(room.sent!['m.mentions'], {
        'room': true,
        'user_ids': ['@alice:example.org', '@reply:example.org'],
      });
      expect(room.reply, same(reply));
      expect(room.editId, r'$edit');
      expect(room.transactionId, 'tx');
      expect(room.threadId, r'$thread');
      expect(room.threadLastId, r'$last');
      expect(room.pending, isFalse);
    },
  );

  test(
    'command dispatch still receives the original message and metadata',
    () async {
      final room = _Room();
      CommandArgs? received;
      room.client.addCommand('me', (args, stdout) {
        received = args;
        return r'$command';
      });
      expect(
        await room.sendTextEventWithFormatting(
          '/me `<T>`',
          editEventId: r'$edit',
        ),
        r'$command',
      );
      expect(received!.msg, '`<T>`');
      expect(received!.editEventId, r'$edit');
      expect(room.sent, isNull);
    },
  );

  testWidgets('Hermes renders the corrected code with literal angles', (
    tester,
  ) async {
    final room = _Room();
    await room.sendTextEventWithFormatting(
      '```dart\nList<T> values;\n```',
      parseCommands: false,
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: HtmlMessage(
            html: room.sent!['formatted_body'] as String,
            room: room,
            fontSize: 14,
            linkStyle: const TextStyle(),
            onOpen: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final rendered = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((text) => text.text.toPlainText());
    expect(rendered.any((text) => text.contains('List<T> values;')), isTrue);
    expect(rendered.any((text) => text.contains('&lt;T&gt;')), isFalse);
    expect(tester.takeException(), isNull);
  });
}
