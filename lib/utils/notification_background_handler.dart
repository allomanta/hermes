import 'dart:convert';
import 'dart:ui';

import 'package:collection/collection.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hermes/l10n/l10n.dart';
import 'package:hermes/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:hermes/utils/platform_infos.dart';
import 'package:hermes/utils/push_helper.dart';
import '../config/app_config.dart';
import '../config/setting_keys.dart';
import 'package:hermes/utils/client_manager.dart';

bool _vodInitialized = false;

extension NotificationResponseJson on NotificationResponse {
  String toJsonString() => jsonEncode({
        'type': notificationResponseType.name,
        'id': id,
        'actionId': actionId,
        'input': input,
        'payload': payload,
        'data': data,
      });

  static NotificationResponse fromJsonString(String jsonString) {
    final json = jsonDecode(jsonString) as Map<String, Object?>;
    return NotificationResponse(
      notificationResponseType: NotificationResponseType.values
          .singleWhere((t) => t.name == json['type']),
      id: json['id'] as int?,
      actionId: json['actionId'] as String?,
      input: json['input'] as String?,
      payload: json['payload'] as String?,
      data: json['data'] as Map<String, dynamic>,
    );
  }
}

@pragma('vm:entry-point')
void notificationTapBackground(
  NotificationResponse notificationResponse,
) async {
  Logs().i('Notification tap in background');

  final sendPort = IsolateNameServer.lookupPortByName('background_tab_port');
  if (sendPort != null) {
    sendPort.send(notificationResponse.toJsonString());
    return;
  }

  if (!_vodInitialized) {
    await vod.init();
    _vodInitialized = true;
  }
  final store = await SharedPreferences.getInstance();
  final client = (await ClientManager.getClients(
    initialize: false,
    store: store,
  ))
      .first;
  await client.abortSync();
  await client.init(
    waitForFirstSync: false,
    waitUntilLoadCompletedLoaded: false,
  );

  AppConfig.sendPublicReadReceipts =
      store.getBool(SettingKeys.sendPublicReadReceipts) ??
          AppConfig.sendPublicReadReceipts;

  if (!client.isLogged()) {
    throw Exception('Notification tab in background but not logged in!');
  }
  try {
    await notificationTap(notificationResponse, client: client);
  } finally {
    await client.dispose(closeDatabase: false);
  }
  return;
}

Future<void> notificationTap(
  NotificationResponse notificationResponse, {
  GoRouter? router,
  required Client client,
  L10n? l10n,
}) async {
  Logs().d(
    'Notification action handler started',
    notificationResponse.notificationResponseType.name,
  );
  final payload =
      HermesPushPayload.fromString(notificationResponse.payload ?? '');
  switch (notificationResponse.notificationResponseType) {
    case NotificationResponseType.selectedNotification:
      final roomId = payload.roomId;
      if (roomId == null) return;

      if (router == null) {
        Logs().v('Ignore select notification action in background mode');
        return;
      }
      Logs().v('Open room from notification tap', roomId);
      await client.roomsLoading;
      await client.accountDataLoading;
      if (client.getRoomById(roomId) == null) {
        await client
            .waitForRoomInSync(roomId)
            .timeout(const Duration(seconds: 30));
      }
      router.go(
        client.getRoomById(roomId)?.membership == Membership.invite
            ? '/rooms'
            : '/rooms/$roomId',
      );
    case NotificationResponseType.selectedNotificationAction:
      final actionType = HermesNotificationActions.values.singleWhereOrNull(
        (action) => action.name == notificationResponse.actionId,
      );
      if (actionType == null) {
        throw Exception('Selected notification with action but no action ID');
      }
      final roomId = payload.roomId;
      if (roomId == null) {
        throw Exception('Selected notification with action but no payload');
      }
      await client.roomsLoading;
      await client.accountDataLoading;
      await client.userDeviceKeysLoading;
      final room = client.getRoomById(roomId);
      if (room == null) {
        throw Exception(
          'Selected notification with action but unknown room $roomId',
        );
      }
      switch (actionType) {
        case HermesNotificationActions.markAsRead:
          await room.setReadMarker(
            payload.eventId ?? room.lastEvent!.eventId,
            mRead: payload.eventId ?? room.lastEvent!.eventId,
            public: AppConfig.sendPublicReadReceipts,
          );
        case HermesNotificationActions.reply:
          final input = notificationResponse.input;
          if (input == null || input.isEmpty) {
            throw Exception(
              'Selected notification with reply action but without input',
            );
          }

          final eventId = await room.sendTextEvent(input);

          if (PlatformInfos.isAndroid) {
            final messagingStyleInformation =
                await AndroidFlutterLocalNotificationsPlugin()
                    .getActiveNotificationMessagingStyle(room.id.hashCode);
            if (messagingStyleInformation == null) return;
            l10n ??= await lookupL10n(const Locale('en'));
            messagingStyleInformation.messages?.add(
              Message(
                input,
                DateTime.now(),
                Person(key: room.client.userID, name: l10n.you),
              ),
            );

            await FlutterLocalNotificationsPlugin().show(
              room.id.hashCode,
              room.getLocalizedDisplayname(MatrixLocals(l10n)),
              input,
              NotificationDetails(
                android: AndroidNotificationDetails(
                  AppConfig.pushNotificationsChannelId,
                  l10n.incomingMessages,
                  category: AndroidNotificationCategory.message,
                  shortcutId: room.id,
                  styleInformation: messagingStyleInformation,
                  groupKey: room.id,
                  playSound: false,
                  enableVibration: false,
                  actions: <AndroidNotificationAction>[
                    AndroidNotificationAction(
                      HermesNotificationActions.reply.name,
                      l10n.reply,
                      inputs: [
                        AndroidNotificationActionInput(
                          label: l10n.writeAMessage,
                        ),
                      ],
                      cancelNotification: false,
                      allowGeneratedReplies: true,
                      semanticAction: SemanticAction.reply,
                    ),
                    AndroidNotificationAction(
                      HermesNotificationActions.markAsRead.name,
                      l10n.markAsRead,
                      semanticAction: SemanticAction.markAsRead,
                    ),
                  ],
                ),
              ),
              payload: HermesPushPayload(
                client.clientName,
                room.id,
                eventId,
              ).toString(),
            );
          }
      }
  }
}

enum HermesNotificationActions { markAsRead, reply }
