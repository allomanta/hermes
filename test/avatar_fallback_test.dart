// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/widgets/avatar.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class _Client extends Fake implements Client {}

void main() {
  testWidgets('avatar initials keep an emoji grapheme intact', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Avatar(name: '😀 Room', client: _Client()),
        ),
      ),
    );

    expect(find.text('😀R'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('avatar initials tolerate malformed UTF-16 names', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Avatar(name: String.fromCharCode(0xd800), client: _Client()),
        ),
      ),
    );

    expect(find.text('�'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
