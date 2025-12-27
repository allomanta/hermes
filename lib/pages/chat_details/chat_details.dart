// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:collection/collection.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matrix/matrix.dart';

import 'package:hermes/l10n/l10n.dart';
import 'package:hermes/pages/chat_details/chat_details_view.dart';
import 'package:hermes/pages/settings/settings.dart';
import 'package:hermes/utils/file_selector.dart';
import 'package:hermes/utils/backfill_service.dart';
import 'package:hermes/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:hermes/utils/platform_infos.dart';
import 'package:hermes/widgets/adaptive_dialogs/show_modal_action_popup.dart';
import 'package:hermes/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:hermes/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:hermes/widgets/future_loading_dialog.dart';
import 'package:hermes/widgets/matrix.dart';

enum AliasActions { copy, delete, setCanonical }

enum BackfillMode { textOnly, withMedia }

class ChatDetails extends StatefulWidget {
  final String roomId;
  final Widget? embeddedCloseButton;

  const ChatDetails({
    super.key,
    required this.roomId,
    this.embeddedCloseButton,
  });

  @override
  ChatDetailsController createState() => ChatDetailsController();
}

class ChatDetailsController extends State<ChatDetails> {
  bool displaySettings = false;

  void toggleDisplaySettings() =>
      setState(() => displaySettings = !displaySettings);

  String? get roomId => widget.roomId;

  Future<void> setDisplaynameAction() async {
    final l10n = L10n.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final room = Matrix.of(context).client.getRoomById(roomId!)!;
    final input = await showTextInputDialog(
      context: context,
      title: l10n.changeTheNameOfTheGroup,
      okLabel: l10n.ok,
      cancelLabel: l10n.cancel,
      initialText: room.getLocalizedDisplayname(MatrixLocals(l10n)),
    );
    if (input == null) return;
    if (!mounted) return;
    final success = await showFutureLoadingDialog(
      context: context,
      future: () => room.setName(input),
    );
    if (!mounted) return;
    if (success.error == null) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(l10n.displaynameHasBeenChanged)),
      );
    }
  }

  Future<void> setTopicAction() async {
    final l10n = L10n.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final room = Matrix.of(context).client.getRoomById(roomId!)!;
    final input = await showTextInputDialog(
      context: context,
      title: l10n.setChatDescription,
      okLabel: l10n.ok,
      cancelLabel: l10n.cancel,
      hintText: l10n.noChatDescriptionYet,
      initialText: room.topic,
      minLines: 4,
      maxLines: 8,
    );
    if (input == null) return;
    if (!mounted) return;
    final success = await showFutureLoadingDialog(
      context: context,
      future: () => room.setDescription(input),
    );
    if (!mounted) return;
    if (success.error == null) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(l10n.chatDescriptionHasBeenChanged)),
      );
    }
  }

  Future<void> setAvatarAction() async {
    final l10n = L10n.of(context);
    final room = Matrix.of(context).client.getRoomById(roomId!);
    final actions = [
      if (PlatformInfos.isMobile)
        AdaptiveModalAction(
          value: AvatarAction.camera,
          label: l10n.openCamera,
          isDefaultAction: true,
          icon: const Icon(Icons.camera_alt_outlined),
        ),
      AdaptiveModalAction(
        value: AvatarAction.file,
        label: l10n.openGallery,
        icon: const Icon(Icons.photo_outlined),
      ),
      if (room?.avatar != null)
        AdaptiveModalAction(
          value: AvatarAction.remove,
          label: l10n.delete,
          isDestructive: true,
          icon: const Icon(Icons.delete_outlined),
        ),
    ];
    final action = actions.length == 1
        ? actions.single.value
        : await showModalActionPopup<AvatarAction>(
            context: context,
            title: l10n.editRoomAvatar,
            cancelLabel: l10n.cancel,
            actions: actions,
          );
    if (action == null) return;
    if (!mounted) return;
    if (action == AvatarAction.remove) {
      await showFutureLoadingDialog(
        context: context,
        future: () => room!.setAvatar(null),
      );
      return;
    }
    MatrixFile file;
    if (PlatformInfos.isMobile) {
      final result = await ImagePicker().pickImage(
        source: action == AvatarAction.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        imageQuality: 50,
      );
      if (result == null) return;
      file = MatrixFile(bytes: await result.readAsBytes(), name: result.path);
    } else {
      if (!mounted) return;
      final picked = await selectFiles(
        context,
        allowMultiple: false,
        type: FileType.image,
      );
      final pickedFile = picked.firstOrNull;
      if (pickedFile == null) return;
      file = MatrixFile(
        bytes: await pickedFile.readAsBytes(),
        name: pickedFile.name,
      );
    }
    if (!mounted) return;
    await showFutureLoadingDialog(
      context: context,
      future: () => room!.setAvatar(file),
    );
  }

  static const fixedWidth = 360.0;

  Future<void> showBackfillOptions() async {
    final choice = await showModalActionPopup<BackfillMode>(
      context: context,
      title: 'Backfill this chat',
      cancelLabel: L10n.of(context).cancel,
      actions: [
        AdaptiveModalAction(
          value: BackfillMode.textOnly,
          label: 'Text only',
          isDefaultAction: true,
          icon: const Icon(Icons.chat_outlined),
        ),
        AdaptiveModalAction(
          value: BackfillMode.withMedia,
          label: 'Text + media',
          icon: const Icon(Icons.perm_media_outlined),
        ),
      ],
    );
    if (choice == null) return;
    final maxEvents = await _promptBackfillLimit();
    if (maxEvents == null) return;
    await backfillRoomHistory(
      includeMedia: choice == BackfillMode.withMedia,
      maxEvents: maxEvents,
    );
  }

  Future<int?> _promptBackfillLimit() async {
    final input = await showTextInputDialog(
      context: context,
      title: 'Backfill limit',
      message: 'Enter max events to fetch. Leave empty for all available.',
      initialText: '2000',
      keyboardType: TextInputType.number,
      validator: (value) {
        final trimmed = value.trim();
        if (trimmed.isEmpty) return null;
        final parsed = int.tryParse(trimmed);
        if (parsed == null || parsed <= 0) {
          return 'Enter a positive number or leave empty.';
        }
        return null;
      },
    );
    if (input == null) return null;
    final trimmed = input.trim();
    if (trimmed.isEmpty) return 0;
    return int.tryParse(trimmed) ?? 2000;
  }

  Future<void> backfillRoomHistory({
    bool includeMedia = false,
    int maxEvents = 2000,
  }) async {
    final room = Matrix.of(context).client.getRoomById(roomId!);
    if (room == null) return;
    final confirm = await showOkCancelAlertDialog(
      context: context,
      title: 'Backfill this chat?',
      message: includeMedia
          ? 'This may take a while and increase local storage usage. Media is cached up to the local size limit. Continue?'
          : 'This may take a while and increase local storage usage. Continue?',
      okLabel: L10n.of(context).ok,
      cancelLabel: L10n.of(context).cancel,
    );
    if (confirm != OkCancelResult.ok) return;

    await showFutureLoadingDialog(
      context: context,
      futureWithProgress: (setProgress) => BackfillService.backfillRoom(
        room,
        setProgress: setProgress,
        perRequest: 200,
        maxEvents: maxEvents,
        includeMedia: includeMedia,
      ),
      title: 'Backfilling chat…',
    );

    if (!context.mounted) return;
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Backfill complete'),
        backgroundColor: theme.colorScheme.secondaryContainer,
        showCloseIcon: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ChatDetailsView(this);
}
