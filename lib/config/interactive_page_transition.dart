// transition.dart
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:hermes/config/app_config.dart';
import 'package:hermes/widgets/reply_swipeable.dart';

class SwipePopPage<T> extends Page<T> {
  SwipePopPage({
    required this.child,
    Duration? duration,
    this.curve = Curves.decelerate,
    this.reverseCurve = Curves.easeOutCubic,
    bool? enableFullScreenDrag,
    double? minimumDragFraction,
    double? velocityThreshold,
    super.key,
    super.name,
    super.arguments,
    super.restorationId,
  })  : duration = duration ?? AppConfig.swipePopDuration,
        enableFullScreenDrag =
            enableFullScreenDrag ?? AppConfig.swipePopEnableFullScreenDrag,
        minimumDragFraction =
            (minimumDragFraction ?? AppConfig.swipePopMinimumDragFraction)
                .clamp(0.0, 1.0),
        velocityThreshold =
            velocityThreshold ?? AppConfig.swipePopVelocityThreshold;

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
    required this.duration,
    required this.curve,
    required this.reverseCurve,
    required this.enableFullScreenDrag,
    required this.minimumDragFraction,
    required this.velocityThreshold,
    super.settings,
  }) : assert(minimumDragFraction >= 0 && minimumDragFraction <= 1);

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
  ) =>
      builder(context);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final wrapped = enableFullScreenDrag
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
      child: wrapped,
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
      ..onCancel = _handleDragCancel
      ..dragStartBehavior = DragStartBehavior.down;
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
        if (navigator.mounted) navigator.didStopUserGesture();
      });
      _controller = null;
    }
    super.dispose();
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (!widget.route.popGestureEnabled) return;
    _recognizer.addPointer(event);
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
    if (delta <= 0) return;
    _controller!.dragUpdate(delta);
  }

  void _handleDragEnd(DragEndDetails details) {
    if (_controller == null) return;
    final velocity = _convertToLogical(details.velocity.pixelsPerSecond.dx);
    final progress = 1 - widget.route.popGestureController.value;
    _controller!.dragEnd(velocity: velocity, dragFraction: progress);
    _controller = null;
  }

  void _handleDragCancel() {
    _controller?.dragCancel();
    _controller = null;
  }

  double _convertToLogical(double value) {
    final td = Directionality.of(context);
    return td == TextDirection.rtl ? -value : value;
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
      final dir = _effectiveTextDirection;
      final logicalDelta =
          dir == TextDirection.rtl ? -event.delta.dx : event.delta.dx;
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

  void dragUpdate(double delta) {
    controller.value = (controller.value - delta).clamp(0.0, 1.0);
  }

  void dragEnd({required double velocity, required double dragFraction}) {
    if (!getIsCurrent()) {
      _animateToPushed();
      return;
    }

    final shouldPop = (velocity > velocityThreshold)
        ? true
        : (velocity < -velocityThreshold)
            ? false
            : (dragFraction > minimumDragFraction);

    if (shouldPop) {
      navigator.pop();
      _listenUntilSettled();
    } else {
      _animateToPushed();
    }
  }

  void dragCancel() => _animateToPushed();

  void _animateToPushed() {
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
    final ms = math.max(1, (duration.inMilliseconds * distance).round());
    return Duration(milliseconds: ms);
  }
}

class BlockSwipeArea extends StatelessWidget {
  const BlockSwipeArea({
    super.key,
    this.direction = ReplySwipeDirection.startToEnd,
    required this.child,
  });

  final ReplySwipeDirection direction;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: {
        _SwipePopBlockRecognizer:
            GestureRecognizerFactoryWithHandlers<_SwipePopBlockRecognizer>(
          () => _SwipePopBlockRecognizer(debugOwner: this),
          (recognizer) {
            recognizer
              ..onStart = (_) {}
              ..onUpdate = (_) {}
              ..onEnd = (_) {}
              ..onCancel = () {}
              ..gestureSettings = MediaQuery.maybeGestureSettingsOf(context)
              ..textDirection = Directionality.of(context)
              ..dragStartBehavior = DragStartBehavior.down
              ..direction = direction;
          },
        ),
      },
      child: child,
    );
  }
}

class _SwipePopBlockRecognizer extends HorizontalDragGestureRecognizer {
  _SwipePopBlockRecognizer({super.debugOwner});

  ReplySwipeDirection direction = ReplySwipeDirection.startToEnd;
  TextDirection _textDirection = TextDirection.ltr;

  set textDirection(TextDirection value) {
    _textDirection = value;
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent &&
        !hasSufficientGlobalDistanceToAccept(
          event.kind,
          gestureSettings?.touchSlop,
        )) {
      final logicalDelta = _textDirection == TextDirection.rtl
          ? -event.delta.dx
          : event.delta.dx;
      final sign = direction == ReplySwipeDirection.endToStart ? -1.0 : 1.0;
      // Block drags moving in the same direction as the pop gesture.
      if (logicalDelta * sign > 0) {
        resolve(GestureDisposition.accepted);
        return;
      }
      // Allow opposite drags to pass through to other recognizers.
      if (logicalDelta * sign < 0) {
        resolve(GestureDisposition.rejected);
        stopTrackingPointer(event.pointer);
        return;
      }
    }
    super.handleEvent(event);
  }

  @override
  String get debugDescription => 'swipePopBlocker';
}
