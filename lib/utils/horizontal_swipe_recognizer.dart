import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Custom recognizer that only accepts drags once movement exceeds touch slop
/// in the externally provided horizontal direction.
class HorizontalSwipeRecognizer extends HorizontalDragGestureRecognizer {
  HorizontalSwipeRecognizer({
    required this.allowedSign,
    this.onAccepted,
    this.allowedPointerKinds,
    super.debugOwner,
  });

  /// Pointer kinds callers can reuse when they only want touch/stylus input.
  static const Set<PointerDeviceKind> touchPointerKinds = {
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
  };

  /// The horizontal direction we treat as a valid swipe (+1 or -1).
  int allowedSign;

  final Set<PointerDeviceKind>? allowedPointerKinds;

  final VoidCallback? onAccepted;
  double _accumulatedDelta = 0.0;
  bool _resolvedDirection = false;
  PointerDeviceKind? _pointerKind;

  void _resetState() {
    _accumulatedDelta = 0.0;
    _resolvedDirection = false;
    _pointerKind = null;
  }

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (!_supportsKind(event.kind)) return;
    _resetState();
    _pointerKind = event.kind;
    super.addAllowedPointer(event);
  }

  @override
  void addAllowedPointerPanZoom(PointerPanZoomStartEvent event) {
    if (!_supportsPanZoomKind(event.kind)) return;
    _resetState();
    _pointerKind = event.kind;
    super.addAllowedPointerPanZoom(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (!_resolvedDirection &&
        (event is PointerMoveEvent || event is PointerPanZoomUpdateEvent)) {
      _pointerKind ??= event.kind;
      final deltaX = event is PointerMoveEvent
          ? event.localDelta.dx
          : (event as PointerPanZoomUpdateEvent).panDelta.dx;
      if (deltaX != 0.0) {
        final logicalDelta = deltaX * allowedSign;
        _accumulatedDelta += logicalDelta;
        final slop =
            computeHitSlop(_pointerKind ?? event.kind, gestureSettings);
        if (_accumulatedDelta.abs() > slop) {
          _resolvedDirection = true;
          if (_accumulatedDelta < 0) {
            resolve(GestureDisposition.rejected);
            stopTrackingPointer(event.pointer);
            _resetState();
            return;
          }
          resolve(GestureDisposition.accepted);
          onAccepted?.call();
        }
      }
    }
    super.handleEvent(event);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _resetState();
    super.didStopTrackingLastPointer(pointer);
  }

  bool _supportsKind(PointerDeviceKind kind) {
    if (kind == PointerDeviceKind.unknown) return true;
    final allowed = allowedPointerKinds;
    return allowed == null || allowed.contains(kind);
  }

  bool _supportsPanZoomKind(PointerDeviceKind kind) {
    if (kind == PointerDeviceKind.trackpad) return true;
    return _supportsKind(kind);
  }
}
