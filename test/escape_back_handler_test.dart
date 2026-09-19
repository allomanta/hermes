// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes/widgets/escape_back_handler.dart';
import 'package:material_ui/material_ui.dart';

Future<GoRouter> _mountRouter(
  WidgetTester tester,
  String location, {
  FocusNode? sidebarFocus,
  ValueNotifier<bool>? blockBack,
}) async {
  final router = GoRouter(
    initialLocation: location,
    routes: [
      ShellRoute(
        builder: (context, state, child) => Row(
          children: [
            SizedBox(
              width: 200,
              child: Material(child: TextField(focusNode: sidebarFocus)),
            ),
            Expanded(child: child),
          ],
        ),
        routes: [
          GoRoute(
            path: '/rooms',
            builder: (_, _) => const Scaffold(body: Text('Rooms')),
            routes: [
              GoRoute(
                path: 'room',
                builder: (_, _) => const Scaffold(body: Text('Chat')),
                routes: [
                  GoRoute(
                    path: 'details',
                    builder: (_, _) => blockBack == null
                        ? const Scaffold(body: Text('Details'))
                        : ValueListenableBuilder(
                            valueListenable: blockBack,
                            builder: (_, blocked, _) => PopScope(
                              canPop: !blocked,
                              onPopInvokedWithResult: (didPop, _) {
                                if (!didPop) blockBack.value = false;
                              },
                              child: const Scaffold(body: Text('Details')),
                            ),
                          ),
                  ),
                ],
              ),
              ShellRoute(
                builder: (_, _, child) => child,
                routes: [
                  GoRoute(
                    path: 'settings',
                    builder: (_, _) => const Scaffold(body: Text('Settings')),
                    routes: [
                      GoRoute(
                        path: 'chat',
                        builder: (_, _) =>
                            const Scaffold(body: Text('Chat settings')),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => EscapeBackHandler(
        onBack: () => unawaited(router.routerDelegate.popRoute()),
        child: child!,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  for (final (location, parent) in [
    ('/rooms/room', '/rooms'),
    ('/rooms/room/details', '/rooms/room'),
    ('/rooms/settings/chat', '/rooms/settings'),
    ('/rooms/settings', '/rooms'),
  ]) {
    testWidgets('Escape goes back from $location with sidebar focus', (
      tester,
    ) async {
      final sidebarFocus = FocusNode();
      addTearDown(sidebarFocus.dispose);
      final router = await _mountRouter(
        tester,
        location,
        sidebarFocus: sidebarFocus,
      );
      sidebarFocus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, parent);
    });
  }

  testWidgets('Escape respects pop guards before leaving the route', (
    tester,
  ) async {
    final blockBack = ValueNotifier(true);
    addTearDown(blockBack.dispose);
    final router = await _mountRouter(
      tester,
      '/rooms/room/details',
      blockBack: blockBack,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(blockBack.value, isFalse);
    expect(
      router.routeInformationProvider.value.uri.path,
      '/rooms/room/details',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/rooms/room');
  });

  testWidgets('Escape on the root page does not close the app', (tester) async {
    final router = await _mountRouter(tester, '/rooms');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/rooms');
    expect(find.text('Rooms'), findsOneWidget);
  });

  testWidgets(
    'focused controls take precedence and repeats do not go back twice',
    (tester) async {
      var localActions = 0;
      var backs = 0;
      final handleLocally = ValueNotifier(true);
      addTearDown(handleLocally.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: EscapeBackHandler(
            onBack: () => backs++,
            child: ValueListenableBuilder(
              valueListenable: handleLocally,
              builder: (_, local, _) => CallbackShortcuts(
                bindings: {
                  if (local)
                    const SingleActivator(LogicalKeyboardKey.escape): () =>
                        localActions++,
                },
                child: const Focus(autofocus: true, child: SizedBox()),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(localActions, 1);
      expect(backs, 0);
      handleLocally.value = false;
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
      expect(backs, 1);
    },
  );
}
