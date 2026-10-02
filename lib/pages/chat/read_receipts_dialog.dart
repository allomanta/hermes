// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:hermes/l10n/l10n.dart';
import 'package:hermes/utils/adaptive_bottom_sheet.dart';
import 'package:hermes/utils/date_time_extension.dart';
import 'package:hermes/utils/matrix_sdk_extensions/event_read_receipts_extension.dart';
import 'package:hermes/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:hermes/widgets/avatar.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

extension ReadReceiptsDialogExtension on Event {
  Future<void> showReadReceiptsDialog(
    BuildContext context, {
    Timeline? timeline,
  }) => showAdaptiveBottomSheet<void>(
    context: context,
    builder: (context) => ReadReceiptsDialog(event: this, timeline: timeline),
  );
}

class ReadReceiptsDialog extends StatelessWidget {
  final Event event;
  final Timeline? timeline;

  const ReadReceiptsDialog({required this.event, this.timeline, super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final locals = MatrixLocals(l10n);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.readBy),
        leading: CloseButton(onPressed: Navigator.of(context).pop),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              l10n.readReceiptTimesDescription,
              style: theme.textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: StreamBuilder<SyncUpdate>(
              stream: event.room.client.onSync.stream.where(
                (update) =>
                    update.rooms?.join?.containsKey(event.room.id) ?? false,
              ),
              builder: (context, snapshot) {
                final receipts = event.readReceiptsForMessage(
                  timeline: timeline,
                );
                if (receipts.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        l10n.noReadReceipts,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: receipts.length,
                  itemBuilder: (context, index) {
                    final receipt = receipts[index];
                    final user = receipt.user;
                    final name = user.calcDisplayname(i18n: locals);
                    final time = receipt.time.millisecondsSinceEpoch > 0
                        ? receipt.time.localizedDetailedTime(context)
                        : l10n.readTimeUnavailable;
                    return ListTile(
                      key: ValueKey(user.id),
                      leading: Avatar(
                        client: event.room.client,
                        mxContent: user.avatarUrl,
                        name: name,
                        size: 32,
                      ),
                      title: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.id,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text('${l10n.lastReportedRead}: $time'),
                        ],
                      ),
                      isThreeLine: true,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
