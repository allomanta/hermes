import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hermes/utils/horizontal_swipe_recognizer.dart';

typedef ReplyBackgroundBuilder = Widget Function(
  BuildContext context,
  bool leftToRight,
  double progress, // 0..1
);

/// Swipe-to-reply that animates the child, fires [onReply] once threshold
/// is crossed, then snaps back. Rejects early if initial motion is the
/// opposite direction so parents can win the arena.
class ReplySwipe extends StatefulWidget {
  const ReplySwipe({
    super.key,
    required this.child,
    required this.onReply,
    this.leftToRight = true,
    this.thresholdPx = 56.0,
    this.maxDragPx = 96.0,
    this.hapticOnThreshold = true,
    this.backgroundBuilder,
  });

  final Widget child;

  final VoidCallback onReply;
  final bool leftToRight;
  final double thresholdPx;
  final double maxDragPx;
  final bool hapticOnThreshold;
  final ReplyBackgroundBuilder? backgroundBuilder;

  @override
  State<ReplySwipe> createState() => _ReplySwipeState();
}

class _ReplySwipeState extends State<ReplySwipe> with TickerProviderStateMixin {
  double _dragX = 0.0; // >= 0
  bool _thresholdBuzzed = false;
  AnimationController? _snapBackAnimation;

  void _setDragX(double v) {
    final clamped = v.clamp(0.0, widget.maxDragPx).toDouble();
    if (clamped != _dragX) {
      setState(() => _dragX = clamped);
      final crossed = _dragX >= widget.thresholdPx;
      if (widget.hapticOnThreshold && crossed && !_thresholdBuzzed) {
        _thresholdBuzzed = true;
        HapticFeedback.vibrate();
      }
      if (!crossed) _thresholdBuzzed = false;
    }
  }

  Future<void> _snapBack() async {
    final start = _dragX;
    if (start == 0.0) return;

    final ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _snapBackAnimation = ctrl;

    final anim = Tween<double>(begin: start, end: 0.0).animate(
      CurvedAnimation(parent: ctrl, curve: Curves.easeOut),
    );

    void listener() => setState(() => _dragX = anim.value);
    ctrl.addListener(listener);

    try {
      await ctrl.forward();
      setState(() => _dragX = 0.0);
      ctrl.removeListener(listener);
    } finally {
      ctrl.dispose();
      _snapBackAnimation = null;
    }
  }

  @override
  void dispose() {
    _snapBackAnimation?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allowedSign = widget.leftToRight ? -1 : 1;
    final sign = allowedSign.toDouble();
    final progress = (_dragX / widget.maxDragPx).clamp(0.0, 1.0).toDouble();
    final backgroundBuilder = widget.backgroundBuilder;

    return RawGestureDetector(
      gestures: {
        HorizontalSwipeRecognizer:
            GestureRecognizerFactoryWithHandlers<HorizontalSwipeRecognizer>(
          () => HorizontalSwipeRecognizer(
            allowedSign: allowedSign,
          ),
          (rec) {
            rec.allowedSign = allowedSign;

            rec
              ..onStart = (details) {
                _snapBackAnimation?.dispose();
                _snapBackAnimation = null;
              }
              ..onUpdate = (details) {
                final delta = details.delta.dx * sign;
                if (delta >= 0) {
                  _setDragX(_dragX + delta);
                } else {
                  final next = _dragX + delta;
                  _setDragX(next >= 0 ? next : 0.0);
                }
              }
              ..onEnd = (_) async {
                final triggered = _dragX >= widget.thresholdPx;
                if (triggered) widget.onReply();
                await _snapBack();
              };
          },
        ),
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (backgroundBuilder != null)
            Positioned.fill(
              child: backgroundBuilder(
                context,
                widget.leftToRight,
                progress,
              ),
            ),
          Transform.translate(
            offset: Offset(sign * _dragX, 0.0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}
