// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes/config/routes.dart';
import 'package:hermes/config/setting_keys.dart';
import 'package:hermes/config/themes.dart';
import 'package:hermes/l10n/l10n.dart';
import 'package:hermes/utils/column_layout_controller.dart';
import 'package:hermes/widgets/interface_scale.dart';
import 'package:hermes/widgets/layouts/two_column_layout.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _mainPane = ValueKey('main-pane');
const _sidePane = ValueKey('side-pane');
const _divider = ValueKey('column-divider');

class _ChatList extends StatelessWidget {
  const _ChatList();

  @override
  Widget build(BuildContext context) => Scaffold(
    key: _mainPane,
    body: Column(
      children: [
        const Text('Chat list'),
        TextButton(
          onPressed: () => context.go('/rooms/first'),
          child: const Text('Open first'),
        ),
        TextButton(
          onPressed: () => context.go('/rooms/second'),
          child: const Text('Open second'),
        ),
      ],
    ),
  );
}

class _Chat extends StatefulWidget {
  const _Chat({super.key});

  @override
  State<_Chat> createState() => _ChatState();
}

class _ChatState extends State<_Chat> {
  final text = TextEditingController();
  final focus = FocusNode();

  @override
  void dispose() {
    text.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    key: _sidePane,
    appBar: AppBar(
      title: Text(
        PantheonThemes.isColumnMode(context) ? 'Two columns' : 'Single column',
      ),
      automaticallyImplyLeading: !PantheonThemes.isColumnMode(context),
    ),
    body: TextField(controller: text, focusNode: focus),
  );
}

