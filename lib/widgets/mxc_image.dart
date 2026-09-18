// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:hermes/config/themes.dart';
import 'package:hermes/utils/client_download_content_extension.dart';
import 'package:hermes/utils/matrix_sdk_extensions/matrix_file_extension.dart';
import 'package:hermes/utils/mxc_image_cache.dart';
import 'package:hermes/widgets/matrix.dart';
import 'package:lottie/lottie.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class MxcImage extends StatefulWidget {
  final Uri? uri;
  final Event? event;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final bool isThumbnail;
  final bool animated;
  final Duration retryDuration;
  final Duration animationDuration;
  final Curve animationCurve;
  final ThumbnailMethod thumbnailMethod;
  final Widget Function(BuildContext context)? placeholder;
  final String? cacheKey;
  final String? cacheName;
  final MxcImageCache? memoryCache;
  final Client? client;
  final BorderRadius borderRadius;

  static void clearCache(String cacheName) =>
      _MxcImageState._imageDataCaches.remove(cacheName);

  const MxcImage({
    this.uri,
    this.event,
    this.width,
    this.height,
    this.fit,
    this.placeholder,
    this.isThumbnail = true,
    this.animated = false,
    this.animationDuration = PantheonThemes.animationDuration,
    this.retryDuration = const Duration(seconds: 2),
    this.animationCurve = PantheonThemes.animationCurve,
    this.thumbnailMethod = ThumbnailMethod.scale,
    this.cacheKey,
    this.client,
    this.borderRadius = BorderRadius.zero,
    this.cacheName,
    this.memoryCache,
    super.key,
  });

  @override
  State<MxcImage> createState() => _MxcImageState();
}

class _MxcImageState extends State<MxcImage> {
  static final Map<String?, Map<String, Uint8List>> _imageDataCaches = {};
  Map<String, Uint8List> get _imageDataCache =>
      _imageDataCaches[widget.cacheName ?? ''] ??= {};

  Uint8List? _imageDataNoCache;
  Object? _memoryKey;
  MxcImageData? _memoryImageData;

  Object get _memoryCacheKey => (
    widget.client ?? widget.event?.room.client ?? Matrix.of(context).client,
    widget.uri,
    widget.isThumbnail,
    widget.isThumbnail ? widget.width : null,
    widget.isThumbnail ? widget.height : null,
    widget.isThumbnail ? MediaQuery.devicePixelRatioOf(context) : null,
    widget.thumbnailMethod,
    widget.animated,
  );

  MxcImageData? get _cachedImageData {
    final cache = widget.memoryCache;
    if (cache == null) return null;
    final key = _memoryCacheKey;
    if (_memoryKey != key) {
      _memoryKey = key;
      _memoryImageData = null;
    }
    return _memoryImageData ??= cache.get(key);
  }

  Uint8List? get _imageData =>
      _cachedImageData?.bytes ??
      (widget.cacheKey == null
          ? _imageDataNoCache
          : _imageDataCache[widget.cacheKey]);

  set _imageData(Uint8List? data) {
    if (data == null) return;
    final cacheKey = widget.cacheKey;
    cacheKey == null
        ? _imageDataNoCache = data
        : _imageDataCache[cacheKey] = data;
  }

  Future<void> _load() async {
    if (!mounted) return;
    final client =
        widget.client ?? widget.event?.room.client ?? Matrix.of(context).client;
    final uri = widget.uri;
    final event = widget.event;

    if (uri != null) {
      final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
      final width = widget.width;
      final realWidth = width == null ? null : width * devicePixelRatio;
      final height = widget.height;
      final realHeight = height == null ? null : height * devicePixelRatio;

      Future<Uint8List> loadImage() => client.downloadMxcCached(
        uri,
        width: realWidth,
        height: realHeight,
        thumbnailMethod: widget.thumbnailMethod,
        isThumbnail: widget.isThumbnail,
        animated: widget.animated,
      );

      final cache = widget.memoryCache;
      if (cache != null) {
        final key = _memoryCacheKey;
        final data = await cache.load(key, loadImage);
        if (!mounted || widget.memoryCache != cache || _memoryCacheKey != key) {
          return;
        }
        setState(() {
          _memoryKey = key;
          _memoryImageData = data;
        });
      } else {
        final remoteData = await loadImage();
        if (!mounted) return;
        setState(() {
          _imageData = remoteData;
        });
      }
    }

    if (event != null) {
      final useThumbnail = widget.isThumbnail && event.hasThumbnail;
      if (!useThumbnail &&
          !{
            MessageTypes.Image,
            MessageTypes.Sticker,
          }.contains(event.messageType)) {
        Logs().e('Event of type ${event.messageType} has no thumbnail!');
      }
      final data = await event.downloadAndDecryptAttachment(
        getThumbnail: useThumbnail,
      );
      if (data.detectFileType is MatrixImageFile) {
        if (!mounted) return;
        setState(() {
          _imageData = data.bytes;
        });
        return;
      }
    }
  }

  Future<void> _tryLoad() async {
    if (!mounted || _imageData != null) {
      return;
    }
    try {
      await _load();
    } on IOException catch (_) {
      if (!mounted) return;
      await Future.delayed(widget.retryDuration);
      _tryLoad();
    } on MatrixException catch (e) {
      Logs().d('Unable to load image', e);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryLoad());
  }

  @override
  void didUpdateWidget(covariant MxcImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.memoryCache != widget.memoryCache) {
      _memoryKey = null;
      _memoryImageData = null;
    }
    if (widget.memoryCache != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryLoad());
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _imageData;
    final hasData = data != null && data.isNotEmpty;
    final ungzippedLottieData = data == null
        ? null
        : (_cachedImageData ?? MxcImageData(data)).lottieBytes;

    Widget errorFallback(
      BuildContext context,
      Object error,
      StackTrace? stackTrace,
    ) {
      Logs().d('Unable to render mxc image', error, stackTrace);
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: Icon(
            Icons.broken_image_outlined,
            size: min(widget.height ?? 64, 64),
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      );
    }

    final imageChild = data == null
        ? _MxcImagePlaceholder(
            width: widget.width,
            height: widget.height,
            placeholder: widget.placeholder,
          )
        : (ungzippedLottieData != null
              ? Lottie.memory(
                  ungzippedLottieData,
                  width: widget.width,
                  height: widget.height,
                  fit: widget.fit,
                  errorBuilder: errorFallback,
                )
              : Image.memory(
                  data,
                  width: widget.width,
                  height: widget.height,
                  fit: widget.fit,
                  filterQuality: widget.isThumbnail
                      ? FilterQuality.low
                      : FilterQuality.medium,
                  errorBuilder: errorFallback,
                ));

    return AnimatedCrossFade(
      duration: PantheonThemes.animationDuration,
      firstChild: ClipRRect(
        borderRadius: widget.borderRadius,
        child: imageChild,
      ),
      secondChild: _MxcImagePlaceholder(
        width: widget.width,
        height: widget.height,
        placeholder: widget.placeholder,
      ),
      crossFadeState: hasData
          ? CrossFadeState.showFirst
          : CrossFadeState.showSecond,
    );
  }
}

class _MxcImagePlaceholder extends StatelessWidget {
  final double? width;
  final double? height;
  final Widget Function(BuildContext context)? placeholder;

  const _MxcImagePlaceholder({
    required this.width,
    required this.height,
    required this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    return placeholder?.call(context) ??
        Container(
          width: width,
          height: height,
          alignment: Alignment.center,
          child: const CircularProgressIndicator.adaptive(strokeWidth: 2),
        );
  }
}
