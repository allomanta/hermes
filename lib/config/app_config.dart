// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ui';

abstract class AppConfig {
  static const Color primaryColor = Color(0xFF261386);

  static const Color chatColor = primaryColor;
  static const double messageFontSize = 16.0;
  static const bool allowOtherHomeservers = true;
  static const bool enableRegistration = true;
  static const bool hideTypingUsernames = false;
  static const String inviteLinkPrefix = 'https://matrix.to/#/';
  static const String deepLinkPrefix = 'im.hermes://chat/';
  static const String schemePrefix = 'matrix:';
  static const String pushNotificationsChannelId = 'hermes_push';
  static const String pushNotificationsAppId = 'chat.pantheon.hermes';
  static const double borderRadius = 18.0;
  static const double spaceBorderRadius = 11.0;
  static const double columnWidth = 360.0;
  static const String website = 'https://hermes.im';
  static const String enablePushTutorial =
      'https://github.com/allomanta/hermes/wiki/Push-Notifications-without-Google-Services';
  static const String encryptionTutorial =
      'https://github.com/allomanta/hermes/wiki/How-to-use-end-to-end-encryption-in-Hermes';
  static const String howDoIGetStickersTutorial =
      'https://github.com/allomanta/hermes/wiki';
  static const String startChatTutorial =
      'https://github.com/allomanta/hermes/wiki/How-to-Find-Users-in-Hermes';
  static const String appId = 'im.hermes.Hermes';
  static const String appOpenUrlScheme = 'im.hermes';
  static const String appSsoUrlScheme = 'im.hermes.auth';
  static const String sourceCodeUrl = 'https://github.com/allomanta/hermes';
  static const String supportUrl = 'https://github.com/allomanta/hermes/issues';
  static const String changelogUrl =
      'https://github.com/allomanta/hermes/blob/main/CHANGELOG.md';
  static const String donationUrl = 'https://ko-fi.com/krille';
  static const String helpUrl = supportUrl;
  static const Set<String> defaultReactions = {'👍', '❤️', '😂', '😮', '😢'};
  static final Uri newIssueUrl = Uri(
    scheme: 'https',
    host: 'github.com',
    path: '/allomanta/hermes/issues/new',
  );
  static final Uri homeserverList = Uri(
    scheme: 'https',
    host: 'raw.githubusercontent.com',
    path: 'krille-chan/fluffychat/refs/heads/main/recommended_homeservers.json',
  );

  // static bool swipePopEnableFullScreenDrag = true;
  // static int swipePopDurationMs = 280;
  // static double swipePopMinimumDragFraction = 0.3;
  // static double swipePopVelocityThreshold = 350.0;
  // static Duration get swipePopDuration =>
  //     Duration(milliseconds: swipePopDurationMs);

  static final Uri privacyUrl = Uri(
    scheme: 'https',
    host: 'github.com',
    path: '/allomanta/hermes/blob/main/PRIVACY.md',
  );
  static final Uri crashReportEndpoint = Uri(
    scheme: 'https',
    host: 'crash.fluffy.chat',
  );

  static const String mainIsolatePortName = 'main_isolate';
  static const String pushIsolatePortName = 'push_isolate';
  static const String pushHelperCrashReportKey = 'push_helper_crash_report';
}