Future<({ColumnLayoutController layout, GoRouter router})> _mountApp(
  WidgetTester tester, {
  TextDirection direction = TextDirection.ltr,
  bool hasNavigationRail = true,
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final router = GoRouter(
    initialLocation: '/rooms/first',
    routes: [
      ShellRoute(
        pageBuilder: (context, state, child) =>
            AppRoutes.noTransitionPageBuilder(
              context,
              state,
              PantheonThemes.isColumnModeByWidth(
                        MediaQuery.sizeOf(context).width,
                      ) &&
                      !state.uri.path.startsWith('/rooms/settings')
                  ? TwoColumnLayout(
                      mainView: const _ChatList(),
                      sideView: child,
                      hasNavigationRail: hasNavigationRail,
                    )
                  : child,
            ),
        routes: [
          GoRoute(
            path: '/rooms',
            pageBuilder: (context, state) => AppRoutes.defaultPageBuilder(
              context,
              state,
              PantheonThemes.isMainColumnVisible(context)
                  ? const SizedBox()
                  : const _ChatList(),
            ),
            routes: [
              ShellRoute(
                pageBuilder: (context, state, child) =>
                    AppRoutes.noTransitionPageBuilder(
                      context,
                      state,
                      PantheonThemes.isColumnModeByWidth(
                            MediaQuery.sizeOf(context).width,
                          )
                          ? TwoColumnLayout(
                              mainView: const _ChatList(),
                              sideView: child,
                              hasNavigationRail: false,
                            )
                          : child,
                    ),
                routes: [
                  GoRoute(
                    path: 'settings',
                    pageBuilder: (context, state) =>
                        AppRoutes.defaultPageBuilder(
                          context,
                          state,
                          PantheonThemes.isMainColumnVisible(context)
                              ? const SizedBox()
                              : const _ChatList(),
                        ),
                    routes: [
                      GoRoute(
                        path: 'style',
                        pageBuilder: (context, state) =>
                            AppRoutes.defaultPageBuilder(
                              context,
                              state,
                              _Chat(key: ValueKey(state.uri)),
                            ),
                      ),
                    ],
                  ),
                ],
              ),
              GoRoute(
                path: ':roomid',
                pageBuilder: (context, state) => AppRoutes.defaultPageBuilder(
                  context,
                  state,
                  _Chat(key: ValueKey(state.uri)),
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  final layout = ColumnLayoutController(
    columnWidth: PantheonThemes.columnWidth,
    navigation: router.routeInformationProvider,
  );
  addTearDown(layout.dispose);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    InterfaceScale(
      child: ColumnLayoutScope(
        controller: layout,
        child: MaterialApp.router(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          routerConfig: router,
          builder: (_, child) =>
              Directionality(textDirection: direction, child: child!),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (layout: layout, router: router);
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
  });
  setUp(() async => AppSettings.store.clear());

  for (final direction in TextDirection.values) {
    testWidgets('divider resizes both panes in ${direction.name}', (
      tester,
    ) async {
      final app = await _mountApp(tester, direction: direction);
      expect(tester.getSize(find.byKey(_mainPane)).width, 450);
      expect(tester.getSize(find.byKey(_sidePane)).width, 749);
      final delta = direction == TextDirection.ltr ? 100.0 : -100.0;
      await tester.drag(find.byKey(_divider), Offset(delta, 0));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(_mainPane)).width, 550);
      expect(tester.getSize(find.byKey(_sidePane)).width, 649);
      expect(app.layout.columnWidth, 480);
      app.router.go('/rooms/second');
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(_mainPane)).width, 550);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('collapsing the list preserves the chat and enables back', (
    tester,
  ) async {
    final app = await _mountApp(tester);
    final chat = tester.state<_ChatState>(find.byType(_Chat));
    await tester.enterText(find.byType(TextField), 'Unsent draft');
    await tester.drag(find.byKey(_divider), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(app.layout.value, CollapsedPane.main);
    expect(find.byKey(_mainPane), findsNothing);
    expect(tester.getSize(find.byKey(_sidePane)).width, 1200);
    expect(find.text('Single column'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
    expect(tester.state<_ChatState>(find.byType(_Chat)), same(chat));
    expect(chat.text.text, 'Unsent draft');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(app.router.routeInformationProvider.value.uri.path, '/rooms');
    expect(find.text('Chat list'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('collapsing the chat preserves its draft and disables focus', (
    tester,
  ) async {
    final app = await _mountApp(tester);
    final chat = tester.state<_ChatState>(find.byType(_Chat));
    await tester.enterText(find.byType(TextField), 'Unsent draft');
    chat.focus.requestFocus();
    await tester.pump();
    expect(chat.focus.hasFocus, isTrue);
    await tester.drag(find.byKey(_divider), const Offset(700, 0));
    await tester.pumpAndSettle();
    expect(app.layout.value, CollapsedPane.side);
    expect(tester.getSize(find.byKey(_mainPane)).width, 1200);
    expect(find.byKey(_sidePane), findsNothing);
    expect(chat.focus.hasFocus, isFalse);
    expect(
      TickerMode.valuesOf(
        tester.element(find.byType(_Chat, skipOffstage: false)),
      ).enabled,
      isFalse,
    );
    expect(chat.text.text, 'Unsent draft');
    // Re-selecting the same room also reveals the retained navigator.
    await tester.tap(find.text('Open first'));
    await tester.pumpAndSettle();
    expect(app.layout.value, CollapsedPane.main);
    expect(find.text('Single column'), findsOneWidget);
    expect(tester.state<_ChatState>(find.byType(_Chat)), same(chat));
    expect(chat.text.text, 'Unsent draft');
    expect(tester.takeException(), isNull);
  });

  for (final (delta, reopen) in [
    (const Offset(-300, 0), const Offset(300, 0)),
    (const Offset(700, 0), const Offset(-450, 0)),
  ]) {
    testWidgets('dragging a collapsed edge reopens both panes after $delta', (
      tester,
    ) async {
      final app = await _mountApp(tester);
      await tester.drag(find.byKey(_divider), delta);
      await tester.pumpAndSettle();
      expect(app.layout.value, isNotNull);
      await tester.drag(find.byKey(_divider), reopen);
      await tester.pumpAndSettle();
      expect(app.layout.value, isNull);
      expect(find.byKey(_mainPane), findsOneWidget);
      expect(find.text('Two columns'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the handle continues tracking through collapse and expansion', (
    tester,
  ) async {
    final app = await _mountApp(tester);
    final start = tester.getCenter(find.byKey(_divider));
    final gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(app.layout.value, CollapsedPane.main);
    await gesture.moveBy(const Offset(400, 0));
    await tester.pumpAndSettle();
    expect(app.layout.value, isNull);
    expect(tester.getSize(find.byKey(_mainPane)).width, closeTo(550.5, 1));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('double-click resets the split and window resizing clamps it', (
    tester,
  ) async {
    final app = await _mountApp(tester);
    await tester.drag(find.byKey(_divider), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(app.layout.columnWidth, 680);
    await tester.binding.setSurfaceSize(const Size(900, 600));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(_sidePane)).width, 380);
    expect(app.layout.columnWidth, 680);
    await tester.binding.setSurfaceSize(const Size(1200, 600));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(_mainPane)).width, 750);
    await tester.tap(find.byKey(_divider));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(_divider));
    await tester.pumpAndSettle();
    expect(app.layout.columnWidth, 380);
    expect(tester.getSize(find.byKey(_mainPane)).width, 450);
    await tester.binding.setSurfaceSize(const Size(800, 600));
    await tester.pumpAndSettle();
    expect(find.byKey(_mainPane), findsNothing);
    expect(find.text('Single column'), findsOneWidget);
    expect(app.router.routeInformationProvider.value.uri.path, '/rooms/first');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the split uses scaled coordinates and supports no rail', (
    tester,
  ) async {
    await AppSettings.interfaceScale.setItem(1.25);
    final app = await _mountApp(tester, hasNavigationRail: false);
    expect(tester.getSize(find.byKey(_mainPane)).width, 380);
    await tester.drag(find.byKey(_divider), const Offset(125, 0));
    await tester.pumpAndSettle();
    expect(app.layout.columnWidth, closeTo(480, 1));
    await tester.drag(find.byKey(_divider), const Offset(-450, 0));
    await tester.pumpAndSettle();
    expect(app.layout.value, CollapsedPane.main);
    expect(find.text('Single column'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('nested settings navigation survives collapse and reopening', (
    tester,
  ) async {
    final app = await _mountApp(tester);
    app.router.go('/rooms/settings/style');
    await tester.pumpAndSettle();
    final page = tester.state<_ChatState>(find.byType(_Chat));
    expect(tester.getSize(find.byKey(_mainPane)).width, 380);
    await tester.drag(find.byKey(_divider), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(find.text('Single column'), findsOneWidget);
    expect(app.layout.value, CollapsedPane.main);
    await tester.tap(find.byKey(_divider));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(app.layout.value, isNull);
    expect(find.text('Two columns'), findsOneWidget);
    expect(tester.state<_ChatState>(find.byType(_Chat)), same(page));
    expect(
      app.router.routeInformationProvider.value.uri.path,
      '/rooms/settings/style',
    );
    expect(tester.takeException(), isNull);
  });
}
