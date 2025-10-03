import 'dart:ui';

import 'package:matrix/matrix.dart';

abstract class AppConfig {
  static String _applicationName = 'Hermes';

  static String get applicationName => _applicationName;
  static String? _applicationWelcomeMessage;

  static String? get applicationWelcomeMessage => _applicationWelcomeMessage;
  static String _defaultHomeserver = 'matrix.org';

  static String get defaultHomeserver => _defaultHomeserver;
  static double fontSizeFactor = 1;
  static const Color chatColor = primaryColor;
  static Color? colorSchemeSeed = primaryColor;
  static const double messageFontSize = 16.0;
  static const bool allowOtherHomeservers = true;
  static const bool enableRegistration = true;
  static const Color primaryColor = Color(0xFF5625BA);
  static const Color primaryColorLight = Color(0xFFCCBDEA);
  static const Color secondaryColor = Color(0xFF41a2bc);
  static String _privacyUrl =
      'https://github.com/allomanta/hermes/blob/main/PRIVACY.md';

  static const Set<String> defaultReactions = {'👍', '❤️', '😂', '😮', '😢'};

  static double replySwipeDismissThreshold = 0.3;
  static double replySwipeMaxOffsetFraction = 0.35;
  static int replySwipeMovementDurationMs = 200;
  static double replySwipeVelocityThreshold = 450.0;

  static String get privacyUrl => _privacyUrl;
  static const String website = 'https://hermes.im';
  static const String enablePushTutorial =
      'https://github.com/allomanta/hermes/wiki/Push-Notifications-without-Google-Services';
  static const String encryptionTutorial =
      'https://github.com/allomanta/hermes/wiki/How-to-use-end-to-end-encryption-in-Hermes';
  static const String startChatTutorial =
      'https://github.com/allomanta/hermes/wiki/How-to-Find-Users-in-Hermes';
  static const String appId = 'im.hermes.Hermes';
  static const String appOpenUrlScheme = 'im.hermes';
  static String _webBaseUrl = 'https://hermes.im/web';

  static String get webBaseUrl => _webBaseUrl;
  static const String sourceCodeUrl = 'https://github.com/allomanta/hermes';
  static const String supportUrl = 'https://github.com/allomanta/hermes/issues';
  static const String changelogUrl =
      'https://github.com/allomanta/hermes/blob/main/CHANGELOG.md';
  static final Uri newIssueUrl = Uri(
    scheme: 'https',
    host: 'github.com',
    path: '/allomanta/hermes/issues/new',
  );
  static bool renderHtml = true;
  static bool hideRedactedEvents = false;
  static bool hideUnknownEvents = true;
  static bool separateChatTypes = false;
  static bool autoplayImages = true;
  static bool sendTypingNotifications = true;
  static bool sendPublicReadReceipts = true;
  static bool swipeRightToLeftToReply = true;
  static bool swipePopEnableFullScreenDrag = true;
  static int swipePopDurationMs = 280;
  static double swipePopMinimumDragFraction = 0.3;
  static double swipePopVelocityThreshold = 350.0;
  static bool? sendOnEnter;
  static bool showPresences = true;
  static bool displayNavigationRail = false;
  static bool experimentalVoip = false;
  static const bool hideTypingUsernames = false;
  static const String inviteLinkPrefix = 'https://matrix.to/#/';
  static const String deepLinkPrefix = 'im.hermes://chat/';
  static const String schemePrefix = 'matrix:';
  static const String pushNotificationsChannelId = 'hermes_push';
  static const String pushNotificationsAppId = 'chat.pantheon.hermes';
  static const double borderRadius = 18.0;
  static const double columnWidth = 360.0;
  static final Uri homeserverList = Uri(
    scheme: 'https',
    host: 'servers.joinmatrix.org',
    path: 'servers.json',
  );

  static Duration get swipePopDuration =>
      Duration(milliseconds: swipePopDurationMs);

  static Duration get replySwipeMovementDuration =>
      Duration(milliseconds: replySwipeMovementDurationMs);

  static void loadFromJson(Map<String, dynamic> json) {
    if (json['chat_color'] != null) {
      try {
        colorSchemeSeed = Color(json['chat_color']);
      } catch (e) {
        Logs().w(
          'Invalid color in config.json! Please make sure to define the color in this format: "0xffdd0000"',
          e,
        );
      }
    }
    if (json['application_name'] is String) {
      _applicationName = json['application_name'];
    }
    if (json['application_welcome_message'] is String) {
      _applicationWelcomeMessage = json['application_welcome_message'];
    }
    if (json['default_homeserver'] is String) {
      _defaultHomeserver = json['default_homeserver'];
    }
    if (json['privacy_url'] is String) {
      _privacyUrl = json['privacy_url'];
    }
    if (json['web_base_url'] is String) {
      _webBaseUrl = json['web_base_url'];
    }
    if (json['render_html'] is bool) {
      renderHtml = json['render_html'];
    }
    if (json['hide_redacted_events'] is bool) {
      hideRedactedEvents = json['hide_redacted_events'];
    }
    if (json['hide_unknown_events'] is bool) {
      hideUnknownEvents = json['hide_unknown_events'];
    }
    if (json['reply_swipe_dismiss_threshold'] is num) {
      replySwipeDismissThreshold =
          (json['reply_swipe_dismiss_threshold'] as num).toDouble();
    }
    if (json['reply_swipe_max_offset_fraction'] is num) {
      replySwipeMaxOffsetFraction =
          (json['reply_swipe_max_offset_fraction'] as num).toDouble();
    }
    if (json['reply_swipe_movement_duration_ms'] is num) {
      replySwipeMovementDurationMs =
          (json['reply_swipe_movement_duration_ms'] as num).round();
    }
    if (json['reply_swipe_velocity_threshold'] is num) {
      replySwipeVelocityThreshold =
          (json['reply_swipe_velocity_threshold'] as num).toDouble();
    }
  }
}
