// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:hermes/config/themes.dart';
import 'package:hermes/l10n/l10n.dart';
import 'package:hermes/pages/chat/read_receipts_dialog.dart';
import 'package:hermes/utils/matrix_sdk_extensions/event_read_receipts_extension.dart';
import 'package:hermes/widgets/avatar.dart';
import 'package:hermes/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class SeenByRow extends StatelessWidget {
  final Event event;
  final Timeline? timeline;
  const SeenByRow({super.key, required this.event, this.timeline});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    const maxAvatars = 7;
    return StreamBuilder(
      stream: event.room.client.onSync.stream.where(
        (syncUpdate) =>
            syncUpdate.rooms?.join?[event.room.id]?.ephemeral?.any(
              (ephemeral) => ephemeral.type == 'm.receipt',
            ) ??
            false,
      ),
      builder: (context, asyncSnapshot) {
        final seenByUsers = event
            .readReceiptsForMessage(timeline: timeline, includeLater: false)
            .map((r) => r.user)
            .toList();
        return Container(
          width: double.infinity,
          alignment: Alignment.center,
          child: AnimatedContainer(
            constraints: const BoxConstraints(
              maxWidth: PantheonThemes.maxTimelineWidth,
            ),
            height: seenByUsers.isEmpty ? 0 : 24,
            duration: seenByUsers.isEmpty
                ? Duration.zero
                : PantheonThemes.animationDuration,
            curve: PantheonThemes.animationCurve,
            alignment: event.senderId == Matrix.of(context).client.userID
                ? Alignment.topRight
                : Alignment.topLeft,
            padding: const EdgeInsets.only(
              bottom: 4,
              top: 1,
              left: 8,
              right: 8,
            ),
            child: Wrap(
              spacing: 4,
              children: [
                ...(seenByUsers.length > maxAvatars
                        ? seenByUsers.sublist(0, maxAvatars)
                        : seenByUsers)
                    .map(
                      (user) => Tooltip(
                        message: L10n.of(context).readBy,
                        child: Avatar(
                          client: event.room.client,
                          mxContent: user.avatarUrl,
                          name: user.calcDisplayname(),
                          size: 16,
                          onTap: () => event.showReadReceiptsDialog(
                            context,
                            timeline: timeline,
                          ),
                        ),
                      ),
                    ),
                if (seenByUsers.length > maxAvatars)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: Material(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(32),
                      child: Tooltip(
                        message: L10n.of(context).readBy,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(32),
                          onTap: () => event.showReadReceiptsDialog(
                            context,
                            timeline: timeline,
                          ),
                          child: Center(
                            child: Text(
                              '+${seenByUsers.length - maxAvatars}',
                              style: const TextStyle(fontSize: 9),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
