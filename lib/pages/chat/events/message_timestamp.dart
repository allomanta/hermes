// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:hermes/l10n/l10n.dart';
import 'package:hermes/pages/chat/read_receipts_dialog.dart';
import 'package:hermes/utils/date_time_extension.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class MessageTimestamp extends StatelessWidget {
  final Event event;
  final Timeline timeline;
  final bool detailed;
  final Color color;
  final List<Shadow>? shadows;

  const MessageTimestamp({
    required this.event,
    required this.timeline,
    required this.color,
    this.detailed = false,
    this.shadows,
    super.key,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
    message: L10n.of(context).readBy,
    child: InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () => event.showReadReceiptsDialog(context, timeline: timeline),
      child: Text(
        ' ${detailed ? event.originServerTs.localizedDetailedTime(context) : event.originServerTs.localizedTimeOfDay(context)}',
        style: TextStyle(color: color, fontSize: 11, shadows: shadows),
      ),
    ),
  );
}
