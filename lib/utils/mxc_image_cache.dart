import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

class MxcImageData {
  final Uint8List bytes;
  Uint8List? _lottieBytes;
  Uint8List? get lottieBytes => _lottieBytes;

  MxcImageData(this.bytes) {
    if (bytes.length < 2 || bytes[0] != 0x1f || bytes[1] != 0x8b) return;
    // Cache the entire animation for Lottie
    try {
      final decompressed = GZipDecoder().decodeBytes(bytes);
      final jsonString = utf8.decode(decompressed);
      final json = jsonDecode(jsonString);
      if (json is Map && json.containsKey('v')) {
        _lottieBytes = Uint8List.fromList(utf8.encode(jsonString));
      }
    } catch (_) {
      // Only Lottie has extra caching
    }
  }

  int get sizeBytes => bytes.lengthInBytes + (lottieBytes?.lengthInBytes ?? 0);
}

class MxcImageCache {
  final int maxBytes;
  final int maxEntries;
  final _entries = <Object, MxcImageData>{};
  final _pending = <Object, Future<MxcImageData>>{};
  int _sizeBytes = 0;

  // Cap cache at 64MB or 256 stickers
  MxcImageCache({this.maxBytes = 64 * 1024 * 1024, this.maxEntries = 256})
    : assert(maxBytes >= 0),
      assert(maxEntries >= 0);

  MxcImageData? get(Object key) {
    final data = _entries.remove(key);
    if (data != null) _entries[key] = data;
    return data;
  }

  Future<MxcImageData> load(
    Object key,
    Future<Uint8List> Function() loader,
  ) async {
    final cached = get(key);
    if (cached != null) return cached;
    final pending = _pending[key];
    if (pending != null) return pending;

    final future = Future<Uint8List>.sync(loader).then(MxcImageData.new);
    _pending[key] = future;
    try {
      final data = await future;
      if (maxEntries > 0 && data.sizeBytes <= maxBytes) {
        while (_entries.isNotEmpty &&
            (_entries.length >= maxEntries ||
                _sizeBytes + data.sizeBytes > maxBytes)) {
          _sizeBytes -= _entries.remove(_entries.keys.first)!.sizeBytes;
        }
        _entries[key] = data;
        _sizeBytes += data.sizeBytes;
      }
      return data;
    } finally {
      _pending.remove(key);
    }
  }
}
