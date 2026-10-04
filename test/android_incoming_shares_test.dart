// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes/l10n/l10n.dart';
import 'package:hermes/pages/chat_list/chat_list.dart';
import 'package:hermes/utils/android_incoming_shares.dart';
import 'package:hermes/widgets/matrix.dart';
import 'package:hermes/widgets/share_scaffold_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:provider/provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Client extends Fake implements Client {
  @override
  String get clientName => 'account';
  @override
  bool isLogged() => true;
  @override
  Future<void>? roomsLoading;
  final roomsById = <String, Room>{};
  @override
  List<Room> get rooms => roomsById.values.toList();
  @override
  final onSync = CachedStreamController<SyncUpdate>();
  @override
  Room? getRoomById(String id) => roomsById[id];
}

class _Room extends Fake implements Room {
  _Room(this.client, this.id) {
    client.roomsById[id] = this;
  }
  @override
  final _Client client;
  @override
  final String id;
  @override
  bool get isSpace => false;
  @override
  Membership get membership => Membership.join;
  @override
  bool get canSendDefaultMessages => true;
  @override
  String get name => 'Target chat';
  @override
  Uri? get avatar => null;
  @override
  String? get directChatMatrixID => '@friend:example.org';
  @override
  String getLocalizedDisplayname([
    MatrixLocalizations i18n = const MatrixDefaultLocalizations(),
  ]) => name;
}

class _Matrix extends Fake with Diagnosticable implements MatrixState {
  _Matrix(this.client, SharedPreferences store)
    : widget = Matrix(clients: [client], store: store);
  @override
  final _Client client;
  @override
  final Matrix widget;
}

// Mount the production delivery method without unrelated startup services.
class _ChatList extends ChatList {
  const _ChatList() : super(activeChat: null);
  @override
  ChatListController createState() => _Controller();
}

class _Controller extends ChatListController {
  @override
  // ignore: must_call_super
  void initState() {
    activeFilter = ActiveFilter.allChats;
  }

