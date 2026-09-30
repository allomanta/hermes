// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:html/parser.dart' as parser;
import 'package:matrix/matrix.dart';

extension EventLinksExtension on Event {
  List<({String url, String name})> get sharedLinks {
    if (type != EventTypes.Message || redacted) return [];

    final links = <String, String>{};
    var text = calcUnlocalizedBody(hideReply: true);
    if (isRichMessage && formattedText.isNotEmpty) {
      final document = parser.parseFragment(formattedText);
      for (final reply in document.querySelectorAll('mx-reply')) {
        reply.remove();
      }
      for (final anchor in document.querySelectorAll('a')) {
        final url = anchor.attributes['href']?.trim();
        if (url != null && url.isNotEmpty) {
          final name = anchor.text.trim();
          links.putIfAbsent(url, () => name.isEmpty ? url : name);
        }
        // A label can look like another URL; only its actual target is shared.
        anchor.remove();
      }
      text = document.text ?? '';
    }
    for (final link in const UrlLinkifier().parse(
      [TextElement(text)],
      const LinkifyOptions(humanize: false, defaultToHttps: true),
    ).whereType<UrlElement>()) {
      links.putIfAbsent(link.url, () => link.text);
    }

    return links.entries
        .where((link) {
          final uri = Uri.tryParse(link.key);
          return uri != null &&
              {'http', 'https'}.contains(uri.scheme) &&
              uri.host.isNotEmpty;
        })
        .map((link) => (url: link.key, name: link.value))
        .toList();
  }
}
