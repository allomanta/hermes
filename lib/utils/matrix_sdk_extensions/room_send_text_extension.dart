// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:html_unescape/html_unescape.dart';
import 'package:matrix/matrix.dart';
// Reuse the SDK formatter to retain its Matrix mentions, emotes and LaTeX.
// ignore: implementation_imports
import 'package:matrix/src/utils/markdown.dart' as sdk;

extension RoomSendTextExtension on Room {
  Future<String?> sendTextEventWithFormatting(
    String message, {
    String? txid,
    Event? inReplyTo,
    String? editEventId,
    bool parseCommands = true,
    String msgtype = MessageTypes.Text,
    String? threadRootEventId,
    String? threadLastEventId,
    bool displayPendingEvent = true,
  }) {
    if (parseCommands) {
      return client.parseAndRunCommand(
        this,
        message,
        inReplyTo: inReplyTo,
        editEventId: editEventId,
        txid: txid,
        threadRootEventId: threadRootEventId,
        threadLastEventId: threadLastEventId,
      );
    }

    final content = <String, dynamic>{'msgtype': msgtype, 'body': message};
    final potentialMentions = message
        .split('@')
        .skip(1)
        .map(
          (text) => text.startsWith('[')
              ? '@${text.split(']').first}]'
              : '@${text.split(RegExp(r'\s+')).first}',
        )
        .toList();
    final hasRoomMention = potentialMentions.remove('@room');
    final mentions =
        potentialMentions
            .map(
              (mention) => mention.isValidMatrixIdStrict()
                  ? mention
                  : getMention(mention),
            )
            .nonNulls
            .toSet()
          ..remove(client.userID);
    if (inReplyTo != null) mentions.add(inReplyTo.senderId);
    if (hasRoomMention || mentions.isNotEmpty) {
      content['m.mentions'] = {
        if (hasRoomMention) 'room': true,
        if (mentions.isNotEmpty) 'user_ids': mentions.toList(),
      };
    }

    // The SDK escapes tag-shaped text before Markdown, which escapes it again
    // inside code. Defer that first escape until after Markdown has been parsed.
    var leftAngle = '\uE000;';
    var rightAngle = '\uE001;';
    while (message.contains(leftAngle) || message.contains(rightAngle)) {
      leftAngle = '\uE000$leftAngle';
      rightAngle = '\uE001$rightAngle';
    }
    final protectedMessage = message.replaceAllMapped(
      RegExp(r'<([^>]*)>'),
      (match) =>
          match[0]!.replaceAll('<', leftAngle).replaceAll('>', rightAngle),
    );
    final html = sdk
        .markdown(
          protectedMessage,
          getEmotePacks: () => getImagePacksFlat(ImagePackUsage.emoticon),
          getMention: getMention,
          convertLinebreaks: client.convertLinebreaksInFormatting,
          enableLatex: client.enableLatexMarkdown,
        )
        .replaceAll(leftAngle, '&lt;')
        .replaceAll(rightAngle, '&gt;');
    if (HtmlUnescape().convert(html.replaceAll(RegExp(r'<br />\n?'), '\n')) !=
        message) {
      content['format'] = 'org.matrix.custom.html';
      content['formatted_body'] = html;
    }
    return sendEvent(
      content,
      txid: txid,
      inReplyTo: inReplyTo,
      editEventId: editEventId,
      threadRootEventId: threadRootEventId,
      threadLastEventId: threadLastEventId,
      displayPendingEvent: displayPendingEvent,
    );
  }
}
