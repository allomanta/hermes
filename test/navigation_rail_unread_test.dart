// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes/l10n/l10n.dart';
import 'package:hermes/pages/chat_list/chat_filter_toggle.dart';
import 'package:hermes/pages/chat_list/navigation_rail.dart';
import 'package:hermes/widgets/matrix.dart';
import 'package:hermes/widgets/unread_rooms_badge.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:matrix/src/utils/space_child.dart';
import 'package:provider/provider.dart';

class _Room extends Fake implements Room {
  bool unread = false;

  @override
  String get id => '!room:example.org';
  @override
  bool get isSpace => false;
  @override
  bool get isUnread => unread;
  @override
  bool get isUnreadOrInvited => unread;
  @override
  Membership get membership => Membership.join;
}

class _Space extends Fake implements Room {
  @override
  String get id => '!space:example.org';
  @override
  bool get isSpace => true;
  @override
  bool get isUnread => false;
  @override
  Membership get membership => Membership.join;
  @override
  List<SpaceChild> get spaceChildren => [];
  @override
  Uri? get avatar => null;
  @override
  String getLocalizedDisplayname([
    MatrixLocalizations i18n = const MatrixDefaultLocalizations(),
  ]) => '😀 ${String.fromCharCode(0xd800)} Space';
}

class _Client extends Fake implements Client {
  @override
  final rooms = <Room>[_Room(), _Space()];
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
    final activeSpaceId = ValueNotifier<String?>(null);
    addTearDown(unreadSelected.dispose);
    addTearDown(activeSpaceId.dispose);
    addTearDown(client.onSync.close);
    final router = GoRouter(
      initialLocation: '/rooms',
      routes: [
        GoRoute(
          path: '/rooms',
          builder: (context, state) => Scaffold(
            body: AnimatedBuilder(
              animation: Listenable.merge([unreadSelected, activeSpaceId]),
              builder: (context, _) => SpacesNavigationRail(
                activeSpaceId: activeSpaceId.value,
                unreadSelected: unreadSelected.value,
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
    const selectionKey = Key('chat_filters_selection');
    const opacityKey = Key('chat_filters_selection_opacity');
    expect(tester.getSize(find.byKey(unreadKey)).height, 0);
    expect(tester.getSize(find.byKey(capsuleKey)), const Size(48, 48));

    (client.rooms.first as _Room).unread = true;
    client.onSync.add(
      SyncUpdate(
        nextBatch: 'next',
        rooms: RoomsUpdate(join: {'!room:example.org': JoinedRoomUpdate()}),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(unreadKey)).height, 52);
    expect(tester.getSize(find.byKey(capsuleKey)), const Size(48, 100));
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

    final allChatsSelectionTop = tester.getTopLeft(find.byKey(selectionKey)).dy;
    await tester.tap(find.byIcon(Icons.mark_chat_unread_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 125));
    final movingSelectionTop = tester.getTopLeft(find.byKey(selectionKey)).dy;
    expect(movingSelectionTop, greaterThan(allChatsSelectionTop));
    expect(movingSelectionTop, lessThan(allChatsSelectionTop + 52));
    expect(
      tester
          .widget<Transform>(
            find.byKey(const Key('chat_filters_thumb_transform')),
          )
          .transform
          .getMaxScaleOnAxis(),
      greaterThan(1),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byKey(selectionKey)).dy,
      closeTo(allChatsSelectionTop + 52, 0.1),
    );
    expect(
      tester.widget<ChatFilterToggle>(find.byType(ChatFilterToggle)).selection,
      ChatFilterSelection.unread,
    );

    activeSpaceId.value = '!space:example.org';
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 125));
    expect(
      tester.getTopLeft(find.byKey(selectionKey)).dy,
      closeTo(allChatsSelectionTop + 52, 0.1),
    );
    final fadingOut = tester.widget<Opacity>(find.byKey(opacityKey)).opacity;
    expect(fadingOut, greaterThan(0));
    expect(fadingOut, lessThan(1));
    await tester.pumpAndSettle();
    expect(tester.widget<Opacity>(find.byKey(opacityKey)).opacity, 0);
    activeSpaceId.value = null;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 125));
    expect(
      tester.getTopLeft(find.byKey(selectionKey)).dy,
      closeTo(allChatsSelectionTop + 52, 0.1),
    );
    final fadingIn = tester.widget<Opacity>(find.byKey(opacityKey)).opacity;
    expect(fadingIn, greaterThan(0));
    expect(fadingIn, lessThan(1));
    await tester.pumpAndSettle();
    expect(tester.widget<Opacity>(find.byKey(opacityKey)).opacity, 1);
    expect(
      tester.getTopLeft(find.byKey(selectionKey)).dy,
      closeTo(allChatsSelectionTop + 52, 0.1),
    );

    await tester.tap(find.byIcon(Icons.forum_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 125));
    final movingUpTop = tester.getTopLeft(find.byKey(selectionKey)).dy;
    expect(movingUpTop, greaterThan(allChatsSelectionTop));
    expect(movingUpTop, lessThan(allChatsSelectionTop + 52));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byKey(selectionKey)).dy,
      closeTo(allChatsSelectionTop, 0.1),
    );
    expect(
      tester.widget<ChatFilterToggle>(find.byType(ChatFilterToggle)).selection,
      ChatFilterSelection.all,
    );

    final normalColor = tester.widget<Icon>(find.byIcon(Icons.forum)).color!;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(
      tester.getCenter(find.byKey(const Key('chat_filter_all'))),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    expect(
      tester
          .widget<Transform>(
            find.byKey(const Key('chat_filter_all_icon_scale')),
          )
          .transform
          .getMaxScaleOnAxis(),
      greaterThan(1),
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.forum)).color!.computeLuminance(),
      greaterThan(normalColor.computeLuminance()),
    );
    await mouse.removePointer();

    await tester.pump(const Duration(seconds: 1));
    (client.rooms.first as _Room).unread = false;
    client.onSync.add(
      SyncUpdate(
        nextBatch: 'later',
        rooms: RoomsUpdate(join: {'!room:example.org': JoinedRoomUpdate()}),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(unreadKey)).height, 0);
    expect(tester.getSize(find.byKey(capsuleKey)), const Size(48, 48));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 1));
  });
}
