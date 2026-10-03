// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:hermes/l10n/l10n.dart';
import 'package:hermes/pages/chat_search/chat_search_message_tab.dart';
import 'package:hermes/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class ChatListMessageSearch extends StatefulWidget {
  final Client client;
  final String query;

  const ChatListMessageSearch({
    required this.client,
    required this.query,
    super.key,
  });

  @override
  State<ChatListMessageSearch> createState() => _ChatListMessageSearchState();
}

class _ChatListMessageSearchState extends State<ChatListMessageSearch> {
  Timer? _debounce;
  int _generation = 0;
  int _visibleCount = 50;
  List<Event> _events = [];
  bool _isLoading = false;
  bool _failed = false;

  void _restartSearch() {
    _debounce?.cancel();
    final generation = ++_generation;
    setState(() {
      _events = [];
      _visibleCount = 50;
      _failed = false;
      _isLoading = widget.query.trim().isNotEmpty;
    });
    if (!_isLoading) return;
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => _search(generation),
    );
  }

  Future<void> _search(int generation) async {
    final client = widget.client;
    final query = widget.query.trim().toLowerCase();
    final events = <Event>[];
    final eventIds = <(String, String)>{};
    final rooms = client.rooms
        .where((room) => !room.isSpace && room.membership == Membership.join)
        .toList();
    try {
      for (final room in rooms) {
        var start = 0;
        while (true) {
          // searchEvents also downloads history. Only read the local timeline.
          final page = await client.database.getEventList(
            room,
            start: start,
            limit: 500,
          );
          if (!mounted || generation != _generation) return;
          if (page.isEmpty) break;
          start += 500;
          events.addAll(
            page.where(
              (event) =>
                  event.type == EventTypes.Message &&
                  !event.redacted &&
                  event.plaintextBody.toLowerCase().contains(query) &&
                  eventIds.add((room.id, event.eventId)),
            ),
          );
        }
      }
      events.sort((a, b) => b.originServerTs.compareTo(a.originServerTs));
      if (!mounted || generation != _generation) return;
      setState(() {
        _events = events;
        _isLoading = false;
      });
    } catch (e, s) {
      if (!mounted || generation != _generation) return;
      Logs().w('Unable to search local messages', e, s);
      setState(() {
        _isLoading = false;
        _failed = true;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _restartSearch();
  }

  @override
  void didUpdateWidget(covariant ChatListMessageSearch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.client, widget.client) ||
        oldWidget.query != widget.query) {
      _restartSearch();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _generation++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final count = _events.length < _visibleCount
        ? _events.length
        : _visibleCount;
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(l10n.messages, style: theme.textTheme.titleSmall),
          ),
        ),
        SliverList.builder(
          itemCount: count,
          itemBuilder: (context, i) {
            final event = _events[i];
            final sender = event.senderFromMemoryOrFallback;
            return MessageSearchResultListTile(
              sender: sender,
              displayname: sender.calcDisplayname(i18n: MatrixLocals(l10n)),
              event: event,
              room: event.room,
              showRoomName: true,
            );
          },
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: _isLoading
                  ? const CircularProgressIndicator.adaptive()
                  : _failed
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(l10n.oopsSomethingWentWrong),
                        TextButton(
                          onPressed: _restartSearch,
                          child: Text(l10n.tryAgain),
                        ),
                      ],
                    )
                  : _events.isEmpty
                  ? Text(l10n.nothingFound)
                  : count < _events.length
                  ? TextButton(
                      onPressed: () => setState(() => _visibleCount += 50),
                      child: Text(l10n.searchMore),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    );
  }
}
