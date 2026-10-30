import 'package:flutter/material.dart';

import 'queueb_motion.dart';

/// The existing InkWell owns input, activation and semantics. This builder only
/// supplies its highlight callback; no second tap/gesture handler is installed.
class QueueBPressMotion extends StatefulWidget {
  const QueueBPressMotion({
    super.key,
    required this.builder,
    this.enabled = true,
  });
  final Widget Function(ValueChanged<bool> onHighlightChanged) builder;
  final bool enabled;

  @override
  State<QueueBPressMotion> createState() => _QueueBPressMotionState();
}

class _QueueBPressMotionState extends State<QueueBPressMotion> {
  bool _pressed = false;

  @override
  void didUpdateWidget(covariant QueueBPressMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _pressed = false;
  }

  @override
  Widget build(BuildContext context) => AnimatedScale(
    scale: _pressed && widget.enabled && !QueueBMotion.reduced(context)
        ? QueueBMotion.pressedScale
        : 1,
    duration: QueueBMotion.duration(
      context,
      _pressed ? QueueBMotion.press : QueueBMotion.release,
    ),
    curve: QueueBMotion.position,
    child: widget.builder((pressed) {
      if (mounted && _pressed != pressed && widget.enabled) {
        setState(() => _pressed = pressed);
      }
    }),
  );
}

/// Uses a route's existing animation. No controller, navigation or callbacks.
/// Reduced/offstage motion stays settled until the next real push/pop cycle.
class QueueBRouteMotion extends StatefulWidget {
  const QueueBRouteMotion({
    super.key,
    required this.animation,
    required this.child,
    this.horizontalOffset = QueueBMotion.routeOffset,
    this.beginScale = 1,
    this.fade = true,
  });
  final Animation<double> animation;
  final Widget child;
  final double horizontalOffset, beginScale;
  final bool fade;

  @override
  State<QueueBRouteMotion> createState() => _QueueBRouteMotionState();
}

class _QueueBRouteMotionState extends State<QueueBRouteMotion> {
  bool _settled = false;
  AnimationStatus? _direction;

  @override
  void didUpdateWidget(covariant QueueBRouteMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      _settled = false;
      _direction = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduced = QueueBMotion.reduced(context);
    final active = TickerMode.valuesOf(context).enabled;
    return AnimatedBuilder(
      animation: widget.animation,
      child: widget.child,
      builder: (context, child) {
        final status = widget.animation.status;
        if (_direction != status &&
            (status == AnimationStatus.forward ||
                status == AnimationStatus.reverse)) {
          _settled = false;
        }
        _direction = status;
        if (reduced || !active) _settled = true;
        final curve = status == AnimationStatus.reverse
            ? QueueBMotion.exiting
            : QueueBMotion.entering;
        final value = _settled ? 1.0 : curve.transform(widget.animation.value);
        return Opacity(
          opacity: widget.fade ? value : 1,
          child: Transform.translate(
            offset: Offset(widget.horizontalOffset * (1 - value), 0),
            child: Transform.scale(
              scale: widget.beginScale + (1 - widget.beginScale) * value,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// Scale shares the native DialogRoute clock; native fade, focus, theme capture,
/// barriers, keyboard/Back handling and overlay ownership remain untouched.
class QueueBModalMotion extends StatelessWidget {
  const QueueBModalMotion({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final animation = ModalRoute.of(context)?.animation;
    return animation == null
        ? child
        : QueueBRouteMotion(
            animation: animation,
            horizontalOffset: 0,
            beginScale: QueueBMotion.modalScale,
            fade: false,
            child: child,
          );
  }
}
