// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/utils/well_formed_text.dart';

void main() {
  test('keeps valid emoji and replaces lone surrogates', () {
    expect(wellFormedText('😀 Room'), '😀 Room');
    final malformed =
        'A${String.fromCharCode(0xd800)}B${String.fromCharCode(0xdc00)}C';
    expect(wellFormedText(malformed), 'A�B�C');
  });
}
