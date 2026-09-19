import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hermes/config/app_config.dart';
import 'package:hermes/utils/client_download_content_extension.dart';
import 'package:hermes/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AndroidShareShortcuts {
  static const _channel = MethodChannel(
    'im.hermes.hermes/direct_share_shortcuts',
  );
  static const _maxShortcuts = 5;
  static const _historyKey = 'im.hermes.direct_share.recent';
  static const _idPrefix = 'hermes-share:';

  static final Map<String, String> _avatarCache = {};
  static List<Client> _latestClients = [];
  static MatrixLocals? _latestLocals;
  static bool _isPublishing = false;
  static bool _publishQueued = false;
  static int _generation = 0;
  static Completer<void> _invalidated = Completer<void>();
  static String? _lastPublishedSignature;
  static final Set<String> _pendingUsage = {};

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static String _shortcutId(Room room) =>
      '$_idPrefix${jsonEncode([room.client.clientName, room.id])}';

  static int _invalidatePublication() {
    _invalidated.complete();
    _invalidated = Completer<void>();
    return ++_generation;
  }

  /// Record only a successfully sent share, never opening a preview or receiving
  /// a message. Persist the order so startup does not replace it with sync order.
  static Future<void> recordShare(Room room) async {
    if (!_supported) return;
    try {
      final store = await SharedPreferences.getInstance();
      if (!_latestClients.contains(room.client) || !room.client.isLogged()) {
        return;
      }
      final id = _shortcutId(room);
      final recent = store.getStringList(_historyKey) ?? [];
      recent.remove(id);
      recent.insert(0, id);
      final saved = store.setStringList(
        _historyKey,
        recent.take(_maxShortcuts).toList(),
      );
      _pendingUsage.add(id);
      final generation = _invalidatePublication();
      await saved;
      final locals = _latestLocals;
      if (generation != _generation || locals == null) return;
      await schedulePublish(_latestClients, locals);
    } catch (error, stackTrace) {
      debugPrint('Failed to record Android share shortcut: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  static Future<void> schedulePublish(
    List<Client> clients,
    MatrixLocals locals,
  ) async {
    if (!_supported) return;
    _latestClients = clients.where((client) => client.isLogged()).toList();
    _latestLocals = locals;
    _invalidatePublication();
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
    } catch (error, stackTrace) {
      debugPrint('Failed to publish Android share shortcuts: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _isPublishing = false;
    }
  }

  static Future<void> _publishCurrentSelection() async {
    final clients = _latestClients;
    final locals = _latestLocals;
    final generation = _generation;
    final invalidated = _invalidated.future;
    if (locals == null) return;

    final store = await SharedPreferences.getInstance();
    await Future.any([
      Future.wait(clients.map((client) async => await client.roomsLoading)),
      invalidated,
    ]);
    if (generation != _generation) return;
    final rooms = {
      for (final client in clients)
        if (client.isLogged())
          for (final room in client.rooms)
            if (room.membership == Membership.join &&
                !room.isSpace &&
                room.canSendDefaultMessages)
              _shortcutId(room): room,
    };
    final selected = (store.getStringList(_historyKey) ?? [])
        .where(rooms.containsKey)
        .take(_maxShortcuts)
        .toList();
    final shortcuts = await Future.wait(
      selected.map((id) async {
        final room = rooms[id]!;
        final label = room.getLocalizedDisplayname(locals);
        return <String, dynamic>{
          'id': id,
          'shortLabel': label,
          'longLabel': label,
          'action': AppConfig.inviteLinkPrefix + room.id,
          'icon': await _loadAvatar(room, generation),
          'isBot': false,
          'isConversation': true,
        };
      }),
    );
    if (generation != _generation) return;

    final signature = jsonEncode(shortcuts);
    if (signature != _lastPublishedSignature) {
      // Send empty selections too: native shortcuts survive process restarts.
      final published = await _channel.invokeMethod<bool>(
        'publishShareShortcuts',
        shortcuts,
      );
      if (generation != _generation || published != true) return;
      _lastPublishedSignature = signature;
    }
    for (final id in selected.where(_pendingUsage.contains).toList()) {
      await _channel.invokeMethod('reportShareShortcutUsed', id);
      if (generation != _generation) return;
      _pendingUsage.remove(id);
    }
    _pendingUsage.retainAll(selected);
  }

  static Future<String?> _loadAvatar(Room room, int generation) async {
    final avatar = room.avatar;
    if (avatar == null) return null;
    final cacheKey = jsonEncode([room.client.clientName, avatar.toString()]);
    final cached = _avatarCache.remove(cacheKey);
    if (cached != null) {
      _avatarCache[cacheKey] = cached;
      return cached;
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
      if (generation == _generation) {
        _avatarCache[cacheKey] = encoded;
        while (_avatarCache.length > _maxShortcuts) {
          _avatarCache.remove(_avatarCache.keys.first);
        }
      }
      return encoded;
    } catch (error, stackTrace) {
      debugPrint('Failed to load shortcut avatar: $error');
      debugPrintStack(stackTrace: stackTrace);
      // Retry on a later refresh instead of permanently caching a failed fetch.
      return null;
    }
  }

  static Future<void> clear({String? clientName}) async {
    if (!_supported) return;
    final locals = _latestLocals;
    _latestClients = clientName == null
        ? []
        : _latestClients.where((c) => c.clientName != clientName).toList();
    final generation = _invalidatePublication();
    _publishQueued = false;
    _avatarCache.clear();
    _lastPublishedSignature = null;
    _pendingUsage.clear();
    try {
      await _channel.invokeMethod('clearShareShortcuts');
      if (clientName != null) {
        final store = await SharedPreferences.getInstance();
        final prefix = '$_idPrefix[${jsonEncode(clientName)},';
        final recent = store.getStringList(_historyKey) ?? [];
        await store.setStringList(
          _historyKey,
          recent.where((id) => !id.startsWith(prefix)).toList(),
        );
      }
      if (generation == _generation &&
          _latestClients.isNotEmpty &&
          locals != null) {
        await schedulePublish(_latestClients, locals);
      }
    } catch (error, stackTrace) {
      debugPrint('Failed to clear Android share shortcuts: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  static Future<({String clientName, String roomId})?>
  takePendingShortcut() async {
    if (!_supported) return null;
    try {
      final id = await _channel.invokeMethod<String>('takePendingShortcut');
      if (id == null || !id.startsWith(_idPrefix)) return null;
      final target = jsonDecode(id.substring(_idPrefix.length));
      if (target case [final String clientName, final String roomId]) {
        if (clientName.isNotEmpty && roomId.isNotEmpty) {
          return (clientName: clientName, roomId: roomId);
        }
      }
    } catch (error, stackTrace) {
      debugPrint('Failed to obtain pending Direct Share shortcut: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
    return null;
  }
}
