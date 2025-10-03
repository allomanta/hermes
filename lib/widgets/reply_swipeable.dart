// swipe.dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:hermes/config/app_config.dart';

enum ReplySwipeDirection { startToEnd, endToStart }

class ReplySwipeable extends StatefulWidget {
  ReplySwipeable({
    required this.child,
    required this.onSwipe,
    this.background,
    double? dismissThreshold,
    double? maxOffsetFraction,
    Duration? movementDuration,
    double? velocityThreshold,
    this.direction = ReplySwipeDirection.endToStart,
    super.key,
  })  : dismissThreshold =
            (dismissThreshold ?? AppConfig.replySwipeDismissThreshold)
                .clamp(0.0, 1.0),
        maxOffsetFraction =
            (maxOffsetFraction ?? AppConfig.replySwipeMaxOffsetFraction)
                .clamp(0.0, 1.0),
        movementDuration =
            movementDuration ?? AppConfig.replySwipeMovementDuration,
        velocityThreshold =
            velocityThreshold ?? AppConfig.replySwipeVelocityThreshold;

  final Widget child;
  final Widget? background;
  final VoidCallback onSwipe;

  final double dismissThreshold;
  final double maxOffsetFraction;
  final Duration movementDuration;
  final double velocityThreshold;

  final ReplySwipeDirection direction;

  @override
  State<ReplySwipeable> createState() => _ReplySwipeableState();
}

class _ReplySwipeableState extends State<ReplySwipeable>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  double _currentOffset = 0.0;
  double _width = 0.0;
  double _maxSlide = 0.0;
  double _dragExtent = 0.0; // negative when swiping left, positive right

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.movementDuration,
    )..addListener(() {
        final v = _animation.value;
        if (v != _currentOffset) setState(() => _currentOffset = v);
      });
    _animation = const AlwaysStoppedAnimation<double>(0.0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _animateTo(double target) {
    _animation = Tween<double>(begin: _currentOffset, end: target).animate(
      CurvedAnimation(parent: _controller, curve: Curves.decelerate),
    );
    _controller
      ..reset()
      ..forward();
  }

  void _handleDragStart(DragStartDetails details) {
    _controller.stop();
    final sign =
        widget.direction == ReplySwipeDirection.endToStart ? -1.0 : 1.0;
    if (_maxSlide > 0 && _width > 0) {
      final progress = _currentOffset / _maxSlide;
      _dragExtent = sign * progress * _width; // resume smoothly
    } else {
      _dragExtent = 0.0;
    }
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (_width == 0.0) return;
    final delta = details.primaryDelta ?? 0.0;
    final sign =
        widget.direction == ReplySwipeDirection.endToStart ? -1.0 : 1.0;

    _dragExtent = (_dragExtent + delta).clamp(-_width, _width);
    final projected = (_dragExtent * sign).clamp(0.0, _width); // our direction
    final slide = (projected / _width) * _maxSlide;
    final clamped = slide.clamp(0.0, _maxSlide);

    if (clamped != _currentOffset) setState(() => _currentOffset = clamped);
  }

  void _handleDragEnd(DragEndDetails details) {
    final sign =
        widget.direction == ReplySwipeDirection.endToStart ? -1.0 : 1.0;

    final dragProgress =
        _width == 0 ? 0.0 : (_dragExtent * sign / _width).clamp(0.0, 1.0);
    final directionalVelocity = details.velocity.pixelsPerSecond.dx * sign;

    final shouldTrigger = dragProgress >= widget.dismissThreshold ||
        directionalVelocity > widget.velocityThreshold;

    if (shouldTrigger) {
      widget.onSwipe();
    }
    _animateTo(0.0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth;
        _maxSlide = (_width.isFinite ? _width : 0.0) * widget.maxOffsetFraction;

        final gestures = <Type, GestureRecognizerFactory>{
          _DirectionalSwipeDragGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<
                  _DirectionalSwipeDragGestureRecognizer>(
            () => _DirectionalSwipeDragGestureRecognizer(debugOwner: this),
            (recognizer) {
              recognizer.onStart = _handleDragStart;
              recognizer.onUpdate = _handleDragUpdate;
              recognizer.onEnd = _handleDragEnd;
              recognizer.onCancel = () => _animateTo(0.0);
              recognizer.gestureSettings =
                  MediaQuery.maybeGestureSettingsOf(context);
              recognizer.textDirection = Directionality.of(context);
              recognizer.dragStartBehavior = DragStartBehavior.down;
              recognizer.direction = widget.direction;
            },
          ),
        };

        final sign =
            widget.direction == ReplySwipeDirection.endToStart ? -1.0 : 1.0;

        Widget content = Transform.translate(
          offset: Offset(sign * _currentOffset, 0.0),
          child: widget.child,
        );

        if (widget.background != null) {
          content = Stack(
            alignment: widget.direction == ReplySwipeDirection.endToStart
                ? Alignment.centerRight
                : Alignment.centerLeft,
            children: [
              Positioned.fill(child: widget.background!),
              content,
            ],
          );
        }

        return RawGestureDetector(
          gestures: gestures,
          behavior: HitTestBehavior.opaque,
          child: content,
        );
      },
    );
  }
}

class _DirectionalSwipeDragGestureRecognizer
    extends HorizontalDragGestureRecognizer {
  _DirectionalSwipeDragGestureRecognizer({super.debugOwner});

  TextDirection _textDirection = TextDirection.ltr;
  ReplySwipeDirection direction = ReplySwipeDirection.endToStart;

  set textDirection(TextDirection d) => _textDirection = d;

  @override
  void handleEvent(PointerEvent event) {
    // Enforce direction before acceptance; reject the "wrong" way so parents can win.
    if (event is PointerMoveEvent &&
        !hasSufficientGlobalDistanceToAccept(
          event.kind,
          gestureSettings?.touchSlop,
        )) {
      final logicalDelta = _textDirection == TextDirection.rtl
          ? -event.delta.dx
          : event.delta.dx;
      final sign = direction == ReplySwipeDirection.endToStart ? -1.0 : 1.0;
      if (logicalDelta * sign < 0) {
        resolve(GestureDisposition.rejected);
        stopTrackingPointer(event.pointer);
        return;
      }
    }
    super.handleEvent(event);
  }

  @override
  String get debugDescription => 'replySwipeDrag';
}
