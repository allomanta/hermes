import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';

class SwipePopPage<T> extends Page<T> {
  const SwipePopPage({
    required this.child,
    this.duration = const Duration(milliseconds: 280),
    this.curve = Curves.decelerate,
    this.reverseCurve = Curves.easeOutCubic,
    this.enableFullScreenDrag = true,
    this.minimumDragFraction = 0.3,
    this.velocityThreshold = 350.0,
    super.key,
    super.name,
    super.arguments,
    super.restorationId,
  });

  final Widget child;
  final Duration duration;
  final Curve curve;
  final Curve reverseCurve;
  final bool enableFullScreenDrag;
  final double minimumDragFraction;
  final double velocityThreshold;

  @override
  Route<T> createRoute(BuildContext context) {
    return SwipePopPageRoute<T>(
      builder: (_) => child,
      duration: duration,
      curve: curve,
      reverseCurve: reverseCurve,
      enableFullScreenDrag: enableFullScreenDrag,
      minimumDragFraction: minimumDragFraction,
      velocityThreshold: velocityThreshold,
      settings: this,
    );
  }
}

class SwipePopPageRoute<T> extends PageRoute<T> {
  SwipePopPageRoute({
    required this.builder,
    this.duration = const Duration(milliseconds: 280),
    this.curve = Curves.decelerate,
    this.reverseCurve = Curves.easeOutCubic,
    this.enableFullScreenDrag = true,
    this.minimumDragFraction = 0.3,
    this.velocityThreshold = 350.0,
    super.settings,
  }) {
    assert(minimumDragFraction >= 0 && minimumDragFraction <= 1);
  }

  final WidgetBuilder builder;
  final Duration duration;
  final Curve curve;
  final Curve reverseCurve;
  final bool enableFullScreenDrag;
  final double minimumDragFraction;
  final double velocityThreshold;

  @override
  bool get opaque => true;

  @override
  bool get barrierDismissible => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => duration;

  @override
  Duration get reverseTransitionDuration => duration;

  @override
  bool get popGestureEnabled => enableFullScreenDrag;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return builder(context);
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final wrappedChild = enableFullScreenDrag
        ? _FullScreenPopGestureDetector<T>(
            route: this,
            minimumDragFraction: minimumDragFraction,
            velocityThreshold: velocityThreshold,
            child: child,
          )
        : child;

    return CupertinoPageTransition(
      primaryRouteAnimation: animation,
      secondaryRouteAnimation: secondaryAnimation,
      linearTransition: navigator?.userGestureInProgress ?? false,
      child: wrappedChild,
    );
  }

  AnimationController get popGestureController => controller!;

  NavigatorState get popGestureNavigator => navigator!;
}

class _FullScreenPopGestureDetector<T> extends StatefulWidget {
  const _FullScreenPopGestureDetector({
    required this.route,
    required this.child,
    required this.minimumDragFraction,
    required this.velocityThreshold,
  });

  final SwipePopPageRoute<T> route;
  final Widget child;
  final double minimumDragFraction;
  final double velocityThreshold;

  @override
  State<_FullScreenPopGestureDetector<T>> createState() =>
      _FullScreenPopGestureDetectorState<T>();
}

class _FullScreenPopGestureDetectorState<T>
    extends State<_FullScreenPopGestureDetector<T>> {
  _FullScreenPopGestureController<T>? _controller;
  late _RightSwipeDragGestureRecognizer _recognizer;

  @override
  void initState() {
    super.initState();
    _recognizer = _RightSwipeDragGestureRecognizer(debugOwner: this)
      ..onStart = _handleDragStart
      ..onUpdate = _handleDragUpdate
      ..onEnd = _handleDragEnd
      ..onCancel = _handleDragCancel;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _recognizer.gestureSettings = MediaQuery.maybeGestureSettingsOf(context);
    _recognizer.contextTextDirection = Directionality.of(context);
  }

  @override
  void dispose() {
    _recognizer.dispose();
    if (_controller != null) {
      final navigator = _controller!.navigator;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (navigator.mounted) {
          navigator.didStopUserGesture();
        }
      });
      _controller = null;
    }
    super.dispose();
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (widget.route.popGestureEnabled) {
      _recognizer.addPointer(event);
    }
  }

  void _handleDragStart(DragStartDetails details) {
    widget.route.popGestureController.stop();
    _controller = _FullScreenPopGestureController<T>(
      route: widget.route,
      duration: widget.route.duration,
      forwardCurve: widget.route.curve,
      reverseCurve: widget.route.reverseCurve,
      minimumDragFraction: widget.minimumDragFraction,
      velocityThreshold: widget.velocityThreshold,
    );
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (_controller == null) return;
    final size = context.size;
    if (size == null || size.width == 0) return;
    final delta = _convertToLogical((details.primaryDelta ?? 0) / size.width);
    if (delta == 0) return;
    _controller!.dragUpdate(delta);
  }

  void _handleDragEnd(DragEndDetails details) {
    if (_controller == null) return;
    final velocity = _convertToLogical(details.velocity.pixelsPerSecond.dx);
    final progress = 1 - widget.route.popGestureController.value;
    _controller!.dragEnd(
      velocity: velocity,
      dragFraction: progress,
    );
    _controller = null;
  }

  void _handleDragCancel() {
    _controller?.dragCancel();
    _controller = null;
  }

  double _convertToLogical(double value) {
    final textDirection = Directionality.of(context);
    return textDirection == TextDirection.rtl ? -value : value;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _handlePointerDown,
      behavior: HitTestBehavior.translucent,
      child: widget.child,
    );
  }
}

