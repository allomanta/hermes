// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:hermes/config/setting_keys.dart';
import 'package:hermes/l10n/l10n.dart';
import 'package:hermes/utils/client_download_content_extension.dart';
import 'package:hermes/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:hermes/utils/notification_background_handler.dart';
import 'package:hermes/utils/platform_infos.dart';
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
    if (activeRoomId == roomId) {
      if (kIsWeb && webHasFocus) return;
      if (!kIsWeb &&
          !PlatformInfos.isMacOS &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        return;
      }
    }

    final title = event.room.getLocalizedDisplayname(
      MatrixLocals(L10n.of(context)),
    );
    final body = await event.calcLocalizedBody(
      MatrixLocals(L10n.of(context)),
      withSenderNamePrefix:
          !event.room.isDirectChat ||
          event.room.lastEvent?.senderId == client.userID,
      plaintextBody: true,
      hideReply: true,
      hideEdit: true,
      removeMarkdown: true,
    );
    final avatarUrl = event.room.avatar;

    const size = 128;
    const thumbnailMethod = ThumbnailMethod.crop;

    if (avatarUrl != null) {
      // Pre-cache so that we can later just set the thumbnail uri as icon:
      try {
        await client.downloadMxcCached(
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

    if (kIsWeb) {
      final thumbnailUri = await avatarUrl?.getThumbnailUri(
        client,
        width: size,
        height: size,
        method: thumbnailMethod,
      );

      if (AppSettings.webNotificationSound.value) _audioPlayer.play();

      html.Notification(
        title,
        body: body,
        icon: thumbnailUri?.toString(),
        tag: event.room.id,
      );
      return;
    }

    FlutterLocalNotificationsPlugin().show(
      id: event.room.id.hashCode,
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
        client.clientName,
        event.room.id,
        event.eventId,
      ).toString(),
    );
  }
}
