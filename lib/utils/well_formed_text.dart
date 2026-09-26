// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Replaces unmatched UTF-16 surrogates before passing text to Flutter layout.
String wellFormedText(String value) {
  StringBuffer? result;
  var start = 0;
  for (var i = 0; i < value.length; i++) {
    final codeUnit = value.codeUnitAt(i);
    if (codeUnit < 0xd800 || codeUnit > 0xdfff) continue;
    if (codeUnit <= 0xdbff && i + 1 < value.length) {
      final next = value.codeUnitAt(i + 1);
      if (next >= 0xdc00 && next <= 0xdfff) {
        i++;
        continue;
      }
    }
    result ??= StringBuffer();
    result.write(value.substring(start, i));
    result.writeCharCode(0xfffd);
    start = i + 1;
  }
  if (result == null) return value;
  result.write(value.substring(start));
  return result.toString();
}