class _RightSwipeDragGestureRecognizer extends HorizontalDragGestureRecognizer {
  _RightSwipeDragGestureRecognizer({super.debugOwner});

  double _accumulatedDelta = 0.0;
  bool _resolvedDirection = false;
  TextDirection? _textDirection;

  set contextTextDirection(TextDirection direction) {
    _textDirection = direction;
  }

  TextDirection get _effectiveTextDirection =>
      _textDirection ?? TextDirection.ltr;

  @override
  void addPointer(PointerDownEvent event) {
    _accumulatedDelta = 0.0;
    _resolvedDirection = false;
    super.addPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent && !_resolvedDirection) {
      final direction = _effectiveTextDirection;
      final logicalDelta =
          direction == TextDirection.rtl ? -event.delta.dx : event.delta.dx;
      _accumulatedDelta += logicalDelta;
      if (_accumulatedDelta.abs() > kTouchSlop) {
        _resolvedDirection = true;
        if (_accumulatedDelta < 0) {
          resolve(GestureDisposition.rejected);
          stopTrackingPointer(event.pointer);
          return;
        }
      }
    }
    super.handleEvent(event);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _resolvedDirection = false;
    _accumulatedDelta = 0.0;
    super.didStopTrackingLastPointer(pointer);
  }
}

class _FullScreenPopGestureController<T> {
  _FullScreenPopGestureController({
    required SwipePopPageRoute<T> route,
    required this.duration,
    required this.forwardCurve,
    required this.reverseCurve,
    required this.minimumDragFraction,
    required this.velocityThreshold,
  })  : controller = route.popGestureController,
        navigator = route.popGestureNavigator {
    getIsCurrent = () => route.isCurrent;
    getIsActive = () => route.isActive;
    navigator.didStartUserGesture();
  }

  final AnimationController controller;
  final NavigatorState navigator;
  final Duration duration;
  final Curve forwardCurve;
  final Curve reverseCurve;
  final double minimumDragFraction;
  final double velocityThreshold;
  late final bool Function() getIsCurrent;
  late final bool Function() getIsActive;

  void dragUpdate(double delta) {
    controller.value = (controller.value - delta).clamp(0.0, 1.0);
  }

  void dragEnd({required double velocity, required double dragFraction}) {
    if (!getIsCurrent()) {
      controller.animateTo(
        1.0,
        duration: _scaledDuration(1.0),
        curve: forwardCurve,
      );
      _listenUntilSettled();
      return;
    }
    final bool shouldPop;
    if (velocity > velocityThreshold) {
      shouldPop = true;
    } else if (velocity < -velocityThreshold) {
      shouldPop = false;
    } else {
      shouldPop = dragFraction > minimumDragFraction;
    }

    if (shouldPop) {
      navigator.pop();
      _listenUntilSettled();
    } else {
      controller.animateTo(
        1.0,
        duration: _scaledDuration(1.0),
        curve: forwardCurve,
      );
      _listenUntilSettled();
    }
  }

  void dragCancel() {
    controller.animateTo(
      1.0,
      duration: _scaledDuration(1.0),
      curve: forwardCurve,
    );
    _listenUntilSettled();
  }

  void _listenUntilSettled() {
    void listener(AnimationStatus status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        navigator.didStopUserGesture();
        controller.removeStatusListener(listener);
      }
    }

    controller.addStatusListener(listener);
  }

  Duration _scaledDuration(double target) {
    final distance = (controller.value - target).abs();
    final int milliseconds =
        math.max(1, (duration.inMilliseconds * distance).round());
    return Duration(milliseconds: milliseconds);
  }
}
