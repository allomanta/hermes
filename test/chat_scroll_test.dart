// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/config/setting_keys.dart';
import 'package:hermes/pages/chat/chat.dart';
import 'package:matrix/matrix.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ChatController extends ChatController {
  @override
  void setReadMarker({String? eventId}) {}
}

class _Event extends Fake implements Event {
  @override
  String get eventId => r'$latest';

  @override
  String? get relationshipType => null;

  @override
  String get type => EventTypes.Message;

  @override
  bool get redacted => false;

  @override
  bool get isEventTypeKnown => true;
}

class _Timeline extends Fake implements Timeline {
  _Timeline({required this.canRequestFuture, required this.isRequestingFuture});

  @override
  final bool canRequestFuture;

  @override
  final bool isRequestingFuture;

  @override
  final List<Event> events = [_Event()];

  @override
  Future<void> requestFuture({
    int historyCount = Room.defaultHistoryCount,
    StateFilter? filter,
  }) async {}
}

void main() {
  for (final loading in [false, true]) {
    testWidgets(
      loading
          ? 'duplicate future requests do not move the chat from the bottom'
          : 'a live timeline stays at the bottom when requesting future events',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await AppSettings.init(loadWebConfigFile: false);
        final controller = _ChatController()
          ..timeline = _Timeline(
            canRequestFuture: loading,
            isRequestingFuture: loading,
          );
        addTearDown(controller.scrollController.dispose);
        addTearDown(controller.sendController.dispose);

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: ListView.builder(
              reverse: true,
              controller: controller.scrollController,
              itemCount: 20,
              itemBuilder: (context, index) => index == 0
                  ? const SizedBox(height: 64)
                  : AutoScrollTag(
                      key: ValueKey(index),
                      index: index - 1,
                      controller: controller.scrollController,
                      child: const SizedBox(height: 100),
                    ),
            ),
          ),
        );

        expect(controller.scrollController.offset, 0);
        await controller.requestFuture();
        await tester.pumpAndSettle();
        expect(controller.scrollController.offset, 0);
      },
    );
  }
}
