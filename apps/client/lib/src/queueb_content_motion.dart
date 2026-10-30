import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'queueb_motion.dart';

/// A bounded, one-shot entrance for initially visible content only. The owner
/// keeps the token across lazy remounts. Cached/offscreen cards settle statically;
/// no scroll listeners, timers, or offscreen animation sequences are installed.
class QueueBContentEntrance extends StatefulWidget {
  const QueueBContentEntrance({
    super.key,
    required this.once,
    required this.index,
    required this.child,
  });
  final QueueBMotionOnce once;
  final int index;
  final Widget child;

  @override
  State<QueueBContentEntrance> createState() => _QueueBContentEntranceState();
}

class _QueueBContentEntranceState extends State<QueueBContentEntrance> {
  bool _checked = false, _play = false;
  late int _ordinal;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  void _prepare() {
    _ordinal = widget.index;
    _play = false;
    _checked = _ordinal < 0 || _ordinal >= 5 || !widget.once.take();
    if (!_checked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _checked) return;
        final box = context.findRenderObject();
        var visible = false;
        if (box is RenderBox && box.hasSize) {
          final viewport = RenderAbstractViewport.maybeOf(box);
          if (viewport != null && viewport is RenderBox) {
            final rect = MatrixUtils.transformRect(
              box.getTransformTo(viewport),
              box.paintBounds,
            );
            visible = viewport.paintBounds.overlaps(rect);
          } else {
            visible = (box.localToGlobal(Offset.zero) & box.size).overlaps(
              Offset.zero & MediaQuery.sizeOf(context),
            );
          }
        }
        setState(() {
          _checked = true;
          _play =
              visible &&
              !QueueBMotion.reduced(context) &&
              TickerMode.valuesOf(context).enabled;
        });
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (QueueBMotion.reduced(context) ||
        !TickerMode.valuesOf(context).enabled) {
      _checked = true;
      _play = false;
    }
  }

  @override
  void didUpdateWidget(covariant QueueBContentEntrance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.once, widget.once)) _prepare();
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) {
      return Opacity(
        opacity: 0,
        alwaysIncludeSemantics: true,
        child: widget.child,
      );
    }
    if (!_play) return widget.child;
    return widget.child
        .animate(
          key: ObjectKey(widget.once),
          delay: QueueBMotion.stagger * _ordinal,
        )
        .custom(
          begin: 0,
          end: 1,
          duration: QueueBMotion.component,
          curve: QueueBMotion.entering,
          builder: (context, value, child) => Opacity(
            opacity: value,
            alwaysIncludeSemantics: true,
            child: child,
          ),
        )
        .moveY(
          begin: QueueBMotion.verticalOffset,
          end: 0,
          duration: QueueBMotion.component,
          curve: QueueBMotion.entering,
        );
  }
}

/// Selection pulse uses only the current child. Old dates/slots are never
/// retained, and no selection callback is invoked by the animation lifecycle.
class QueueBSelectionMotion extends StatefulWidget {
  const QueueBSelectionMotion({
    super.key,
    required this.selected,
    required this.child,
  });
  final bool selected;
  final Widget child;

  @override
  State<QueueBSelectionMotion> createState() => _QueueBSelectionMotionState();
}

class _QueueBSelectionMotionState extends State<QueueBSelectionMotion> {
  Object? _selection;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (QueueBMotion.reduced(context) ||
        !TickerMode.valuesOf(context).enabled) {
      _selection = null;
    }
  }

  @override
  void didUpdateWidget(covariant QueueBSelectionMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.selected ||
        QueueBMotion.reduced(context) ||
        !TickerMode.valuesOf(context).enabled) {
      _selection = null;
    } else if (!oldWidget.selected) {
      _selection = Object();
    }
  }

  @override
  Widget build(BuildContext context) => _selection == null
      ? widget.child
      : TweenAnimationBuilder<double>(
          key: ObjectKey(_selection),
          duration: QueueBMotion.micro,
          curve: QueueBMotion.entering,
          tween: Tween(begin: .96, end: 1),
          child: widget.child,
          builder: (_, value, child) =>
              Transform.scale(scale: value, child: child),
        );
}
