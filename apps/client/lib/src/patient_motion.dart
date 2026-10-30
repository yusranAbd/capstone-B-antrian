import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Presentation-only identity. It contains no patient or booking data.
class PatientMotionOnce {
  bool _consumed = false;

  bool take() {
    if (_consumed) return false;
    _consumed = true;
    return true;
  }
}

/// A finite patient-only entrance; text remains visible and semantic throughout.
class PatientMicroEntrance extends StatefulWidget {
  const PatientMicroEntrance({
    super.key,
    required this.once,
    required this.child,
  });

  final PatientMotionOnce once;
  final Widget child;
  static const duration = Duration(milliseconds: 200);
  static const minimumOpacity = 0.88;

  @override
  State<PatientMicroEntrance> createState() => _PatientMicroEntranceState();
}

class _PatientMicroEntranceState extends State<PatientMicroEntrance> {
  bool _observed = false, _play = false;

  void _observe() {
    final active = TickerMode.valuesOf(context).enabled;
    final reduced = MediaQuery.disableAnimationsOf(context);
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
  void didUpdateWidget(covariant PatientMicroEntrance oldWidget) {
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
              begin: PatientMicroEntrance.minimumOpacity,
              end: 1,
              duration: PatientMicroEntrance.duration,
              curve: Curves.easeOut,
            )
            .moveY(
              begin: 3,
              end: 0,
              duration: PatientMicroEntrance.duration,
              curve: Curves.easeOut,
            );
}
