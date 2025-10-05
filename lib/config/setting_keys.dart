import 'package:shared_preferences/shared_preferences.dart';

abstract class SettingKeys {
  static const String renderHtml = 'chat.pantheon.renderHtml';
  static const String hideRedactedEvents = 'chat.pantheon.hideRedactedEvents';
  static const String hideUnknownEvents = 'chat.pantheon.hideUnknownEvents';
  static const String hideUnimportantStateEvents =
      'chat.pantheon.hideUnimportantStateEvents';
  static const String separateChatTypes = 'chat.pantheon.separateChatTypes';
  static const String sentry = 'sentry';
  static const String theme = 'theme';
  static const String amoledEnabled = 'amoled_enabled';
  static const String codeLanguage = 'code_language';
  static const String showNoGoogle = 'chat.pantheon.show_no_google';
  static const String fontSizeFactor = 'chat.pantheon.font_size_factor';
  static const String showNoPid = 'chat.pantheon.show_no_pid';
  static const String databasePassword = 'database-password';
  static const String appLockKey = 'chat.pantheon.app_lock';
  static const String unifiedPushRegistered =
      'chat.pantheon.unifiedpush.registered';
  static const String unifiedPushEndpoint =
      'chat.pantheon.unifiedpush.endpoint';
  static const String ownStatusMessage = 'chat.pantheon.status_msg';
  static const String dontAskForBootstrapKey = 'chat.hermes.dont_ask_bootstrap';
  static const String autoplayImages = 'chat.pantheon.autoplay_images';
  static const String sendTypingNotifications =
      'chat.pantheon.send_typing_notifications';
  static const String sendPublicReadReceipts =
      'chat.pantheon.send_public_read_receipts';
  static const String sendOnEnter = 'chat.pantheon.send_on_enter';
  static const String swipeRightToLeftToReply =
      'chat.pantheon.swipeRightToLeftToReply';

  static const String swipePopEnableFullScreenDrag =
      'chat.pantheon.swipePopEnableFullScreenDrag';
  static const String swipePopDurationMs = 'chat.pantheon.swipePopDurationMs';
  static const String swipePopMinimumDragFraction =
      'chat.pantheon.swipePopMinimumDragFraction';
  static const String swipePopVelocityThreshold =
      'chat.pantheon.swipePopVelocityThreshold';

  static const String experimentalVoip = 'chat.pantheon.experimental_voip';
  static const String showPresences = 'chat.pantheon.show_presences';
  static const String displayNavigationRail =
      'chat.pantheon.display_navigation_rail';
}

enum AppSettings<T> {
  textMessageMaxLength<int>('textMessageMaxLength', 16384),
  audioRecordingNumChannels<int>('audioRecordingNumChannels', 1),
  audioRecordingAutoGain<bool>('audioRecordingAutoGain', true),
  audioRecordingEchoCancel<bool>('audioRecordingEchoCancel', false),
  audioRecordingNoiseSuppress<bool>('audioRecordingNoiseSuppress', true),
  audioRecordingBitRate<int>('audioRecordingBitRate', 64000),
  audioRecordingSamplingRate<int>('audioRecordingSamplingRate', 44100),
  pushNotificationsGatewayUrl<String>(
    'pushNotificationsGatewayUrl',
    'https://push.lageveen.co/_matrix/push/v1/notify',
  ),
  pushNotificationsPusherFormat<String>(
    'pushNotificationsPusherFormat',
    'event_id_only',
  ),
  shareKeysWith<String>('chat.pantheon.share_keys_with_2', 'all'),
  noEncryptionWarningShown<bool>(
    'chat.pantheon.no_encryption_warning_shown',
    false,
  ),
  displayChatDetailsColumn(
    'chat.pantheon.display_chat_details_column',
    false,
  ),
  enableSoftLogout<bool>('chat.pantheon.enable_soft_logout', false);

  final String key;
  final T defaultValue;

  const AppSettings(this.key, this.defaultValue);
}

extension AppSettingsBoolExtension on AppSettings<bool> {
  bool getItem(SharedPreferences store) => store.getBool(key) ?? defaultValue;

  Future<void> setItem(SharedPreferences store, bool value) =>
      store.setBool(key, value);
}

extension AppSettingsStringExtension on AppSettings<String> {
  String getItem(SharedPreferences store) =>
      store.getString(key) ?? defaultValue;

  Future<void> setItem(SharedPreferences store, String value) =>
      store.setString(key, value);
}

extension AppSettingsIntExtension on AppSettings<int> {
  int getItem(SharedPreferences store) => store.getInt(key) ?? defaultValue;

  Future<void> setItem(SharedPreferences store, int value) =>
      store.setInt(key, value);
}

extension AppSettingsDoubleExtension on AppSettings<double> {
  double getItem(SharedPreferences store) =>
      store.getDouble(key) ?? defaultValue;

  Future<void> setItem(SharedPreferences store, double value) =>
      store.setDouble(key, value);
}
