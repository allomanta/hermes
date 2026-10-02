// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/utils/matrix_sdk_extensions/event_read_receipts_extension.dart';
import 'package:matrix/matrix.dart';

class _Client extends Fake implements Client {
  @override
  String get userID => '@me:example.org';
}

class _Room extends Fake implements Room {
  @override
  String get id => '!room:example.org';
  @override
  final client = _Client();
  @override
  final receiptState = LatestReceiptState.empty();
  @override
  User unsafeGetUserFromMemoryOrFallback(String id) => User(id, room: this);
}

class _Timeline extends Fake implements Timeline {
  _Timeline(this.room, this.events);
  @override
  final Room room;
  @override
  final List<Event> events;
}

Event _event(Room room, String id, {String? threadId}) => Event(
  room: room,
  eventId: id,
  senderId: '@sender:example.org',
  originServerTs: DateTime(2026),
  type: EventTypes.Message,
  content: {
    'msgtype': MessageTypes.Text,
    'body': id,
    if (threadId != null)
      'm.relates_to': {
        'rel_type': RelationshipTypes.thread,
        'event_id': threadId,
      },
  },
);

void main() {
  test('merges exact receipts and excludes the sender and current account', () {
    final room = _Room();
    final event = _event(room, r'$target');
    room.receiptState.global.otherUsers.addAll({
      '@alice:example.org': LatestReceiptStateData(event.eventId, 1000),
      '@me:example.org': LatestReceiptStateData(event.eventId, 2000),
      '@sender:example.org': LatestReceiptStateData(event.eventId, 3000),
    });
    room.receiptState.mainThread = LatestReceiptStateForTimeline.empty()
      ..otherUsers['@alice:example.org'] = LatestReceiptStateData(
        event.eventId,
        4000,
      )
      ..otherUsers['@bob:example.org'] = LatestReceiptStateData(
        event.eventId,
        2000,
      );
    final receipts = event.readReceiptsForMessage();
    expect(receipts.map((receipt) => receipt.user.id), [
      '@alice:example.org',
      '@bob:example.org',
    ]);
    expect(receipts.first.time.millisecondsSinceEpoch, 4000);
  });

  test('uses timeline order rather than receipt or message timestamps', () {
    final room = _Room();
    final target = _event(room, r'$target');
    final later = _event(room, r'$later');
    final earlier = _event(room, r'$earlier');
    room.receiptState.global.otherUsers.addAll({
      '@later:example.org': LatestReceiptStateData(later.eventId, 1000),
      '@earlier:example.org': LatestReceiptStateData(earlier.eventId, 9000),
      '@unknown:example.org': LatestReceiptStateData(r'$unknown', 9999),
    });
    final timeline = _Timeline(room, [later, target, earlier]);
    expect(
      target.readReceiptsForMessage(timeline: timeline).single.user.id,
      '@later:example.org',
    );
    expect(
      target.readReceiptsForMessage(timeline: timeline, includeLater: false),
      isEmpty,
    );
  });

  test('thread messages use unthreaded and matching-thread receipts', () {
    final room = _Room();
    final event = _event(room, r'$reply', threadId: r'$root');
    room.receiptState.global.otherUsers['@global:example.org'] =
        LatestReceiptStateData(event.eventId, 1000);
    room.receiptState.mainThread = LatestReceiptStateForTimeline.empty()
      ..otherUsers['@main:example.org'] = LatestReceiptStateData(
        event.eventId,
        1000,
      );
    room.receiptState.byThread[r'$root'] = LatestReceiptStateForTimeline.empty()
      ..otherUsers['@thread:example.org'] = LatestReceiptStateData(
        event.eventId,
        2000,
      );
    room.receiptState.byThread[r'$other'] =
        LatestReceiptStateForTimeline.empty()
          ..otherUsers['@other:example.org'] = LatestReceiptStateData(
            event.eventId,
            3000,
          );
    expect(event.readReceiptsForMessage().map((receipt) => receipt.user.id), [
      '@thread:example.org',
      '@global:example.org',
    ]);
  });

  test('a receipt stays applicable when the user reads further', () {
    final room = _Room();
    final target = _event(room, r'$target');
    final later = _event(room, r'$later');
    final timeline = _Timeline(room, [later, target]);
    room.receiptState.global.otherUsers['@alice:example.org'] =
        LatestReceiptStateData(target.eventId, 1000);
    expect(target.readReceiptsForMessage(timeline: timeline), hasLength(1));
    room.receiptState.global.otherUsers['@alice:example.org'] =
        LatestReceiptStateData(later.eventId, 2000);
    expect(
      target
          .readReceiptsForMessage(timeline: timeline)
          .single
          .time
          .millisecondsSinceEpoch,
      2000,
    );
  });
}
