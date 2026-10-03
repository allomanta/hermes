import 'package:hermes/config/themes.dart';
import 'package:hermes/l10n/l10n.dart';
import 'package:hermes/pages/chat_search/chat_search_files_tab.dart';
import 'package:hermes/pages/chat_search/chat_search_images_tab.dart';
import 'package:hermes/pages/chat_search/chat_search_links_tab.dart';
import 'package:hermes/pages/chat_search/chat_search_message_tab.dart';
import 'package:hermes/pages/chat_search/chat_search_page.dart';
import 'package:hermes/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:hermes/widgets/layouts/max_width_body.dart';
import 'package:material_ui/material_ui.dart';

class ChatSearchView extends StatelessWidget {
  final ChatSearchController controller;

  const ChatSearchView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final room = controller.room;
    if (room == null) {
      return Scaffold(
        appBar: AppBar(title: Text(L10n.of(context).oopsSomethingWentWrong)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(L10n.of(context).youAreNoLongerParticipatingInThisChat),
          ),
        ),
      );
    }

    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: const Center(child: BackButton()),
        titleSpacing: 0,
        title: Text(
          L10n.of(context).searchIn(
            room.getLocalizedDisplayname(MatrixLocals(L10n.of(context))),
          ),
        ),
      ),
      body: MaxWidthBody(
        withScrolling: false,
        child: Column(
          children: [
            if (PantheonThemes.isThreeColumnMode(context))
              const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: controller.searchController,
                onSubmitted: (_) => controller.restartSearch(),
                autofocus: true,
                enabled: controller.tabController.index == 0,
                decoration: InputDecoration(
                  hintText: L10n.of(context).search,
                  prefixIcon: const Icon(Icons.search_outlined),
                  filled: true,
                  fillColor: theme.colorScheme.secondaryContainer,
                  border: OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  hintStyle: TextStyle(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ),
            ),
            TabBar(
              controller: controller.tabController,
              tabs: [
                Tab(child: Text(L10n.of(context).messages)),
                Tab(child: Text(L10n.of(context).gallery)),
                Tab(child: Text(L10n.of(context).files)),
                Tab(child: Text(L10n.of(context).links)),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: controller.tabController,
                children: [
                  ChatSearchMessageTab(
                    searchQuery: controller.searchQuery,
                    room: room,
                    onStartSearch: () => controller.startSearch(0),
                    events: controller.messages,
                    endReached: controller.searches[0].endReached,
                    isLoading: controller.searches[0].isLoading,
                    hasError: controller.searches[0].hasError,
                    searchedUntil: controller.searches[0].searchedUntil,
                  ),
                  ChatSearchImagesTab(
                    room: room,
                    onStartSearch: () => controller.startSearch(1),
                    events: controller.images,
                    endReached: controller.searches[1].endReached,
                    isLoading: controller.searches[1].isLoading,
                    hasError: controller.searches[1].hasError,
                    searchedUntil: controller.searches[1].searchedUntil,
                  ),
                  ChatSearchFilesTab(
                    room: room,
                    onStartSearch: () => controller.startSearch(2),
                    events: controller.files,
                    endReached: controller.searches[2].endReached,
                    isLoading: controller.searches[2].isLoading,
                    hasError: controller.searches[2].hasError,
                    searchedUntil: controller.searches[2].searchedUntil,
                  ),
                  ChatSearchLinksTab(
                    room: room,
                    onStartSearch: () => controller.startSearch(3),
                    events: controller.links,
                    endReached: controller.searches[3].endReached,
                    isLoading: controller.searches[3].isLoading,
                    hasError: controller.searches[3].hasError,
                    searchedUntil: controller.searches[3].searchedUntil,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BackIntent extends Intent {}
