// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:go_router/go_router.dart';
import 'package:hermes/l10n/l10n.dart';
import 'package:hermes/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:hermes/widgets/future_loading_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

enum SpaceActions { addChild, settings, leave }

List<PopupMenuEntry<SpaceActions>> spaceActionMenuItems(
  BuildContext context,
  Room space,
) => [
  if (space.canChangeStateEvent(EventTypes.SpaceChild))
    PopupMenuItem(
      value: SpaceActions.addChild,
      child: ListTile(
        leading: const Icon(Icons.edit_square),
        title: Text(L10n.of(context).addChatOrSubSpace),
      ),
    ),
  PopupMenuItem(
    value: SpaceActions.settings,
    child: ListTile(
      leading: const Icon(Icons.settings_outlined),
      title: Text(L10n.of(context).settings),
    ),
  ),
  PopupMenuItem(
    value: SpaceActions.leave,
    child: ListTile(
      leading: const Icon(Icons.delete_outlined),
      title: Text(L10n.of(context).leave),
    ),
  ),
];

Future<void> performSpaceAction(
  BuildContext context,
  Room space,
  SpaceActions action, {
  required VoidCallback onLeave,
}) async {
  switch (action) {
    case SpaceActions.settings:
      await space.postLoad();
      if (!context.mounted) return;
      context.push('/rooms/${space.id}/details');
      return;
    case SpaceActions.addChild:
      context.go('/rooms/newgroup?space_id=${space.id}');
      return;
    case SpaceActions.leave:
      final confirmed = await showOkCancelAlertDialog(
        context: context,
        title: L10n.of(context).areYouSure,
        message: L10n.of(context).archiveRoomDescription,
        okLabel: L10n.of(context).leave,
        cancelLabel: L10n.of(context).cancel,
        isDestructive: true,
      );
      if (!context.mounted || confirmed != OkCancelResult.ok) return;

      final result = await showFutureLoadingDialog(
        context: context,
        future: () async {
          try {
            await space.leave();
          } on MatrixException catch (e) {
            if (e.error != MatrixError.M_FORBIDDEN &&
                e.error != MatrixError.M_NOT_FOUND) {
              rethrow;
            }
          }
          await space.client.database.forgetRoom(space.id);
          space.client.rooms.removeWhere((room) => room.id == space.id);
        },
      );
      if (!context.mounted || result.error != null) return;
      onLeave();
      return;
  }
}