  @override
  // ignore: must_call_super
  void didChangeDependencies() {}
  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('Chat list'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('im.hermes.hermes/incoming_shares');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  var pending = <Map<String, Object?>>[];
  var failAck = false;

  Map<String, Object?> packet(
    String id,
    String account,
    String room,
    String file,
  ) => {
    'id': id,
    'shortcutId': 'hermes-share:${jsonEncode([account, room])}',
    'files': [
      {'path': file, 'type': 'image', 'mimeType': 'image/jpeg'},
    ],
  };

  setUp(() {
    calls.clear();
    pending = [];
    failAck = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getPendingShares') return pending;
      if (call.method == 'completeShare') {
        if (failAck) throw PlatformException(code: 'detached');
        pending.removeWhere((share) => share['id'] == call.arguments);
      }
      return null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'each queued payload stays paired with its own quick-share destination',
    () async {
      pending = [
        packet('pair-1', 'first', '!one', '/cache/1/photo.jpg'),
        packet('pair-2', 'second', '!two', '/cache/2/photo.jpg'),
      ];
      final shares = await AndroidIncomingShares.getPending();
      expect(shares.map((share) => share.target?.clientName), [
        'first',
        'second',
      ]);
      expect(shares.map((share) => share.target?.roomId), ['!one', '!two']);
      expect(shares.map((share) => share.files.single.path), [
        '/cache/1/photo.jpg',
        '/cache/2/photo.jpg',
      ]);
      expect(calls.map((call) => call.method), ['getPendingShares']);
    },
  );

  test(
    'a disposed owner cannot release or acknowledge a replacement owner',
    () async {
      final old = AndroidIncomingShares.claim('handoff')!;
      expect(AndroidIncomingShares.claim('handoff'), isNull);
      AndroidIncomingShares.release('handoff', old);
      final current = AndroidIncomingShares.claim('handoff')!;
      AndroidIncomingShares.release('handoff', old);
      await AndroidIncomingShares.complete('handoff', old);
      expect(calls, isEmpty);
      expect(AndroidIncomingShares.claim('handoff'), isNull);
      await AndroidIncomingShares.complete('handoff', current);
      expect(calls.single.arguments, 'handoff');
      expect(AndroidIncomingShares.claim('handoff'), isNull);
    },
  );

  test(
    'acknowledgement failure is retried without presenting a share twice',
    () async {
      pending = [packet('ack-retry', 'account', '!room', '/cache/photo.jpg')];
      final lease = AndroidIncomingShares.claim('ack-retry')!;
      failAck = true;
      await expectLater(
        AndroidIncomingShares.complete('ack-retry', lease),
        throwsA(isA<PlatformException>()),
      );
      failAck = false;
      expect(await AndroidIncomingShares.getPending(), isEmpty);
      expect(pending, isEmpty);
      expect(
        calls.where((call) => call.method == 'completeShare'),
        hasLength(2),
      );
    },
  );

  test('an empty launch lookup cannot clear a later arriving share', () async {
    expect(await AndroidIncomingShares.getPending(), isEmpty);
    pending = [packet('late-launch', 'account', '!room', '/cache/photo.jpg')];
    expect((await AndroidIncomingShares.getPending()).single.id, 'late-launch');
    expect(
      calls.any(
        (call) => call.method == 'completeShare' || call.method == 'reset',
      ),
      isFalse,
    );
  });

  for (final alreadyOpen in [false, true]) {
    testWidgets(
      alreadyOpen
          ? 'sharing to the current chat delivers fresh route extras'
          : 'startup navigation during room loading does not discard a share',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final store = await SharedPreferences.getInstance();
        final client = _Client();
        final room = _Room(client, '!target');
        final ready = Completer<void>();
        client.roomsLoading = ready.future;
        List<ShareItem>? delivered;
        final router = GoRouter(
          initialLocation: alreadyOpen
              ? '/rooms/!target?client=account&body=old-share'
              : '/rooms',
          routes: [
            GoRoute(
              path: '/rooms',
              builder: (context, state) => const _ChatList(),
              routes: [
                GoRoute(
                  path: ':roomid',
                  builder: (context, state) {
                    if (state.extra is List<ShareItem>) {
                      delivered = state.extra as List<ShareItem>;
                    }
                    return const Scaffold(body: Text('Chat'));
                  },
                ),
              ],
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
        final controller = tester.state<ChatListController>(
          find.byType(_ChatList, skipOffstage: false),
        );
        final receipt = controller.handleIncomingSharedMedia(
          [
            SharedMediaFile(
              path: '/cache/photo.jpg',
              type: SharedMediaType.image,
              mimeType: 'image/jpeg',
            ),
          ],
          target: (clientName: client.clientName, roomId: room.id),
        );
        await tester.pump(const Duration(milliseconds: 1));
        if (!alreadyOpen) {
          router.go('/rooms/startup-restored-chat');
          await tester.pumpAndSettle();
        }
        ready.complete();
        await tester.pumpAndSettle();
        expect(await receipt, isTrue);
        expect(
          router.routeInformationProvider.value.uri.path,
          '/rooms/!target',
        );
        expect(router.routeInformationProvider.value.uri.queryParameters, {
          'client': 'account',
        });
        expect(
          (delivered!.single as FileShareItem).value.path,
          '/cache/photo.jpg',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'generic shares replace the old picker, update on sync, and forward safely',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final client = _Client();
      final store = await SharedPreferences.getInstance();
      List<ShareItem>? delivered;
      final router = GoRouter(
        initialLocation: '/rooms',
        routes: [
          GoRoute(
            path: '/rooms',
            builder: (_, _) => const _ChatList(),
            routes: [
              GoRoute(
                path: ':roomid',
                builder: (_, state) {
                  delivered = state.extra as List<ShareItem>?;
                  return const Scaffold(body: Text('Chat'));
                },
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      addTearDown(client.onSync.close);
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
      final controller = tester.state<ChatListController>(
        find.byType(_ChatList),
      );
      for (final name in ['first.jpg', 'second.jpg']) {
        final opened = controller.handleIncomingSharedMedia([
          SharedMediaFile(path: '/cache/$name', type: SharedMediaType.image),
        ]);
        await tester.pumpAndSettle();
        expect(await opened, isTrue);
        expect(find.byType(ShareScaffoldDialog), findsOneWidget);
        expect(
          (tester
                      .widget<ShareScaffoldDialog>(
                        find.byType(ShareScaffoldDialog),
                      )
                      .items
                      .single
                  as FileShareItem)
              .value
              .name,
          name,
        );
      }
      _Room(client, '!target');
      client.onSync.add(SyncUpdate(nextBatch: 'ready'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Target chat'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Forward'));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/rooms/!target');
      expect((delivered!.single as FileShareItem).value.name, 'second.jpg');
      expect(find.byType(ShareScaffoldDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
