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
import 'package:shared_preferences/shared_preferences.dart';

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
  _Space(this.id, this.displayName);

  @override
  final String id;
  final String displayName;
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
  ]) => displayName;
}

class _Client extends Fake implements Client {
  @override
  final rooms = <Room>[
    _Room(),
    _Space('!space:example.org', '😀 ${String.fromCharCode(0xd800)} Space'),
    _Space('!second:example.org', 'Second Space'),
  ];
  @override
  String get userID => '@me:example.org';
  @override
  String get clientName => 'test-client';
  @override
  final onSync = CachedStreamController<SyncUpdate>();
}

class _Matrix extends Fake with Diagnosticable implements MatrixState {
  _Matrix(this.client, this.store);

  @override
  final _Client client;
  @override
  final SharedPreferences store;
}

void main() {
  testWidgets('dragging spaces saves their order without blocking taps', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = await SharedPreferences.getInstance();
    final client = _Client();
    addTearDown(client.onSync.close);
    String? selectedSpace;
    final router = GoRouter(
      initialLocation: '/rooms',
      routes: [
        GoRoute(
          path: '/rooms',
          builder: (context, state) => Scaffold(
            body: SpacesNavigationRail(
              activeSpaceId: null,
              unreadSelected: false,
              onGoToChats: () {},
              onGoToUnread: () {},
              onGoToSpaceId: (id) => selectedSpace = id,
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    Widget app(TargetPlatform platform) => Provider<MatrixState>.value(
      value: _Matrix(client, store),
      child: MaterialApp.router(
        theme: ThemeData(platform: platform),
        routerConfig: router,
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
      ),
    );

    await tester.pumpWidget(app(TargetPlatform.macOS));
    await tester.pumpAndSettle();
    final first = find.byKey(const ValueKey('!space:example.org'));
    final second = find.byKey(const ValueKey('!second:example.org'));
    expect(tester.getTopLeft(first).dy, lessThan(tester.getTopLeft(second).dy));

    await tester.tap(second);
    expect(selectedSpace, '!second:example.org');
    await tester.timedDrag(
      first,
      const Offset(0, 100),
      const Duration(milliseconds: 500),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(first).dy,
      greaterThan(tester.getTopLeft(second).dy),
    );
    expect(store.getStringList('chat.pantheon.space_order.test-client'), [
      '!second:example.org',
      '!space:example.org',
    ]);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(app(TargetPlatform.macOS));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(first).dy,
      greaterThan(tester.getTopLeft(second).dy),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(app(TargetPlatform.android));
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(tester.getCenter(second));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 70));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(first).dy, lessThan(tester.getTopLeft(second).dy));
    expect(store.getStringList('chat.pantheon.space_order.test-client'), [
      '!space:example.org',
      '!second:example.org',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('filter and space indicators slide and fade independently', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = await SharedPreferences.getInstance();
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
        value: _Matrix(client, store),
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
    const spaceIndicatorKey = Key('space_selection_indicator');
    const spaceOpacityKey = Key('space_selection_opacity');
    expect(tester.getSize(find.byKey(unreadKey)).height, 0);
    expect(tester.getSize(find.byKey(capsuleKey)), const Size(48, 48));
    expect(tester.widget<Opacity>(find.byKey(spaceOpacityKey)).opacity, 0);

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
    final spaceFadingIn = tester
        .widget<Opacity>(find.byKey(spaceOpacityKey))
        .opacity;
    expect(spaceFadingIn, greaterThan(0));
    expect(spaceFadingIn, lessThan(1));
    await tester.pumpAndSettle();
    expect(tester.widget<Opacity>(find.byKey(opacityKey)).opacity, 0);
    expect(tester.widget<Opacity>(find.byKey(spaceOpacityKey)).opacity, 1);
    final firstSpaceTop = tester.getTopLeft(find.byKey(spaceIndicatorKey)).dy;
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
    expect(tester.widget<Opacity>(find.byKey(spaceOpacityKey)).opacity, 0);
    expect(
      tester.getTopLeft(find.byKey(selectionKey)).dy,
      closeTo(allChatsSelectionTop + 52, 0.1),
    );

    activeSpaceId.value = '!space:example.org';
    await tester.pumpAndSettle();
    activeSpaceId.value = '!second:example.org';
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    final movingSpaceTop = tester.getTopLeft(find.byKey(spaceIndicatorKey)).dy;
    expect(movingSpaceTop, greaterThan(firstSpaceTop));
    expect(movingSpaceTop, lessThan(firstSpaceTop + 60));
    expect(
      tester
          .widget<Transform>(find.byKey(const Key('space_selection_scale')))
          .transform
          .getMaxScaleOnAxis(),
      greaterThan(1),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byKey(spaceIndicatorKey)).dy,
      closeTo(firstSpaceTop + 60, 0.1),
    );
    activeSpaceId.value = null;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 125));
    expect(
      tester.getTopLeft(find.byKey(spaceIndicatorKey)).dy,
      closeTo(firstSpaceTop + 60, 0.1),
    );
    final spaceFadingOut = tester
        .widget<Opacity>(find.byKey(spaceOpacityKey))
        .opacity;
    expect(spaceFadingOut, greaterThan(0));
    expect(spaceFadingOut, lessThan(1));
    await tester.pumpAndSettle();
    expect(tester.widget<Opacity>(find.byKey(spaceOpacityKey)).opacity, 0);

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

    tester.view.physicalSize = const Size(800, 220);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    activeSpaceId.value = '!second:example.org';
    await tester.pumpAndSettle();
    final beforeScroll = tester.getTopLeft(find.byKey(spaceIndicatorKey)).dy;
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    scrollable.position.jumpTo(40);
    await tester.pump();
    expect(
      tester.getTopLeft(find.byKey(spaceIndicatorKey)).dy,
      closeTo(beforeScroll - 40, 0.1),
    );
  });
}
