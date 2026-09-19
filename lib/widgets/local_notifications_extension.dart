// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:hermes/config/setting_keys.dart';
import 'package:hermes/l10n/l10n.dart';
import 'package:hermes/utils/client_download_content_extension.dart';
import 'package:hermes/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:hermes/utils/notification_background_handler.dart';
import 'package:hermes/utils/push_helper.dart';
import 'package:hermes/widgets/hermes_app.dart';
import 'package:hermes/widgets/incoming_call_dialog.dart';
import 'package:hermes/widgets/matrix.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:universal_html/html.dart' as html;

extension LocalNotificationsExtension on MatrixState {
  static final html.AudioElement _audioPlayer = html.AudioElement()
    ..src = 'assets/assets/sounds/notification.mp3'
    ..load();

  Future<void> showLocalNotification(Event event) async {
    if (!mounted) return;
    Logs().v(
      '[Notifications] event received for ${event.room.id} (${event.type})',
    );
    if (event.type == RtcNotificationContent.eventType &&
        event.tryParseRtcNotificationContent()?.notificationType == .ring) {
      final context =
          HermesApp.router.routerDelegate.navigatorKey.currentContext ??
          this.context;
      showDialog<bool>(
        context: context,
        builder: (_) => IncomingCallDialog(event: event),
      ).then((joinCall) {
        if (joinCall != true) return;
        if (!context.mounted) return;
        setActiveClient(event.room.client);
        HermesApp.router.go('/rooms/${event.room.id}?action=call');
      });
    }

    final l10n = L10n.of(context);
    final roomId = event.room.id;
    final notificationClient = event.room.client;
    bool roomIsVisible() =>
        notificationClient == client &&
        activeRoomId == roomId &&
        (kIsWeb
            ? webHasFocus
            : WidgetsBinding.instance.lifecycleState ==
                  AppLifecycleState.resumed);
    if (roomIsVisible()) return;

    final title = event.room.getLocalizedDisplayname(
      MatrixLocals(L10n.of(context)),
    );
    final body = await event.calcLocalizedBody(
      MatrixLocals(L10n.of(context)),
      withSenderNamePrefix:
          !event.room.isDirectChat ||
          event.room.lastEvent?.senderId == notificationClient.userID,
      plaintextBody: true,
      hideReply: true,
      hideEdit: true,
      removeMarkdown: true,
    );
    final avatarUrl = event.room.avatar;

    const size = 128;
    const thumbnailMethod = ThumbnailMethod.crop;

    if (kIsWeb && avatarUrl != null) {
      // Pre-cache so that we can later just set the thumbnail uri as icon:
      try {
        await notificationClient.downloadMxcCached(
          avatarUrl,
          width: size,
          height: size,
          thumbnailMethod: thumbnailMethod,
          isThumbnail: true,
          rounded: true,
        );
      } catch (e, s) {
        Logs().d('Unable to pre-download avatar for web notification', e, s);
      }
    }

    if (!mounted || roomIsVisible()) return;
    final notificationId = '${notificationClient.clientName}_$roomId'.hashCode;
    if (kIsWeb) {
      final thumbnailUri = await avatarUrl?.getThumbnailUri(
        notificationClient,
        width: size,
        height: size,
        method: thumbnailMethod,
      );

      if (AppSettings.webNotificationSound.value) _audioPlayer.play();

      trackedRoomNotifications[notificationId]?.close?.call();
      final notification = html.Notification(
        title,
        body: body,
        icon: thumbnailUri?.toString(),
        tag: '${notificationClient.clientName}_$roomId',
      );
      trackedRoomNotifications[notificationId] = (
        clientName: notificationClient.clientName,
        roomId: roomId,
        close: notification.close,
      );
      return;
    }

    await FlutterLocalNotificationsPlugin().show(
      id: notificationId,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        macOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          presentBadge: true,
          interruptionLevel: InterruptionLevel.timeSensitive,
        ),
        linux: LinuxNotificationDetails(
          sound: ThemeLinuxSound('message-new-instant'),
          actions: switch (event.type) {
            EventTypes.Message ||
            EventTypes.Encrypted ||
            EventTypes.Sticker => [
              LinuxNotificationAction(
                key: HermesNotificationActions.markAsRead.name,
                label: l10n.markAsRead,
              ),
              LinuxNotificationAction(
                key: HermesNotificationActions.mute.name,
                label: l10n.mute,
              ),
            ],
            RtcNotificationContent.eventType => [
              LinuxNotificationAction(
                key: HermesNotificationActions.enterCall.name,
                label: l10n.enterCall,
              ),
            ],
            _ => [],
          },
        ),
      ),
      payload: HermesPushPayload(
        notificationClient.clientName,
        event.room.id,
        event.eventId,
      ).toString(),
    );
    trackedRoomNotifications[notificationId] = (
      clientName: notificationClient.clientName,
      roomId: roomId,
      close: null,
    );
  }
}
