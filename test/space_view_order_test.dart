// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/l10n/l10n.dart';
import 'package:hermes/pages/chat_list/space_view.dart';
import 'package:hermes/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:matrix/src/utils/space_child.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Room extends Fake implements Room {
  _Room(this.id, this.name, this.client, {this.isSpace = false});

  @override
  final String id;
  @override
  final String name;
  @override
  final _Client client;
  @override
  final bool isSpace;
  @override
  Membership get membership => Membership.join;
  @override
  Uri? get avatar => null;
  @override
  Map<String, Map<String, StrippedStateEvent>> get states => {};
  @override
  PushRuleState get pushRuleState => PushRuleState.notify;
  @override
  bool get isUnread => false;
  @override
  bool get hasNewMessages => false;
  @override
  bool get markedUnread => false;
  @override
  int get notificationCount => 0;
  @override
  int get highlightCount => 0;
  @override
  bool canChangeStateEvent(String type) => false;
  @override
  String getLocalizedDisplayname([
    MatrixLocalizations i18n = const MatrixDefaultLocalizations(),
  ]) => name;
  @override
  List<SpaceChild> get spaceChildren => isSpace
      ? client.rooms
            .where((room) => room.id != id)
            .map(
              (room) => SpaceChild.fromState(
                StrippedStateEvent(
                  type: EventTypes.SpaceChild,
                  stateKey: room.id,
                  senderId: '@me:example.org',
                  content: {
                    'via': ['example.org'],
                  },
                ),
              ),
            )
            .toList()
      : [];
}

class _Client extends Fake implements Client {
  @override
  late final rooms = <Room>[
    _Room('!pinned:example.org', 'Pinned', this),
    _Room('!recent1:example.org', 'Recent One', this),
    _Room('!recent2:example.org', 'Recent Two', this),
    _Room('!missing:example.org', 'Missing Recent', this),
    _Room('!older1:example.org', 'Older One', this),
    _Room('!older2:example.org', 'Older Two', this),
    _Room('!space:example.org', 'Example Space', this, isSpace: true),
  ];

  @override
  final onSync = CachedStreamController<SyncUpdate>();

  @override
  Room? getRoomById(String roomId) {
    for (final room in rooms) {
      if (room.id == roomId) return room;
    }
    return null;
  }

  @override
  Future<GetSpaceHierarchyResponse> getSpaceHierarchy(
    String roomId, {
    bool? suggestedOnly,
    int? limit,
    int? maxDepth,
    String? from,
  }) async => GetSpaceHierarchyResponse(
    rooms: [
      for (final room in rooms.where(
        (room) => room.id != roomId && room.id != '!missing:example.org',
      ))
        SpaceRoomsChunk$2(
          guestCanJoin: false,
          numJoinedMembers: 1,
          roomId: room.id,
          worldReadable: false,
          childrenState: [],
          name: (room as _Room).name,
        ),
    ],
  );
}

class _Matrix extends Fake with Diagnosticable implements MatrixState {
  _Matrix(this.client, this.store);

  @override
  final _Client client;
  @override
  final SharedPreferences store;
}

void main() {
  testWidgets(
    'space shows locally joined rooms omitted by hierarchy in chat order',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = await SharedPreferences.getInstance();
      final client = _Client();
      addTearDown(client.onSync.close);

      await tester.pumpWidget(
        Provider<MatrixState>.value(
          value: _Matrix(client, store),
          child: MaterialApp(
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: SpaceView(
              spaceId: '!space:example.org',
              activeChat: null,
              onBack: () {},
              onUnreadChanged: () {},
              onChatTab: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final names = [
        'Pinned',
        'Recent One',
        'Recent Two',
        'Missing Recent',
        'Older One',
        'Older Two',
      ];
      final positions = names
          .map((name) => tester.getTopLeft(find.text(name)).dy)
          .toList();
      expect(positions, orderedEquals([...positions]..sort()));
      expect(tester.takeException(), isNull);
    },
  );
}
