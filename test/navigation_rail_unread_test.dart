// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes/l10n/l10n.dart';
import 'package:hermes/pages/chat_list/navi_rail_item.dart';
import 'package:hermes/pages/chat_list/navigation_rail.dart';
import 'package:hermes/widgets/matrix.dart';
import 'package:hermes/widgets/unread_rooms_badge.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:provider/provider.dart';

class _Room extends Fake implements Room {
  bool unread = false;

  @override
  bool get isSpace => false;
  @override
  bool get isUnread => unread;
  @override
  bool get isUnreadOrInvited => unread;
  @override
  Membership get membership => Membership.join;
}

class _Client extends Fake implements Client {
  @override
  final rooms = <Room>[_Room()];
  @override
  String get userID => '@me:example.org';
  @override
  final onSync = CachedStreamController<SyncUpdate>();
}

class _Matrix extends Fake with Diagnosticable implements MatrixState {
  _Matrix(this.client);

  @override
  final _Client client;
}

void main() {
  testWidgets('unread destination slides in and filters the rail selection', (
    tester,
  ) async {
    final client = _Client();
    final unreadSelected = ValueNotifier(false);
    addTearDown(unreadSelected.dispose);
    addTearDown(client.onSync.close);
    final router = GoRouter(
      initialLocation: '/rooms',
      routes: [
        GoRoute(
          path: '/rooms',
          builder: (context, state) => Scaffold(
            body: ValueListenableBuilder(
              valueListenable: unreadSelected,
              builder: (context, isUnreadSelected, _) => SpacesNavigationRail(
                activeSpaceId: null,
                unreadSelected: isUnreadSelected,
                onGoToChats: () => unreadSelected.value = false,
                onGoToUnread: () => unreadSelected.value = true,
                onGoToSpaceId: (_) {},
              ),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      Provider<MatrixState>.value(
        value: _Matrix(client),
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
    const unreadKey = Key('unread_rail_destination');
    const capsuleKey = Key('chat_filters_capsule');
    expect(tester.getSize(find.byKey(unreadKey)).height, 0);
    expect(tester.getSize(find.byKey(capsuleKey)), const Size(48, 48));

    (client.rooms.single as _Room).unread = true;
    client.onSync.add(
      SyncUpdate(
        nextBatch: 'next',
        rooms: RoomsUpdate(join: {'!room:example.org': JoinedRoomUpdate()}),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(unreadKey)).height, 60);
    expect(tester.getSize(find.byKey(capsuleKey)), const Size(48, 108));
    expect(
      find.ancestor(
        of: find.byIcon(Icons.forum),
        matching: find.byType(UnreadRoomsBadge),
      ),
      findsNothing,
    );
    expect(
      find.ancestor(
        of: find.byIcon(Icons.mark_chat_unread_outlined),
        matching: find.byType(UnreadRoomsBadge),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byIcon(Icons.mark_chat_unread_outlined));
    await tester.pumpAndSettle();
    final items = tester.widgetList<NaviRailItem>(find.byType(NaviRailItem));
    expect(items.first.isSelected, isFalse);
    expect(items.elementAt(1).isSelected, isTrue);

    await tester.tap(find.byIcon(Icons.forum_outlined));
    await tester.pumpAndSettle();
    final allChatsItems = tester.widgetList<NaviRailItem>(
      find.byType(NaviRailItem),
    );
    expect(allChatsItems.first.isSelected, isTrue);
    expect(allChatsItems.elementAt(1).isSelected, isFalse);

    await tester.pump(const Duration(seconds: 1));
    (client.rooms.single as _Room).unread = false;
    client.onSync.add(
      SyncUpdate(
        nextBatch: 'later',
        rooms: RoomsUpdate(join: {'!room:example.org': JoinedRoomUpdate()}),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(unreadKey)).height, 0);
    expect(tester.getSize(find.byKey(capsuleKey)), const Size(48, 48));
    await tester.pump(const Duration(seconds: 1));
  });
}
