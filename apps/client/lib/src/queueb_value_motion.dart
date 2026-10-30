import 'package:flutter/material.dart';

import 'queueb_motion.dart';

/// Visual reaction to a changed, already-authoritative value. Hydration,
/// unavailable data, scope changes and identical snapshots are always static.
/// No event subscriptions, data arithmetic, business callbacks or timers.
class QueueBValueMotion extends StatefulWidget {
  const QueueBValueMotion({
    super.key,
    required this.value,
    required this.child,
    this.scope,
    this.available = true,
    this.highlight = false,
    this.animateChild = true,
    this.borderOnly = false,
    this.highlightColor = Colors.transparent,
    this.duration = QueueBMotion.realtime,
    this.radius = 12,
  });
  final Object? value, scope;
  final Widget child;
  final bool available, highlight, animateChild, borderOnly;
  final Color highlightColor;
  final Duration duration;
  final double radius;

  @override
  State<QueueBValueMotion> createState() => _QueueBValueMotionState();
}

class _QueueBValueMotionState extends State<QueueBValueMotion>
    with SingleTickerProviderStateMixin {
  AnimationController? _pulse;

  bool get _enabled =>
      !QueueBMotion.reduced(context) && TickerMode.valuesOf(context).enabled;

  void _settle() {
    _pulse?.stop();
    _pulse?.value = 1;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_enabled) _settle();
  }

  @override
  void didUpdateWidget(covariant QueueBValueMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.scope != oldWidget.scope ||
        !widget.available ||
        !oldWidget.available ||
        !_enabled) {
      _settle();
    } else if (widget.value != oldWidget.value) {
      if (widget.highlight) {
        _pulse ??= AnimationController(
          vsync: this,
          duration: QueueBMotion.highlight,
          value: 1,
        );
        _pulse!.forward(from: 0);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final child = !widget.animateChild
        ? widget.child
        : AnimatedSwitcher(
            key: ValueKey((widget.scope, widget.available, _enabled)),
            duration: widget.available && _enabled
                ? QueueBMotion.duration(context, widget.duration)
                : Duration.zero,
            switchInCurve: QueueBMotion.entering,
            switchOutCurve: QueueBMotion.exiting,
            transitionBuilder: (child, animation) => AnimatedBuilder(
              animation: animation,
              child: child,
              builder: (context, child) {
                final incoming = child!.key == ValueKey(widget.value);
                return Opacity(
                  opacity: animation.value,
                  alwaysIncludeSemantics: true,
                  child: Transform.translate(
                    offset: Offset(
                      0,
                      (incoming ? 6 : -6) * (1 - animation.value),
                    ),
                    child: child,
                  ),
                );
              },
            ),
            // One outgoing number, never an accessible duplicate or a long queue
            // of intermediate values. Current content owns the layout bounds.
            layoutBuilder: (current, previous) => Stack(
              alignment: AlignmentDirectional.centerStart,
              children: [
                if (previous.isNotEmpty)
                  Positioned.fill(
                    child: ExcludeSemantics(
                      child: IgnorePointer(child: previous.last),
                    ),
                  ),
                ?current,
              ],
            ),
            child: KeyedSubtree(
              key: ValueKey(widget.value),
              child: widget.child,
            ),
          );
    return AnimatedBuilder(
      animation: _pulse ?? const AlwaysStoppedAnimation<double>(1),
      child: child,
      builder: (context, child) {
        final strength = _pulse == null || !_enabled || !widget.highlight
            ? 0.0
            : 1 - QueueBMotion.entering.transform(_pulse!.value);
        return DecoratedBox(
          position: widget.borderOnly
              ? DecorationPosition.foreground
              : DecorationPosition.background,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            color: widget.borderOnly
                ? null
                : widget.highlightColor.withValues(alpha: .14 * strength),
            border: widget.borderOnly
                ? Border.all(
                    color: widget.highlightColor.withValues(
                      alpha: .55 * strength,
                    ),
                    width: 2,
                  )
                : null,
          ),
          child: child,
        );
      },
    );
  }

  @override
  void dispose() {
    _pulse?.dispose();
    super.dispose();
  }
}
