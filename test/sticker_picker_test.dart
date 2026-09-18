// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/l10n/l10n.dart';
import 'package:hermes/pages/chat/sticker_picker_dialog.dart';
import 'package:hermes/widgets/mxc_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class _Database extends Fake implements DatabaseApi {
  final reads = <Uri, int>{};
  final bytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX1sAAAAASUVORK5CYII=',
  );

  @override
  Future<Uint8List?> getFile(Uri uri) async {
    reads.update(uri, (count) => count + 1, ifAbsent: () => 1);
    return bytes;
  }
}

class _Client extends Fake implements Client {
  @override
  final _Database database = _Database();
  @override
  final Map<String, BasicEvent> accountData = {};
}

class _Room extends Fake implements Room {
  @override
  final _Client client = _Client();
  @override
  final Map<String, Map<String, StrippedStateEvent>> states = {
    'im.ponies.room_emotes': {
      for (var pack = 0; pack < 3; pack++)
        'pack-$pack': StrippedStateEvent(
          type: 'im.ponies.room_emotes',
          stateKey: 'pack-$pack',
          senderId: '@me:example.org',
          content: {
            'pack': {
              'display_name': 'Pack $pack',
              'avatar_url': 'https://example.org/avatar-$pack.png',
            },
            'images': {
              for (var image = 0; image < (pack == 2 ? 1 : 300); image++)
                'sticker-$pack-$image': {
                  'url': 'mxc://example.org/sticker-$pack-$image',
                },
            },
          },
        ),
    },
  };
}

Future<void> _mountPicker(
  WidgetTester tester,
  Room room, {
  double width = 400,
  void Function(ImagePackImageContent)? onSelected,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          height: 400,
          child: StickerPickerDialog(
            room: room,
            onSelected: onSelected ?? (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('large packs load visible stickers and reuse them on return', (
    tester,
  ) async {
    final room = _Room();
    await _mountPicker(tester, room);
    final stickers = find.byWidgetPredicate(
      (widget) => widget is MxcImage && !widget.isThumbnail,
    );
    expect(stickers.evaluate().length, lessThan(30));
    expect(
      room.client.database.reads.containsKey(
        Uri.parse('mxc://example.org/sticker-0-100'),
      ),
      isFalse,
    );

    final scroll = tester.widget<CustomScrollView>(
      find.byType(CustomScrollView),
    );
    scroll.controller!.jumpTo(1500);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('mxc://example.org/sticker-0-0')),
      findsNothing,
    );
    expect(stickers.evaluate().length, lessThan(40));
    scroll.controller!.jumpTo(0);
    await tester.pumpAndSettle();
    expect(
      room.client.database.reads[Uri.parse('mxc://example.org/sticker-0-0')],
      1,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('pack jumps align headers, including after resizing and search', (
    tester,
  ) async {
    final room = _Room();
    await _mountPicker(tester, room);
    final headerTop = tester
        .getTopLeft(find.widgetWithText(ListTile, 'Pack 0'))
        .dy;
    for (final pack in [1, 2, 0]) {
      await tester.tap(find.byTooltip('Pack $pack'));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.widgetWithText(ListTile, 'Pack $pack')).dy,
        closeTo(headerTop, 0.1),
      );
    }

    await _mountPicker(tester, room, width: 260);
    await tester.enterText(find.byType(TextField), 'no matches');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Pack 2'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    expect(
      tester.getTopLeft(find.widgetWithText(ListTile, 'Pack 2')).dy,
      closeTo(headerTop, 0.1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'search still filters stickers and selection preserves the body',
    (tester) async {
      ImagePackImageContent? selected;
      await _mountPicker(
        tester,
        _Room(),
        onSelected: (image) => selected = image,
      );
      await tester.enterText(find.byType(TextField), 'sticker-0-123');
      await tester.pumpAndSettle();
      final stickers = find.byWidgetPredicate(
        (widget) => widget is MxcImage && !widget.isThumbnail,
      );
      expect(stickers, findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('mxc://example.org/sticker-0-123')),
      );
      expect(selected?.body, 'sticker-0-123');
      expect(selected?.url.toString(), 'mxc://example.org/sticker-0-123');
      expect(tester.takeException(), isNull);
    },
  );
}
