// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/widgets/matrix.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/encryption/key_manager.dart';
import 'package:matrix/encryption/utils/key_verification.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Client extends Fake implements Client {
  _Client([this.clientName = 'account']);
  @override
  final String clientName;
  @override
  final onRoomKeyRequest = CachedStreamController<RoomKeyRequest>();
  @override
  final onKeyVerificationRequest = CachedStreamController<KeyVerification>();
  @override
  final onLoginStateChanged = CachedStreamController<LoginState>();
  @override
  final onUiaRequest = CachedStreamController<UiaRequest>();
  @override
  final onSync = CachedStreamController<SyncUpdate>();
  @override
  final onSyncStatus = CachedStreamController<SyncStatusUpdate>();
  @override
  final onNotification = CachedStreamController<Event>();
}

class _ClosableClient extends http.BaseClient {
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      throw UnimplementedError();

  @override
  void close() => closed = true;
}

class _StalledClient extends _Client {
  _StalledClient(this.transport) {
    _httpClient = FixedTimeoutHttpClient(
      transport,
      const Duration(minutes: 30),
    );
  }

  final _ClosableClient transport;
  late http.Client _httpClient;
  @override
  http.Client get httpClient => _httpClient;
  @override
  set httpClient(http.Client client) => _httpClient = client;
  int aborts = 0;
  bool restarted = false;

  @override
  bool isLogged() => true;

  @override
  Future<void> abortSync() async {
    aborts++;
  }

  @override
  set backgroundSync(bool enabled) => restarted = enabled;
}

class _Matrix extends Matrix {
  final ValueChanged<NotificationResponse>? onResponse;
  const _Matrix({
    required super.clients,
    required super.store,
    this.onResponse,
  });

  @override
  MatrixState createState() => _MatrixState();
}

