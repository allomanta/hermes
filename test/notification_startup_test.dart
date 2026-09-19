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
import 'package:matrix/encryption/key_manager.dart';
import 'package:matrix/encryption/utils/key_verification.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Client extends Fake implements Client {
  @override
  String get clientName => 'account';
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
  final onNotification = CachedStreamController<Event>();
}

class _Matrix extends Matrix {
  const _Matrix({required super.clients, required super.store});

  @override
  MatrixState createState() => _MatrixState();
}

class _MatrixState extends MatrixState {
  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
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
}
