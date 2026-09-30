// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:hermes/pages/chat_search/chat_search_view.dart';
import 'package:hermes/utils/matrix_sdk_extensions/event_links_extension.dart';
import 'package:hermes/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class ChatSearchPage extends StatefulWidget {
  final String roomId;
  const ChatSearchPage({required this.roomId, super.key});

  @override
  ChatSearchController createState() => ChatSearchController();
}

class ChatSearchController extends State<ChatSearchPage>
    with SingleTickerProviderStateMixin {
  Room? get room => Matrix.of(context).client.getRoomById(widget.roomId);

  final TextEditingController searchController = TextEditingController();
  late final TabController tabController;

  final List<Event> messages = [];
  final List<Event> images = [];
  final List<Event> files = [];
  final List<Event> links = [];
  String? messagesNextBatch, imagesNextBatch, filesNextBatch, linksNextBatch;
  bool messagesEndReached = false;
  bool imagesEndReached = false;
  bool filesEndReached = false;
  bool linksEndReached = false;
  bool linksIsLoading = false;
  int _linksSearchGeneration = 0;
  DateTime? linksSearchedUntil;
  bool isLoading = false;
  DateTime? searchedUntil;

  void restartSearch() {
    setState(() {
      messages.clear();
      images.clear();
      files.clear();
      links.clear();
      linksNextBatch = linksSearchedUntil = null;
      linksEndReached = linksIsLoading = false;
      _linksSearchGeneration++;
      messagesNextBatch = imagesNextBatch = filesNextBatch = searchedUntil =
          null;
      messagesEndReached = imagesEndReached = filesEndReached = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      startSearch();
    });
  }

  Future<void> startSearch() async {
    switch (tabController.index) {
      case 0:
        final searchQuery = searchController.text.trim();
        if (searchQuery.isEmpty) return;
        setState(() {
          isLoading = true;
        });
        final result = await room!.searchEvents(
          searchTerm: searchController.text.trim(),
          nextBatch: messagesNextBatch,
        );
        setState(() {
          isLoading = false;
          messages.addAll(result.events);
          messagesNextBatch = result.nextBatch;
          messagesEndReached = result.nextBatch == null;
          searchedUntil = result.searchedUntil;
        });
        return;
      case 1:
        setState(() {
          isLoading = true;
        });
        final result = await room!.searchEvents(
          searchFunc: (event) => {
            MessageTypes.Image,
            MessageTypes.Video,
          }.contains(event.messageType),
          nextBatch: imagesNextBatch,
        );
        setState(() {
          isLoading = false;
          images.addAll(result.events);
          imagesNextBatch = result.nextBatch;
          imagesEndReached = result.nextBatch == null;
          searchedUntil = result.searchedUntil;
        });
        return;
      case 2:
        setState(() {
          isLoading = true;
        });
        final result = await room!.searchEvents(
          searchFunc: (event) =>
              event.messageType == MessageTypes.File ||
              (event.messageType == MessageTypes.Audio &&
                  !event.content.containsKey('org.matrix.msc3245.voice')),
          nextBatch: filesNextBatch,
        );
        setState(() {
          isLoading = false;
          files.addAll(result.events);
          filesNextBatch = result.nextBatch;
          filesEndReached = result.nextBatch == null;
          searchedUntil = result.searchedUntil;
        });
        return;
      case 3:
        if (linksIsLoading || linksEndReached) return;
        final generation = _linksSearchGeneration;
        setState(() {
          linksIsLoading = true;
        });
        try {
          final result = await room!.searchEvents(
            searchFunc: (event) => event.sharedLinks.isNotEmpty,
            nextBatch: linksNextBatch,
          );
          if (!mounted || generation != _linksSearchGeneration) return;
          setState(() {
            final eventIds = links.map((event) => event.eventId).toSet();
            links.addAll(
              result.events.where((event) => eventIds.add(event.eventId)),
            );
            linksNextBatch = result.nextBatch;
            linksEndReached = result.nextBatch == null;
            linksSearchedUntil = result.searchedUntil;
          });
        } finally {
          if (mounted && generation == _linksSearchGeneration) {
            setState(() {
              linksIsLoading = false;
            });
          }
        }
        return;
      default:
        return;
    }
  }

  void _onTabChanged() {
    if (tabController.indexIsChanging) return;
    switch (tabController.index) {
      case 1:
      case 2:
      case 3:
        startSearch();
        break;
      case 0:
      default:
        restartSearch();
        break;
    }
  }

  @override
  void initState() {
    super.initState();
    tabController = TabController(initialIndex: 0, length: 4, vsync: this);
    tabController.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    tabController.removeListener(_onTabChanged);
    searchController.dispose();
    tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ChatSearchView(this);
}