class _MatrixState extends MatrixState {
  @override
  Future<void> handleNotificationResponse(NotificationResponse response) {
    (widget as _Matrix).onResponse?.call(response);
    return Future<void>.value();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  testWidgets('desktop restarts a stalled sync with a fresh HTTP client', (
    tester,
  ) async {
    MacOSFlutterLocalNotificationsPlugin.registerWith();
    SharedPreferences.setMockInitialValues({});
    final store = await SharedPreferences.getInstance();
    final transport = _ClosableClient();
    final client = _StalledClient(transport);
    addTearDown(() async {
      if (client.httpClient is TimeoutHttpClient) {
        (client.httpClient as TimeoutHttpClient).inner.close();
      }
      await Future.wait([
        client.onRoomKeyRequest.close(),
        client.onKeyVerificationRequest.close(),
        client.onLoginStateChanged.close(),
        client.onUiaRequest.close(),
        client.onSync.close(),
        client.onSyncStatus.close(),
        client.onNotification.close(),
      ]);
    });
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'initialize' ? true : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    await tester.pumpWidget(_Matrix(clients: [client], store: store));
    final state = tester.state<MatrixState>(find.byType(_Matrix));
    final oldHttpClient = client.httpClient;
    client.onSync.add(SyncUpdate(nextBatch: 'initial'));
    await tester.pump();
    state.checkDesktopSync(DateTime.now());
    expect(client.aborts, 0);
    client.onSyncStatus.add(const SyncStatusUpdate(SyncStatus.finished));
    await tester.pump();
    state.checkDesktopSync(DateTime.now().add(const Duration(minutes: 4)));
    expect(client.aborts, 0);

    state.checkDesktopSync(DateTime.now().add(const Duration(minutes: 6)));
    await tester.pump();
    expect(client.aborts, 1);
    expect(transport.closed, isTrue);
    expect(client.restarted, isTrue);
    expect(client.httpClient, isNot(same(oldHttpClient)));
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  for (final disposeBeforeReady in [false, true]) {
    testWidgets(
      disposeBeforeReady
          ? 'macOS does not attach notification listeners after disposal'
          : 'macOS waits for plugin initialization and sync, then cancels on disposal',
      (tester) async {
        MacOSFlutterLocalNotificationsPlugin.registerWith();
        SharedPreferences.setMockInitialValues({});
        final store = await SharedPreferences.getInstance();
        final client = _Client();
        addTearDown(() async {
          await Future.wait([
            client.onRoomKeyRequest.close(),
            client.onKeyVerificationRequest.close(),
            client.onLoginStateChanged.close(),
            client.onUiaRequest.close(),
            client.onSync.close(),
            client.onSyncStatus.close(),
            client.onNotification.close(),
          ]);
        });
        final initialized = Completer<bool>();
        final calls = <MethodCall>[];
        const channel = MethodChannel(
          'dexterous.com/flutter/local_notifications',
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            calls.add(call);
            return call.method == 'initialize' ? initialized.future : null;
          },
        );
        addTearDown(() {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          );
        });

        await tester.pumpWidget(_Matrix(clients: [client], store: store));
        final state = tester.state<MatrixState>(find.byType(_Matrix));
        client.onSync.add(SyncUpdate(nextBatch: 'initial'));
        await tester.pump();
        expect(
          calls.where((call) => call.method == 'initialize'),
          hasLength(1),
        );
        expect(state.onNotification, isEmpty);

        if (disposeBeforeReady) await tester.pumpWidget(const SizedBox());
        initialized.complete(true);
        await tester.pump();
        expect(
          calls.where(
            (call) => call.method == 'getNotificationAppLaunchDetails',
          ),
          hasLength(disposeBeforeReady ? 0 : 1),
        );
        if (disposeBeforeReady) {
          expect(state.onNotification, isEmpty);
        } else {
          expect(state.onNotification.keys, ['account']);
          await tester.pumpWidget(const SizedBox());
          expect(state.onNotification, isEmpty);
        }
        expect(tester.takeException(), isNull);
      },
      skip: !Platform.isMacOS,
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }

  testWidgets(
    'macOS dispatches the cold-start response once across accounts and remounts',
    (tester) async {
      MacOSFlutterLocalNotificationsPlugin.registerWith();
      SharedPreferences.setMockInitialValues({});
      final store = await SharedPreferences.getInstance();
      final clients = [_Client('first'), _Client('second')];
      addTearDown(() async {
        for (final client in clients) {
          await Future.wait([
            client.onRoomKeyRequest.close(),
            client.onKeyVerificationRequest.close(),
            client.onLoginStateChanged.close(),
            client.onUiaRequest.close(),
            client.onSync.close(),
            client.onSyncStatus.close(),
            client.onNotification.close(),
          ]);
        }
      });
      const channel = MethodChannel(
        'dexterous.com/flutter/local_notifications',
      );
      final firstQuery = Completer<Map<String, Object?>>();
      var queries = 0;
      final responses = <NotificationResponse>[];
      final launchDetails = <String, Object?>{
        'notificationLaunchedApp': true,
        'notificationResponse': {
          'notificationId': 42,
          'notificationResponseType': 0,
          'payload': r'second|!room:example.org|$event',
        },
      };
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'initialize') return true;
        if (call.method == 'getNotificationAppLaunchDetails') {
          queries++;
          return queries == 1 ? firstQuery.future : launchDetails;
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final widget = _Matrix(
        clients: clients,
        store: store,
        onResponse: responses.add,
      );

      await tester.pumpWidget(widget);
      await tester.pump();
      expect(queries, 1);
      await tester.pumpWidget(const SizedBox());
      firstQuery.complete(launchDetails);
      await tester.pumpAndSettle();
      expect(responses, isEmpty);

      await tester.pumpWidget(widget);
      await tester.pumpAndSettle();
      expect(queries, 2);
      expect(responses, hasLength(1));
      expect(responses.single.payload, r'second|!room:example.org|$event');
      expect(
        responses.single.notificationResponseType,
        NotificationResponseType.selectedNotification,
      );

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(widget);
      await tester.pumpAndSettle();
      expect(queries, 2);
      expect(responses, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      // Resolve the initial-sync waiters after disposal; none may attach listeners.
      for (final client in clients) {
        client.onSync.add(SyncUpdate(nextBatch: 'initial'));
      }
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
    skip: !Platform.isMacOS,
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
