// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/l10n/l10n.dart';
import 'package:hermes/pages/chat_details/chat_details.dart';
import 'package:hermes/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

class _Client extends Fake implements Client {
  late _Room room;
  @override
  String get userID => '@me:example.org';
  @override
  bool get formatLocalpart => false;
  @override
  bool get mxidLocalPartFallback => true;
  @override
  Room? getRoomById(String roomId) => room;
}

class _Room extends Fake implements Room {
  _Room(this.client, List<String> members) {
    users = members.map((id) => User(id, room: this)).toList();
  }
  @override
  final _Client client;
  @override
  String get id => '!chat:example.org';
  @override
  bool get isSpace => false;
  late final List<User> users;
  String? directUser;
  bool removed = false;

  @override
  Future<List<User>> requestParticipants([
    List<Membership> membershipFilter = const [],
    bool suppressWarning = false,
    bool? cache,
    bool enforceFetchFromServer = false,
  ]) async => users;

  @override
  Future<void> addToDirectChat(String userID) async => directUser = userID;

  @override
  Future<void> removeFromDirectChat() async => removed = true;
}

class _Matrix extends Fake with Diagnosticable implements MatrixState {
  _Matrix(this.client);
  @override
  final Client client;
}

class _ChatDetails extends ChatDetails {
  const _ChatDetails() : super(roomId: '!chat:example.org');
  @override
  ChatDetailsController createState() => _Controller();
}

class _Controller extends ChatDetailsController {
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        TextButton(
          onPressed: () => setDirectChat(true),
          child: const Text('Direct'),
        ),
        TextButton(
          onPressed: () => setDirectChat(false),
          child: const Text('Group'),
        ),
      ],
    ),
  );
}

Future<_Room> _mountChat(WidgetTester tester, List<String> members) async {
  final client = _Client();
  final room = client.room = _Room(client, [client.userID, ...members]);
  await tester.pumpWidget(
    Provider<MatrixState>.value(
      value: _Matrix(client),
      child: MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: const _ChatDetails(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return room;
}

void main() {
  testWidgets('mark direct selects the sole other member', (tester) async {
    final room = await _mountChat(tester, ['@alice:example.org']);
    await tester.tap(find.text('Direct'));
    await tester.pumpAndSettle();
    expect(room.directUser, '@alice:example.org');
  });

  testWidgets(
    'bridged rooms let the user choose the person instead of the bot',
    (tester) async {
      final room = await _mountChat(tester, [
        '@signalbot:example.org',
        '@alice:example.org',
      ]);
      await tester.tap(find.text('Direct'));
      await tester.pumpAndSettle();
      expect(room.directUser, isNull);
      await tester.tap(find.text('alice (@alice:example.org)'));
      await tester.pumpAndSettle();
      expect(room.directUser, '@alice:example.org');
    },
  );

  testWidgets('cancelling person selection does not change the chat type', (
    tester,
  ) async {
    final room = await _mountChat(tester, [
      '@signalbot:example.org',
      '@alice:example.org',
    ]);
    await tester.tap(find.text('Direct'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(room.directUser, isNull);
    expect(room.removed, isFalse);
    expect(
      tester
          .state<ChatDetailsController>(find.byType(_ChatDetails))
          .changingChatType,
      isFalse,
    );
  });

  testWidgets('mark group removes the direct-chat classification', (
    tester,
  ) async {
    final room = await _mountChat(tester, ['@alice:example.org']);
    await tester.tap(find.text('Group'));
    await tester.pumpAndSettle();
    expect(room.removed, isTrue);
  });
}
