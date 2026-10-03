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
import 'package:provider/provider.dart';

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
  final visitedCursors = <String>{};
  int generation = 0;
  Completer<void>? cancellation;

  void cancel() {
    generation++;
    if (cancellation?.isCompleted == false) cancellation!.complete();
    cancellation = null;
    isLoading = false;
  }
}

class ChatSearchController extends State<ChatSearchPage>
    with SingleTickerProviderStateMixin {
  static const resultsPerPage = 20;
  static const maxRemotePages = 5;
  static const maxLocalPages = 20;
  static const maxSearchDuration = Duration(seconds: 30);
  Room? get room => Matrix.of(context).client.getRoomById(widget.roomId);

  final TextEditingController searchController = TextEditingController();
  late final TabController tabController;
  final searches = List.generate(4, (_) => ChatSearchState());
  String searchQuery = '';
  Timer? _debounce;
  ChatSearchHistory? _history;
  Room? _observedRoom;

  List<Event> get messages => searches[0].events;
  List<Event> get images => searches[1].events;
  List<Event> get files => searches[2].events;
  List<Event> get links => searches[3].events;

  void restartSearch({bool debounce = false}) {
    _debounce?.cancel();
    final query = searchController.text.trim();
    if (query == searchQuery && searches[0].initialized) return;
    setState(() {
      searches[0].cancel();
      searchQuery = query;
      searches[0] = ChatSearchState();
    });
    if (query.isEmpty) return;
    if (debounce) {
      _debounce = Timer(const Duration(milliseconds: 300), () {
        if (!searches[0].initialized) startSearch(0);
      });
    } else {
      startSearch(0);
    }
  }

  bool _isCurrent(
    int index,
    ChatSearchState state,
    Room searchRoom,
    int generation,
  ) =>
      mounted &&
      identical(searches[index], state) &&
      state.generation == generation &&
      identical(room, searchRoom);

  void stopSearch(int index, {bool hasError = false}) {
    setState(() {
      searches[index].cancel();
      searches[index].hasError = hasError;
    });
  }

  void _appendResults(
    ChatSearchState state,
    Iterable<Event> events,
    int index,
    String query,
  ) {
    final normalizedQuery = query.toLowerCase();
    setState(() {
      state.events.addAll(
        events.where((event) {
          if (event.type != EventTypes.Message || event.redacted) return false;
          final matches = switch (index) {
            0 => event.plaintextBody.toLowerCase().contains(normalizedQuery),
            1 => {
              MessageTypes.Image,
              MessageTypes.Video,
            }.contains(event.messageType),
            2 =>
              event.messageType == MessageTypes.File ||
                  (event.messageType == MessageTypes.Audio &&
                      !event.content.containsKey('org.matrix.msc3245.voice')),
            3 => event.sharedLinks.isNotEmpty,
            _ => false,
          };
          return matches && state.eventIds.add(event.eventId);
        }),
      );
      state.events.sort((a, b) => b.originServerTs.compareTo(a.originServerTs));
    });
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
    final generation = ++state.generation;
    final cancellation = state.cancellation = Completer<void>();
    final timeout = Timer(maxSearchDuration, () {
      if (_isCurrent(index, state, searchRoom, generation)) {
        stopSearch(index, hasError: true);
      }
    });
    final previousCount = state.events.length;
    try {
      if (state.history == null) {
        state.history = _history ??= ChatSearchHistory(searchRoom);
        state.nextBatch = state.history!.initialCursor;
      }
      for (
        var page = 0;
        !state.localLoaded &&
            page < maxLocalPages &&
            state.events.length - previousCount < resultsPerPage;
        page++
      ) {
        final events = await Future.any<List<Event>>([
          state.history!.loadLocal(state.localOffset),
          cancellation.future.then((_) => <Event>[]),
        ]);
        if (!_isCurrent(index, state, searchRoom, generation)) return;
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
        // Yield between cached batches so cancel and timeout timers can run.
        await Future<void>.delayed(Duration.zero);
        if (!_isCurrent(index, state, searchRoom, generation)) return;
      }
      if (!state.localLoaded || state.endReached) return;
      for (
        var page = 0;
        page < maxRemotePages &&
            !state.endReached &&
            state.events.length - previousCount < resultsPerPage;
        page++
      ) {
        final cursor = state.nextBatch!;
        final result = await Future.any<ChatSearchBatch>([
          state.history!.loadRemote(cursor),
          cancellation.future.then(
            (_) => (
              events: <Event>[],
              nextBatch: null,
              searchedUntil: null,
              hasUndecryptedEvents: false,
            ),
          ),
        ]);
        if (!_isCurrent(index, state, searchRoom, generation)) return;
        _appendResults(state, result.events, index, query);
        state.visitedCursors.add(cursor);
        final next = result.nextBatch;
        setState(() {
          state.searchedUntil = result.searchedUntil ?? state.searchedUntil;
          if (next != null && state.visitedCursors.contains(next)) {
            state.hasError = true;
          } else {
            state.nextBatch = next;
            state.endReached = next == null;
          }
        });
        if (state.hasError) {
          state.history!.invalidateRemote();
          break;
        }
      }
    } catch (e, s) {
      if (!_isCurrent(index, state, searchRoom, generation)) return;
      Logs().w('Unable to search chat history', e, s);
      setState(() => state.hasError = true);
    } finally {
      timeout.cancel();
      if (_isCurrent(index, state, searchRoom, generation)) {
        state.cancellation = null;
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

  void _updateRoom(Room? current) {
    if (identical(current, _observedRoom)) return;
    _observedRoom = current;
    _debounce?.cancel();
    _history?.dispose();
    _history = null;
    for (var i = 0; i < searches.length; i++) {
      searches[i].cancel();
      searches[i] = ChatSearchState();
    }
    if (searchQuery.isNotEmpty || tabController.index != 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) startSearch();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateRoom(
      Provider.of<MatrixState>(context).client.getRoomById(widget.roomId),
    );
  }

  @override
  void didUpdateWidget(covariant ChatSearchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roomId != widget.roomId) _updateRoom(room);
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
    for (final state in searches) {
      state.cancel();
    }
    _history?.dispose();
    tabController.removeListener(_onTabChanged);
    searchController.dispose();
    tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ChatSearchView(this);
}
