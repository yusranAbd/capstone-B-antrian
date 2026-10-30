import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Local presentation tokens; no theme, route or business behavior.
abstract final class QueueBMotion {
  static const instant = Duration.zero;
  static const fast = Duration(milliseconds: 160);
  static const standard = Duration(milliseconds: 200);
  static const emphasis = Duration(milliseconds: 260);
  static const curve = Curves.easeOut;
  static const minimumOpacity = 0.88;
  static const verticalOffset = 3.0;
}

/// Presentation-only identity; no account, patient or backend event data.
class QueueBMotionOnce {
  bool _consumed = false;

  bool take() {
    if (_consumed) return false;
    _consumed = true;
    return true;
  }
}

/// A finite local entrance; text remains visible and semantic throughout.
class QueueBMicroEntrance extends StatefulWidget {
  const QueueBMicroEntrance({
    super.key,
    required this.once,
    required this.child,
    this.effectDuration = QueueBMotion.standard,
  });

  final QueueBMotionOnce once;
  final Widget child;
  final Duration effectDuration;
  static const minimumOpacity = QueueBMotion.minimumOpacity;

  @override
  State<QueueBMicroEntrance> createState() => _QueueBMicroEntranceState();
}

class _QueueBMicroEntranceState extends State<QueueBMicroEntrance> {
  bool _observed = false, _play = false;

  void _observe() {
    final active = TickerMode.valuesOf(context).enabled;
    final reduced =
        MediaQuery.disableAnimationsOf(context) ||
        widget.effectDuration == QueueBMotion.instant;
    // Retained offstage branches must not consume a newly confirmed event.
    if (!_observed && active) {
      _observed = true;
      _play = widget.once.take() && !reduced;
    }
    // Leaving during motion settles the presentation; returning never replays.
    if (!active || reduced) _play = false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _observe();
  }

  @override
  void didUpdateWidget(covariant QueueBMicroEntrance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.once, widget.once)) {
      _observed = _play = false;
    }
    _observe();
  }

  @override
  Widget build(BuildContext context) => !_play
      ? widget.child
      : widget.child
            .animate(key: ObjectKey(widget.once))
            .fade(
              begin: QueueBMicroEntrance.minimumOpacity,
              end: 1,
              duration: widget.effectDuration,
              curve: QueueBMotion.curve,
            )
            .moveY(
              begin: QueueBMotion.verticalOffset,
              end: 0,
              duration: widget.effectDuration,
              curve: QueueBMotion.curve,
            );
}

/// Observe a confirmed feedback transition without listeners or business work.
/// Initial hydration and remounts are static; callers retain this presentation
/// slot while feedback is absent so a later false-to-true edge is meaningful.
class QueueBConfirmedFeedback extends StatefulWidget {
  const QueueBConfirmedFeedback({
    super.key,
    required this.confirmed,
    required this.child,
  });
  final bool confirmed;
  final Widget child;

  @override
  State<QueueBConfirmedFeedback> createState() =>
      _QueueBConfirmedFeedbackState();
}

class _QueueBConfirmedFeedbackState extends State<QueueBConfirmedFeedback> {
  QueueBMotionOnce? _event;

  @override
  void didUpdateWidget(covariant QueueBConfirmedFeedback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.confirmed) {
      _event = null;
    } else if (!oldWidget.confirmed) {
      final event = _event = QueueBMotionOnce();
      // Operational feedback arriving offstage should stay settled on return.
      if (!TickerMode.valuesOf(context).enabled) event.take();
    }
  }

  @override
  Widget build(BuildContext context) => _event == null
      ? widget.child
      : QueueBMicroEntrance(once: _event!, child: widget.child);
}
