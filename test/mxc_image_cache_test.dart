// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/utils/mxc_image_cache.dart';
import 'package:hermes/widgets/mxc_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class _Database extends Fake implements DatabaseApi {
  int reads = 0;
  final result = Completer<Uint8List>();

  @override
  Future<Uint8List?> getFile(Uri uri) {
    reads++;
    return result.future;
  }
}

class _Client extends Fake implements Client {
  @override
  final _Database database = _Database();
}

Future<void> _mountImage(
  WidgetTester tester,
  Client client,
  MxcImageCache cache, {
  String id = 'sticker',
}) => tester.pumpWidget(
  MaterialApp(
    home: MxcImage(
      client: client,
      uri: Uri.parse('mxc://example.org/$id'),
      memoryCache: cache,
      isThumbnail: false,
      width: 128,
      height: 128,
    ),
  ),
);

void main() {
  test('concurrent loads share bytes and prepared Lottie data', () async {
    final cache = MxcImageCache();
    final pending = Completer<Uint8List>();
    final first = cache.load('sticker', () => pending.future);
    final second = cache.load('sticker', () => throw StateError('duplicate'));
    const json = '{"v":"5.5.7","layers":[]}';
    final bytes = Uint8List.fromList(GZipEncoder().encode(utf8.encode(json)));
    pending.complete(bytes);

    final data = await first;
    expect(await second, same(data));
    expect(cache.get('sticker'), same(data));
    expect(data.bytes, same(bytes));
    expect(utf8.decode(data.lottieBytes!), json);
    expect(data.sizeBytes, bytes.length + utf8.encode(json).length);
    expect(
      await cache.load('sticker', () => throw StateError('reloaded')),
      same(data),
    );
  });

  test('evicts least recently used entries to meet the byte limit', () async {
    final cache = MxcImageCache(maxBytes: 8);
    await cache.load('a', () async => Uint8List(4));
    await cache.load('b', () async => Uint8List(4));
    expect(cache.get('a'), isNotNull);
    await cache.load('c', () async => Uint8List(4));
    expect(cache.get('b'), isNull);
    expect(cache.get('a'), isNotNull);
    expect(cache.get('c'), isNotNull);
  });

  test('also bounds the number of entries', () async {
    final cache = MxcImageCache(maxEntries: 1);
    await cache.load('a', () async => Uint8List(1));
    await cache.load('b', () async => Uint8List(1));
    expect(cache.get('a'), isNull);
    expect(cache.get('b'), isNotNull);
  });

  test('oversized prepared animations do not evict cached stickers', () async {
    final bytes = Uint8List.fromList(
      GZipEncoder().encode(utf8.encode('{"v":"5","padding":"${'x' * 200}"}')),
    );
    final cache = MxcImageCache(maxBytes: bytes.length + 1);
    await cache.load('small', () async => Uint8List(1));
    final animation = await cache.load('animation', () async => bytes);
    expect(animation.lottieBytes, isNotNull);
    expect(cache.get('animation'), isNull);
    expect(cache.get('small'), isNotNull);
  });

  test('failed loads can be retried', () async {
    final cache = MxcImageCache();
    await expectLater(
      cache.load('sticker', () => throw StateError('failed')),
      throwsStateError,
    );
    final data = await cache.load('sticker', () async => Uint8List(1));
    expect(cache.get('sticker'), same(data));
  });

  testWidgets('a load finishes after unmount and is reused on the first frame', (
    tester,
  ) async {
    final cache = MxcImageCache();
    final client = _Client();
    await _mountImage(tester, client, cache);
    expect(client.database.reads, 1);
    await tester.pumpWidget(const SizedBox());
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX1sAAAAASUVORK5CYII=',
    );
    client.database.result.complete(bytes);
    await tester.pump();

    await _mountImage(tester, client, cache);
    expect(client.database.reads, 1);
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as MemoryImage).bytes, same(bytes));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // A different URI in the same widget state must not reuse the old image.
    await _mountImage(tester, client, cache, id: 'other');
    expect(client.database.reads, 2);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
