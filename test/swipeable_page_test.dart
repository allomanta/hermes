// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/utils/swipeable_page.dart';

void main() {
  testWidgets('updates the child when a page keeps the same key', (
    tester,
  ) async {
    final label = ValueNotifier('first');
    addTearDown(label.dispose);

    await tester.pumpWidget(
      CupertinoApp(
        home: ValueListenableBuilder(
          valueListenable: label,
          builder: (context, value, _) => Navigator(
            pages: [
              SwipePopPage<void>(
                key: const ValueKey('page'),
                duration: Duration.zero,
                enableFullScreenDrag: false,
                minimumDragFraction: 0.5,
                velocityThreshold: 100,
                child: Center(child: Text(value)),
              ),
            ],
            onDidRemovePage: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('first'), findsOneWidget);

    label.value = 'second';
    await tester.pump();

    expect(find.text('first'), findsNothing);
    expect(find.text('second'), findsOneWidget);
  });
}
