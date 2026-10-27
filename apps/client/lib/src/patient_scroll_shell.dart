import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Patient-only chrome. Content stays mounted while the bars release space.
/// No timers or scroll controllers are attached to the individual pages.
class PatientScrollShell extends StatefulWidget {
  const PatientScrollShell({
    super.key,
    required this.pageKey,
    required this.body,
    required this.bottomNavigationBar,
    this.header,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
  });

  final Object pageKey;
  final Widget body, bottomNavigationBar;
  final PreferredSizeWidget? header;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;

  @override
  State<PatientScrollShell> createState() => _PatientScrollShellState();
}

class _PatientScrollShellState extends State<PatientScrollShell>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    value: 1,
    duration: const Duration(milliseconds: 220),
    reverseDuration: const Duration(milliseconds: 180),
  );
  late final _visibility = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInOutCubic,
  );
  bool _userScrolling = false;
  double _travel = 0;
  BuildContext? _scrollContext;

  // main.dart always enables Web semantics; that flag alone does not identify
  // a screen reader there. Native platforms retain their accessibility policy.
  bool get _keepControlsVisible =>
      !kIsWeb && MediaQuery.accessibleNavigationOf(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A screen reader enabled mid-session must never inherit hidden controls.
    if (_keepControlsVisible) _controller.value = 1;
  }

  @override
  void didUpdateWidget(covariant PatientScrollShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageKey != widget.pageKey) {
      _userScrolling = false;
      _travel = 0;
      _scrollContext = null;
      _controller.forward();
    }
  }

  void _show(bool visible) {
    final target = visible ? 1.0 : 0.0;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = target;
    } else if (visible) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  bool _onScroll(ScrollNotification notification) {
    // Ignore nested filter strips, programmatic ensureVisible/jumpTo, dialogs
    // and dialogs. Web semantics maps native DOM scrolling to jumpTo, so
    // Web updates also count as scrolling without disabling semantics.
    if (notification.metrics.axis != Axis.vertical ||
        notification.depth != 0 ||
        _keepControlsVisible ||
        ModalRoute.of(context)?.isCurrent == false) {
      return false;
    }
    if (notification is UserScrollNotification) {
      _userScrolling = notification.direction != ScrollDirection.idle;
      if (!_userScrolling) _travel = 0;
    }
    if (notification is ScrollUpdateNotification &&
        (kIsWeb || _userScrolling || notification.dragDetails != null)) {
      final delta = notification.scrollDelta ?? 0;
      if (delta != 0) _scrollContext = notification.context;
      if (notification.metrics.pixels <= 0) {
        _travel = 0;
        _show(true);
      } else if (notification.metrics.maxScrollExtent > 0 && delta != 0) {
        if (_travel.sign != delta.sign) _travel = 0;
        _travel += delta;
        if (_travel.abs() >= 8) _show(_travel < 0);
      }
    }
    return false;
  }

  Widget _bar(Widget child, {required bool bottom}) => Focus(
    onFocusChange: (focused) {
      if (focused) _show(true);
    },
    child: IgnorePointer(
      ignoring: _controller.value == 0,
      child: ExcludeSemantics(
        excluding: !kIsWeb && _controller.value == 0,
        child: SizeTransition(
          key: ValueKey(
            bottom ? 'patient-chrome-bottom' : 'patient-chrome-top',
          ),
          sizeFactor: _visibility,
          alignment: bottom ? Alignment.bottomCenter : Alignment.topCenter,
          child: FadeTransition(opacity: _visibility, child: child),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: Semantics(
      customSemanticsActions: {
        const CustomSemanticsAction(label: 'Tampilkan navigasi pasien'): () =>
            _show(true),
      },
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) {
          final metrics = notification.metrics;
          // Collapsing bars can make a short page fit or clamp its offset to
          // zero. Restore controls even when no reverse scroll is possible.
          if (identical(notification.context, _scrollContext) &&
              notification.depth == 0 &&
              metrics.axis == Axis.vertical &&
              (metrics.maxScrollExtent <= 0 || metrics.pixels <= 0) &&
              _controller.value < 1 &&
              _controller.status != AnimationStatus.forward) {
            _show(true);
          }
          return false;
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: widget.body,
        ),
      ),
    ),
    builder: (context, body) => Scaffold(
      floatingActionButton: widget.floatingActionButton,
      floatingActionButtonLocation: widget.floatingActionButtonLocation,
      bottomNavigationBar: _bar(widget.bottomNavigationBar, bottom: true),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (widget.header != null)
              _bar(
                SizedBox(
                  height: widget.header!.preferredSize.height,
                  child: MediaQuery.removePadding(
                    context: context,
                    removeTop: true,
                    child: widget.header!,
                  ),
                ),
                bottom: false,
              ),
            Expanded(child: body!),
          ],
        ),
      ),
    ),
  );

  @override
  void dispose() {
    _visibility.dispose();
    _controller.dispose();
    super.dispose();
  }
}
