import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import 'package:hermes/config/app_config.dart';
import 'package:hermes/l10n/l10n.dart';
import 'package:hermes/utils/platform_infos.dart';
import 'package:hermes/utils/url_launcher.dart';
import 'package:hermes/widgets/mxc_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

import '../../widgets/avatar.dart';

class _CloseStickerPickerIntent extends Intent {
  const _CloseStickerPickerIntent();
}

class StickerPickerDialog extends StatefulWidget {
  final Room room;
  final ImagePackUsage usage;
  final void Function(ImagePackImageContent) onSelected;
  final VoidCallback? onEscape;

  const StickerPickerDialog({
    required this.onSelected,
    required this.room,
    this.usage = ImagePackUsage.sticker,
    this.onEscape,
    super.key,
  });

  @override
  StickerPickerDialogState createState() => StickerPickerDialogState();
}

class StickerPickerDialogState extends State<StickerPickerDialog> {
  String? searchFilter;
  late final FocusNode _searchFocusNode = FocusNode();
  final _searchController = TextEditingController();
  final _scrollController = AutoScrollController();

  @override
  void initState() {
    super.initState();
    if (PlatformInfos.isDesktop) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _searchFocusNode.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleStickerSelected(ImagePackImageContent image) {
    if (PlatformInfos.isMobile) {
      FocusScope.of(context).unfocus();
    }
    widget.onSelected(image);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final stickerPacks = widget.room.getImagePacks(widget.usage);
    final packSlugs = stickerPacks.keys.toList();

    // ignore: prefer_function_declarations_over_variables
    final packBuilder = (BuildContext context, int packIndex) {
      final pack = stickerPacks[packSlugs[packIndex]]!;
      final filteredImagePackImageEntried = pack.images.entries.toList();
      if (searchFilter?.isNotEmpty ?? false) {
        filteredImagePackImageEntried.removeWhere(
          (e) =>
              !(e.key.toLowerCase().contains(searchFilter!.toLowerCase()) ||
                  (e.value.body?.toLowerCase().contains(
                        searchFilter!.toLowerCase(),
                      ) ??
                      false)),
        );
      }
      final imageKeys = filteredImagePackImageEntried
          .map((e) => e.key)
          .toList();
      if (imageKeys.isEmpty) {
        return const SizedBox.shrink();
      }
      final packName = pack.pack.displayName ?? packSlugs[packIndex];
      return Column(
        children: <Widget>[
          if (packName != 'user')
            ListTile(
              leading: Avatar(
                mxContent: pack.pack.avatarUrl,
                name: packName,
                client: widget.room.client,
              ),
              title: Text(packName),
            ),
          const SizedBox(height: 6),
          GridView.builder(
            padding: EdgeInsets.zero,
            itemCount: imageKeys.length,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 128,
            ),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemBuilder: (BuildContext context, int imageIndex) {
              final image = pack.images[imageKeys[imageIndex]]!;
              return Tooltip(
                message: image.body ?? imageKeys[imageIndex],
                child: InkWell(
                  radius: AppConfig.borderRadius,
                  key: ValueKey(image.url.toString()),
                  onTap: () {
                    // copy the image
                    final imageCopy = ImagePackImageContent.fromJson(
                      image.toJson().copy(),
                    );
                    // set the body, if it doesn't exist, to the key
                    imageCopy.body ??= imageKeys[imageIndex];
                    _handleStickerSelected(imageCopy);
                  },
                  child: AbsorbPointer(
                    absorbing: true,
                    child: MxcImage(
                      uri: image.url,
                      fit: BoxFit.contain,
                      width: 128,
                      height: 128,
                      animated: true,
                      isThumbnail: false,
                    ),
                  ),
                ),
              );
            },
          ),
          if (packIndex != packSlugs.length - 1) const SizedBox(height: 20),
        ],
      );
    };

    return Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{
        LogicalKeySet(LogicalKeyboardKey.escape):
            const _CloseStickerPickerIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _CloseStickerPickerIntent: CallbackAction<_CloseStickerPickerIntent>(
            onInvoke: (intent) {
              widget.onEscape?.call();
              return null;
            },
          ),
        },
        child: Scaffold(
          backgroundColor: theme.colorScheme.onInverseSurface,
          body: SizedBox(
            width: double.maxFinite,
            child: CustomScrollView(
              controller: _scrollController,
              slivers: <Widget>[
                SliverAppBar(
                  primary: false,
                  floating: true,
                  pinned: true,
                  scrolledUnderElevation: 0,
                  automaticallyImplyLeading: false,
                  backgroundColor: theme.colorScheme.onInverseSurface,
                  toolbarHeight: packSlugs.isEmpty
                      ? kToolbarHeight
                      : kToolbarHeight * 2,
                  title: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (packSlugs.isNotEmpty)
                        SizedBox(
                          height: kToolbarHeight,
                          child: ScrollConfiguration(
                            behavior: ScrollConfiguration.of(context).copyWith(
                              dragDevices: {
                                ...ScrollConfiguration.of(context).dragDevices,
                                PointerDeviceKind.mouse,
                              },
                            ),
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: packSlugs.length,
                              itemBuilder: (context, index) {
                                final pack = stickerPacks[packSlugs[index]]!;
                                final packName =
                                    pack.pack.displayName ?? packSlugs[index];
                                return IconButton(
                                  tooltip: packName,
                                  icon: Avatar(
                                    mxContent:
                                        pack.pack.avatarUrl ??
                                        pack.images.values.firstOrNull?.url,
                                    name: packName,
                                    client: widget.room.client,
                                    size: 36,
                                  ),
                                  onPressed: () async {
                                    _searchFocusNode.unfocus();
                                    if (searchFilter?.isNotEmpty ?? false) {
                                      _searchController.clear();
                                      setState(() => searchFilter = null);
                                      await WidgetsBinding.instance.endOfFrame;
                                      if (!mounted) return;
                                    }
                                    await _scrollController.scrollToIndex(
                                      index,
                                      preferPosition: AutoScrollPosition.begin,
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        ),
                      SizedBox(
                        height: 42,
                        child: TextField(
                          controller: _searchController,
                          autofocus: false,
                          focusNode: _searchFocusNode,
                          decoration: InputDecoration(
                            filled: true,
                            hintText: L10n.of(context).search,
                            prefixIcon: const Icon(Icons.search_outlined),
                            contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: (s) => setState(() => searchFilter = s),
                        ),
                      ),
                    ],
                  ),
                ),
                if (packSlugs.isEmpty)
                  SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(L10n.of(context).noEmotesFound),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: () => UrlLauncher(
                              context,
                              'https://matrix.to/#/#hermes-stickers:janian.de',
                            ).launchUrl(),
                            icon: const Icon(Icons.explore_outlined),
                            label: Text(L10n.of(context).discover),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  SliverLayoutBuilder(
                    builder: (context, constraints) => SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => AutoScrollTag(
                          key: ValueKey(packSlugs[index]),
                          controller: _scrollController,
                          index: index,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              // Let even a short final pack reach the header.
                              minHeight:
                                  index == packSlugs.length - 1 &&
                                      !(searchFilter?.isNotEmpty ?? false)
                                  ? (constraints.viewportMainAxisExtent -
                                            kToolbarHeight * 2)
                                        .clamp(0.0, double.infinity)
                                  : 0,
                            ),
                            child: packBuilder(context, index),
                          ),
                        ),
                        childCount: packSlugs.length,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
