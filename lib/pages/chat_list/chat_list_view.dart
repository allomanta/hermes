import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:hermes/l10n/l10n.dart';
import 'package:hermes/pages/chat_list/chat_list.dart';
import 'package:hermes/widgets/navigation_rail.dart';
import 'chat_list_body.dart';

class ChatListView extends StatelessWidget {
  final ChatListController controller;

  const ChatListView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !controller.isSearchMode && controller.activeSpaceId == null,
      onPopInvokedWithResult: (pop, _) {
        if (pop) return;
        if (controller.activeSpaceId != null) {
          controller.clearActiveSpace();
          return;
        }
        if (controller.isSearchMode) {
          controller.cancelSearch();
          return;
        }
      },
      child: Row(
        children: [
          // if (PantheonThemes.isColumnMode(context) ||
          //     AppConfig.displayNavigationRail)
          // ...[
          SpacesNavigationRail(
            activeSpaceId: controller.activeSpaceId,
            onGoToChats: controller.clearActiveSpace,
            onGoToSpaceId: controller.setActiveSpace,
          ),
          Container(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
          // ],
          Expanded(
            child: GestureDetector(
              onTap: FocusManager.instance.primaryFocus?.unfocus,
              excludeFromSemantics: true,
              behavior: HitTestBehavior.translucent,
              child: Scaffold(
                body: ChatListViewBody(controller),
                floatingActionButton: !controller.isSearchMode &&
                        controller.activeSpaceId == null
                    ? FloatingActionButton(
                        onPressed: () => context.go('/rooms/newprivatechat'),
                        shape: const CircleBorder(),
                        heroTag: null,
                        mini: false,
                        // backgroundColor: theme.colorScheme.surface,
                        // foregroundColor: theme.colorScheme.onSurface,
                        child: const Icon(Icons.add_outlined),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
