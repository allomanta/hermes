// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:hermes/utils/android_share_shortcuts.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

class AndroidIncomingShare {
  final String id;
  final List<SharedMediaFile> files;
  final ({String clientName, String roomId})? target;
  final String? error;

  AndroidIncomingShare.fromMap(Map value)
    : id = value['id'] as String,
      files = (value['files'] as List)
          .map(
            (file) =>
                SharedMediaFile.fromMap(Map<String, dynamic>.from(file as Map)),
          )
          .toList(),
      target = AndroidShareShortcuts.parseShortcut(
        value['shortcutId'] as String?,
      ),
      error = value['error'] as String?;
}

abstract class AndroidIncomingShares {
  static const _channel = MethodChannel('im.hermes.hermes/incoming_shares');
  static const _timeout = Duration(seconds: 10);
  static final _changes = StreamController<void>.broadcast();
  static final _claims = <String, Object>{};
  static final _completed = <String>{};

  static Stream<void> get changes {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'sharesChanged') _changes.add(null);
    });
    return _changes.stream;
  }

  static Future<List<AndroidIncomingShare>> getPending() async {
    final values =
        await _channel
            .invokeListMethod<dynamic>('getPendingShares')
            .timeout(_timeout) ??
        [];
    final shares = <AndroidIncomingShare>[];
    for (final value in values) {
      final share = AndroidIncomingShare.fromMap(value as Map);
      if (_completed.contains(share.id)) {
        await _channel
            .invokeMethod<void>('completeShare', share.id)
            .timeout(_timeout);
      } else {
        shares.add(share);
      }
    }
    return shares;
  }

  static Object? claim(String id) {
    if (_claims.containsKey(id) || _completed.contains(id)) return null;
    return _claims[id] = Object();
  }

  static void release(String id, Object lease, {bool notify = false}) {
    if (!identical(_claims[id], lease)) return;
    _claims.remove(id);
    if (notify) _changes.add(null);
  }

  static Future<void> complete(String id, Object lease) async {
    if (!identical(_claims[id], lease)) return;
    _completed.add(id);
    if (_completed.length > 128) _completed.remove(_completed.first);
    _claims.remove(id);
    await _channel.invokeMethod<void>('completeShare', id).timeout(_timeout);
  }
}
