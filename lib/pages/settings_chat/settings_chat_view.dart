import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:hermes/l10n/l10n.dart';
import 'package:hermes/config/app_config.dart';
import 'package:hermes/config/setting_keys.dart';
import 'package:hermes/config/themes.dart';
import 'package:hermes/utils/platform_infos.dart';
import 'package:hermes/widgets/layouts/max_width_body.dart';
import 'package:hermes/widgets/matrix.dart';
import 'package:hermes/widgets/settings_switch_list_tile.dart';
import 'settings_chat.dart';

class SettingsChatView extends StatelessWidget {
  final SettingsChatController controller;
  const SettingsChatView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.of(context).chat),
        automaticallyImplyLeading: !PantheonThemes.isColumnMode(context),
        centerTitle: PantheonThemes.isColumnMode(context),
      ),
      body: ListTileTheme(
        iconColor: theme.textTheme.bodyLarge!.color,
        child: MaxWidthBody(
          child: Column(
            children: [
              const ListTile(
                title: Text('Swipe back gesture'),
                subtitle: Text(
                  'Adjust how sensitive the back-swipe navigation should be.',
                ),
              ),
              SwitchListTile.adaptive(
                value: controller.swipeEnableFullScreenDrag,
                title: const Text('Enable full-screen swipe back'),
                onChanged: controller.setSwipeEnableFullScreenDrag,
              ),
              ListTile(
                title: const Text('Swipe duration'),
                subtitle:
                    const Text('Controls how long the transition animates.'),
                trailing: Text('${controller.swipeDurationMs.round()} ms'),
              ),
              Slider.adaptive(
                min: 120,
                max: 600,
                divisions: 24,
                value: controller.swipeDurationMs.clamp(120, 600).toDouble(),
                onChanged: controller.swipeEnableFullScreenDrag
                    ? controller.updateSwipeDuration
                    : null,
                onChangeEnd: controller.swipeEnableFullScreenDrag
                    ? controller.saveSwipeDuration
                    : null,
              ),
              ListTile(
                title: const Text('Required swipe distance'),
                subtitle: const Text(
                  'Percentage of the screen that must be swiped before popping.',
                ),
                trailing: Text(
                  '${(controller.swipeMinimumDragFraction * 100).round()}%',
                ),
              ),
              Slider.adaptive(
                min: 0.05,
                max: 1.0,
                divisions: 19,
                value: controller.swipeMinimumDragFraction
                    .clamp(0.05, 1.0)
                    .toDouble(),
                onChanged: controller.swipeEnableFullScreenDrag
                    ? controller.updateSwipeMinimumDragFraction
                    : null,
                onChangeEnd: controller.swipeEnableFullScreenDrag
                    ? controller.saveSwipeMinimumDragFraction
                    : null,
              ),
              ListTile(
                title: const Text('Swipe release velocity'),
                subtitle: const Text(
                  'Minimum fling speed needed when the drag is short.',
                ),
                trailing:
                    Text('${controller.swipeVelocityThreshold.round()} px/s'),
              ),
              Slider.adaptive(
                min: 50,
                max: 2000,
                divisions: 39,
                value: controller.swipeVelocityThreshold
                    .clamp(50.0, 2000.0)
                    .toDouble(),
                onChanged: controller.swipeEnableFullScreenDrag
                    ? controller.updateSwipeVelocityThreshold
                    : null,
                onChangeEnd: controller.swipeEnableFullScreenDrag
                    ? controller.saveSwipeVelocityThreshold
                    : null,
              ),
              Divider(color: theme.dividerColor),
              SettingsSwitchListTile.adaptive(
                title: L10n.of(context).formattedMessages,
                subtitle: L10n.of(context).formattedMessagesDescription,
                onChanged: (b) => AppConfig.renderHtml = b,
                storeKey: SettingKeys.renderHtml,
                defaultValue: AppConfig.renderHtml,
              ),
              SettingsSwitchListTile.adaptive(
                title: L10n.of(context).hideRedactedMessages,
                subtitle: L10n.of(context).hideRedactedMessagesBody,
                onChanged: (b) => AppConfig.hideRedactedEvents = b,
                storeKey: SettingKeys.hideRedactedEvents,
                defaultValue: AppConfig.hideRedactedEvents,
              ),
              SettingsSwitchListTile.adaptive(
                title: L10n.of(context).hideInvalidOrUnknownMessageFormats,
                onChanged: (b) => AppConfig.hideUnknownEvents = b,
                storeKey: SettingKeys.hideUnknownEvents,
                defaultValue: AppConfig.hideUnknownEvents,
              ),
              if (PlatformInfos.isMobile)
                SettingsSwitchListTile.adaptive(
                  title: L10n.of(context).autoplayImages,
                  onChanged: (b) => AppConfig.autoplayImages = b,
                  storeKey: SettingKeys.autoplayImages,
                  defaultValue: AppConfig.autoplayImages,
                ),
              SettingsSwitchListTile.adaptive(
                title: L10n.of(context).sendOnEnter,
                onChanged: (b) => AppConfig.sendOnEnter = b,
                storeKey: SettingKeys.sendOnEnter,
                defaultValue: AppConfig.sendOnEnter ?? !PlatformInfos.isMobile,
              ),
              SettingsSwitchListTile.adaptive(
                title: L10n.of(context).swipeRightToLeftToReply,
                onChanged: (b) => AppConfig.swipeRightToLeftToReply = b,
                storeKey: SettingKeys.swipeRightToLeftToReply,
                defaultValue: AppConfig.swipeRightToLeftToReply,
              ),
              const ListTile(
                title: Text('Reply swipe sensitivity'),
                subtitle: Text(
                  'Tune the gesture used to reply directly from a message.',
                ),
              ),
              ListTile(
                title: const Text('Swipe distance'),
                trailing: Text(
                  '${(controller.replyDismissThreshold * 100).round()}%',
                ),
              ),
              Slider.adaptive(
                min: 0.05,
                max: 0.8,
                divisions: 15,
                value: controller.replyDismissThreshold.clamp(0.05, 0.8),
                onChanged: controller.updateReplyDismissThreshold,
                onChangeEnd: controller.saveReplyDismissThreshold,
              ),
              ListTile(
                title: const Text('Swipe travel distance'),
                trailing: Text(
                  '${(controller.replyMaxOffsetFraction * 100).round()}%',
                ),
              ),
              Slider.adaptive(
                min: 0.1,
                max: 0.9,
                divisions: 16,
                value: controller.replyMaxOffsetFraction.clamp(0.1, 0.9),
                onChanged: controller.updateReplyMaxOffsetFraction,
                onChangeEnd: controller.saveReplyMaxOffsetFraction,
              ),
              ListTile(
                title: const Text('Swipe animation duration'),
                trailing: Text('${controller.replyDurationMs.round()} ms'),
              ),
              Slider.adaptive(
                min: 100,
                max: 600,
                divisions: 20,
                value: controller.replyDurationMs.clamp(100, 600),
                onChanged: controller.updateReplyDuration,
                onChangeEnd: controller.saveReplyDuration,
              ),
              ListTile(
                title: const Text('Swipe release velocity'),
                trailing:
                    Text('${controller.replyVelocityThreshold.round()} px/s'),
              ),
              Slider.adaptive(
                min: 100,
                max: 2000,
                divisions: 38,
                value: controller.replyVelocityThreshold.clamp(100.0, 2000.0),
                onChanged: controller.updateReplyVelocity,
                onChangeEnd: controller.saveReplyVelocity,
              ),
              Divider(color: theme.dividerColor),
              ListTile(
                title: Text(
                  L10n.of(context).customEmojisAndStickers,
                  style: TextStyle(
                    color: theme.colorScheme.secondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ListTile(
                title: Text(L10n.of(context).customEmojisAndStickers),
                subtitle: Text(L10n.of(context).customEmojisAndStickersBody),
                onTap: () => context.go('/rooms/settings/chat/emotes'),
                trailing: const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Icon(Icons.chevron_right_outlined),
                ),
              ),
              Divider(color: theme.dividerColor),
              ListTile(
                title: Text(
                  L10n.of(context).calls,
                  style: TextStyle(
                    color: theme.colorScheme.secondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              SettingsSwitchListTile.adaptive(
                title: L10n.of(context).experimentalVideoCalls,
                onChanged: (b) {
                  AppConfig.experimentalVoip = b;
                  Matrix.of(context).createVoipPlugin();
                  return;
                },
                storeKey: SettingKeys.experimentalVoip,
                defaultValue: AppConfig.experimentalVoip,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
