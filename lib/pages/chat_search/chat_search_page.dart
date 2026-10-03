// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:hermes/pages/chat_search/chat_search_history.dart';
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

class ChatSearchState {
  final List<Event> events = [];
  final eventIds = <String>{};
  ChatSearchHistory? history;
  int localOffset = 0;
  bool localLoaded = false;
  String? nextBatch;
  DateTime? searchedUntil;
  bool initialized = false;
  bool endReached = false;
  bool isLoading = false;
  bool hasError = false;
}

class ChatSearchController extends State<ChatSearchPage>
    with SingleTickerProviderStateMixin {
  Room? get room => Matrix.of(context).client.getRoomById(widget.roomId);

  final TextEditingController searchController = TextEditingController();
  late final TabController tabController;
  final searches = List.generate(4, (_) => ChatSearchState());
  String searchQuery = '';
  Timer? _debounce;

  List<Event> get messages => searches[0].events;
  List<Event> get images => searches[1].events;
  List<Event> get files => searches[2].events;
  List<Event> get links => searches[3].events;

  void restartSearch({bool debounce = false}) {
    _debounce?.cancel();
    final query = searchController.text.trim();
    if (query == searchQuery && searches[0].initialized) return;
    setState(() {
      searchQuery = query;
      searches[0] = ChatSearchState();
    });
    if (query.isEmpty) return;
    if (debounce) {
      _debounce = Timer(
        const Duration(milliseconds: 300),
        () => startSearch(0),
      );
    } else {
      startSearch(0);
    }
  }

  bool _isCurrent(int index, ChatSearchState state, Room searchRoom) =>
      mounted &&
      identical(searches[index], state) &&
      identical(room, searchRoom);

  void _appendResults(
    ChatSearchState state,
    Iterable<Event> events,
    int index,
    String query,
  ) {
    setState(() {
      state.events.addAll(
        events.where(
          (event) =>
              matches(event, index, query) && state.eventIds.add(event.eventId),
        ),
      );
      state.events.sort((a, b) => b.originServerTs.compareTo(a.originServerTs));
    });
  }

  bool matches(Event event, int index, String query) {
    if (event.type != EventTypes.Message || event.redacted) return false;
    switch (index) {
      case 0:
        return event.plaintextBody.toLowerCase().contains(query.toLowerCase());
      case 1:
        return {
          MessageTypes.Image,
          MessageTypes.Video,
        }.contains(event.messageType);
      case 2:
        return event.messageType == MessageTypes.File ||
            (event.messageType == MessageTypes.Audio &&
                !event.content.containsKey('org.matrix.msc3245.voice'));
      case 3:
        return event.sharedLinks.isNotEmpty;
      default:
        return false;
    }
  }

  Future<void> startSearch([int? tab]) async {
    final index = tab ?? tabController.index;
    final state = searches[index];
    final searchRoom = room;
    final query = searchQuery;
    if (searchRoom == null ||
        state.isLoading ||
        state.endReached ||
        (index == 0 && query.isEmpty)) {
      return;
    }
    setState(() {
      state.initialized = state.isLoading = true;
      state.hasError = false;
    });
    try {
      if (state.history == null) {
        state.history = ChatSearchHistory(searchRoom);
        state.nextBatch = state.history!.initialCursor;
      }
      while (!state.localLoaded) {
        final events = await state.history!.loadLocal(state.localOffset);
        if (!_isCurrent(index, state, searchRoom)) return;
        state.localOffset += ChatSearchHistory.localBatchSize;
        state.localLoaded =
            events.isEmpty || events.last.type == EventTypes.RoomCreate;
        state.endReached =
            state.localLoaded &&
            (state.nextBatch == null ||
                events.lastOrNull?.type == EventTypes.RoomCreate);
        state.searchedUntil =
            events.lastOrNull?.originServerTs ?? state.searchedUntil;
        _appendResults(state, events, index, query);
      }
      if (state.endReached) return;
      final result = await state.history!.loadRemote(state.nextBatch!);
      if (!_isCurrent(index, state, searchRoom)) return;
      _appendResults(state, result.events, index, query);
      setState(() {
        state.nextBatch = result.nextBatch;
        state.endReached = result.nextBatch == null;
        state.searchedUntil = result.searchedUntil ?? state.searchedUntil;
      });
    } catch (e, s) {
      if (!mounted || !identical(searches[index], state)) return;
      Logs().w('Unable to search chat history', e, s);
      setState(() => state.hasError = true);
    } finally {
      if (mounted && identical(searches[index], state)) {
        setState(() => state.isLoading = false);
      }
    }
  }

  void _onTabChanged() {
    if (!tabController.indexIsChanging &&
        !searches[tabController.index].initialized) {
      startSearch();
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
    _debounce?.cancel();
    tabController.removeListener(_onTabChanged);
    searchController.dispose();
    tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ChatSearchView(this);
}
