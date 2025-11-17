import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart';

import 'package:hermes/config/app_config.dart';
import 'package:hermes/utils/client_download_content_extension.dart';
import 'package:hermes/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:hermes/utils/platform_infos.dart';

class AndroidShareShortcuts {
  static const _channel =
      MethodChannel('im.hermes.hermes/direct_share_shortcuts');
  static const _maxShortcuts = 10;

  static final Map<String, String?> _avatarCache = <String, String?>{};
  static Client? _latestClient;
  static MatrixLocals? _latestLocals;
  static bool _isPublishing = false;
  static bool _publishQueued = false;

  static Future<void> schedulePublish(
    Client client,
    MatrixLocals locals,
  ) async {
    if (!PlatformInfos.isAndroid) return;
    _latestClient = client;
    _latestLocals = locals;
    if (_isPublishing) {
      _publishQueued = true;
      return;
    }
    _publishQueued = false;
    _isPublishing = true;
    try {
      await _publishCurrentSelection();
      while (_publishQueued) {
        _publishQueued = false;
        await _publishCurrentSelection();
      }
    } finally {
      _isPublishing = false;
    }
  }

  static Future<void> _publishCurrentSelection() async {
    final client = _latestClient;
    final locals = _latestLocals;
    if (client == null || locals == null) return;

    await client.roomsLoading;
    final rooms = client.rooms
        .where(
          (room) =>
              room.membership == Membership.join &&
              !room.isSpace &&
              room.canSendDefaultMessages,
        )
        .toList()
      ..sort(
        (a, b) {
          final bTs = _roomTimestamp(b);
          final aTs = _roomTimestamp(a);
          return bTs.compareTo(aTs);
        },
      );

    final shortcuts = <Map<String, dynamic>>[];
    for (final room in rooms.take(_maxShortcuts)) {
      final label = room.getLocalizedDisplayname(locals);
      shortcuts.add({
        'id': room.id,
        'shortLabel': label,
        'longLabel': label,
        'action': AppConfig.inviteLinkPrefix + room.id,
        'icon': await _loadAvatar(room),
        'isImportant': room.isFavourite,
        'isBot': false,
        'isConversation': true,
      });
    }

    try {
      await _channel.invokeMethod('publishShareShortcuts', shortcuts);
    } on PlatformException catch (error, stackTrace) {
      debugPrint('Failed to publish Android share shortcuts: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  static Future<String?> _loadAvatar(Room room) async {
    final avatar = room.avatar;
    if (avatar == null) return null;
    final cacheKey = '${room.id}_${avatar.hashCode}';
    if (_avatarCache.containsKey(cacheKey)) {
      return _avatarCache[cacheKey];
    }
    try {
      final bytes = await room.client
          .downloadMxcCached(
            avatar,
            width: 192,
            height: 192,
            thumbnailMethod: ThumbnailMethod.crop,
            animated: false,
            isThumbnail: true,
            rounded: true,
          )
          .timeout(const Duration(seconds: 3));
      final encoded = base64Encode(bytes);
      _avatarCache[cacheKey] = encoded;
      return encoded;
    } catch (error, stackTrace) {
      debugPrint('Failed to load shortcut avatar: $error');
      debugPrintStack(stackTrace: stackTrace);
      _avatarCache[cacheKey] = null;
      return null;
    }
  }

  static Future<void> clear() async {
    if (!PlatformInfos.isAndroid) return;
    try {
      await _channel.invokeMethod('clearShareShortcuts');
      _avatarCache.clear();
    } on PlatformException catch (error, stackTrace) {
      debugPrint('Failed to clear Android share shortcuts: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  static Future<String?> takePendingShortcutRoomId() async {
    if (!PlatformInfos.isAndroid) return null;
    try {
      final roomId =
          await _channel.invokeMethod<String>('takePendingShortcutRoomId');
      if (roomId == null || roomId.isEmpty) {
        return null;
      }
      return roomId;
    } on PlatformException catch (error, stackTrace) {
      debugPrint('Failed to obtain pending Direct Share shortcut: $error');
      debugPrintStack(stackTrace: stackTrace);
      return null;
    }
  }

  static int _roomTimestamp(Room room) {
    final Object? timestamp = room.lastEvent?.originServerTs;
    if (timestamp is int) {
      return timestamp;
    }
    if (timestamp is DateTime) {
      return timestamp.millisecondsSinceEpoch;
    }
    return 0;
  }
}
