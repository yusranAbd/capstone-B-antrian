import 'package:flutter/material.dart';

import 'mobile_ui.dart';

// Hallmark · QueueB reference · split healthcare welcome / focused native form.
// Hallmark pre-emit critique: P4 H5 E4 S5 R4 V4; user reference takes priority.
// Scoped tokens; existing app typography, routes and role dashboards are preserved.
abstract final class LoginStyle {
  static const sky = Color(0xffdaf4fc);
  static const paper = Color(0xfff1fbfd);
  static const rule = Color(0xffdce9ef);
  static const white = Colors.white;
  static const shadow = Color(0x10007f80);
}

/// Sizes are in logical Flutter pixels after SafeArea, never monitor pixels.
class LoginSizing {
  const LoginSizing(this.viewport, this.textScale);
  final Size viewport;
  final double textScale;
  bool get desktop => viewport.width >= 1024;
  bool get compact => desktop && viewport.height < 900;
  bool get fitDesktop => desktop && viewport.height >= 680 && textScale <= 1.1;
  double get outerPadding => desktop && compact
      ? 16
      : viewport.width < 600
      ? 16
      : 28;
  double get framePadding => compact ? 12 : 18;
  double get gap => compact ? 12 : 18;
  double get cardHeight =>
      (viewport.height - outerPadding * 2 - framePadding * 2 - 6).clamp(
        0,
        double.infinity,
      );
  double get formPadding => compact
      ? 24
      : viewport.width < 600
      ? 24
      : 36;
  double get fieldGap => compact ? 16 : 24;
  double get dividerGap => compact ? 12 : 24;
}

/// Presentation only. The existing LoginPage owns validation and authentication.
class LoginLayout extends StatelessWidget {
  const LoginLayout({super.key, required this.builder});
  final Widget Function(BuildContext context, LoginSizing sizing) builder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final sizing = LoginSizing(
        constraints.biggest,
        MediaQuery.textScalerOf(context).scale(1),
      );
      final desktop = sizing.desktop;
      final mobile = constraints.maxWidth < 600;
      final form = builder(context, sizing);
      return DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [LoginStyle.paper, LoginStyle.sky, LoginStyle.paper],
          ),
        ),
        child: SingleChildScrollView(
          key: const ValueKey('login-page-scroll'),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(sizing.outerPadding),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: desktop ? 1440 : 560),
                  child: desktop
                      ? Container(
                          padding: EdgeInsets.all(sizing.framePadding),
                          decoration: BoxDecoration(
                            color: LoginStyle.white.withValues(alpha: .5),
                            border: Border.all(
                              color: LoginStyle.white,
                              width: 3,
                            ),
                            borderRadius: BorderRadius.circular(32),
                            boxShadow: const [
                              BoxShadow(
                                color: LoginStyle.shadow,
                                blurRadius: 40,
                                offset: Offset(0, 16),
                              ),
                            ],
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 64,
                                child: _Welcome(sizing: sizing),
                              ),
                              SizedBox(width: sizing.gap),
                              Expanded(flex: 40, child: form),
                            ],
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const QueueBBrand(compact: true),
                            const SizedBox(height: 24),
                            Text(
                              'Akses mudah untuk pelayanan lebih baik',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Pendaftaran, tiket, dan antrean rumah sakit dalam satu aplikasi.',
                              style: TextStyle(color: QueueBStyle.muted),
                            ),
                            const SizedBox(height: 24),
                            form,
                            if (!mobile) ...[
                              const SizedBox(height: 20),
                              const _DigitalServices(),
                            ],
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class LoginFormCard extends StatelessWidget {
  const LoginFormCard({super.key, required this.child, required this.sizing});
  final Widget child;
  final LoginSizing sizing;
  @override
  Widget build(BuildContext context) => Container(
    constraints: BoxConstraints(
      minHeight: sizing.desktop ? sizing.cardHeight : 0,
    ),
    padding: EdgeInsets.all(sizing.formPadding),
    decoration: BoxDecoration(
      color: LoginStyle.white,
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: LoginStyle.rule),
      boxShadow: const [
        BoxShadow(
          color: LoginStyle.shadow,
          blurRadius: 28,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: Theme(
      data: sizing.compact
          ? Theme.of(context).copyWith(
              inputDecorationTheme: Theme.of(context).inputDecorationTheme
                  .copyWith(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                  ),
            )
          : Theme.of(context),
      child: child,
    ),
  );
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.sizing});
  final LoginSizing sizing;
  @override
  Widget build(BuildContext context) {
    final digitalHeight = sizing.compact
        ? sizing.viewport.width < 1200
              ? 150.0
              : 128.0
        : 190.0;
    final gap = sizing.compact ? 12.0 : 16.0;
    // Minimums fill the viewport while allowing longer text/error content to grow.
    // No maximum height, clipping or nested scroll is used to hide overflow.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _WelcomeHero(
          compact: sizing.compact,
          minimumHeight: sizing.fitDesktop
              ? (sizing.cardHeight - digitalHeight - gap).clamp(
                  0,
                  double.infinity,
                )
              : 550,
        ),
        SizedBox(height: gap),
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: digitalHeight),
          child: _DigitalServices(compact: sizing.compact),
        ),
      ],
    );
  }
}

class _WelcomeHero extends StatelessWidget {
  const _WelcomeHero({required this.compact, required this.minimumHeight});
  final bool compact;
  final double minimumHeight;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final wide = box.maxWidth >= 700;
      return Container(
        constraints: BoxConstraints(minHeight: minimumHeight),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [LoginStyle.paper, LoginStyle.sky],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: 0,
              bottom: 0,
              width: box.maxWidth * .45,
              height: (minimumHeight * .88).clamp(0, 520),
              child: ExcludeSemantics(
                child: Image.asset(
                  'assets/illustrations/login_hospital.png',
                  fit: BoxFit.contain,
                  alignment: Alignment.bottomRight,
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(compact ? 20 : 26),
              child: SizedBox(
                width: box.maxWidth * .50,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    QueueBBrand(compact: compact),
                    SizedBox(height: compact ? 18 : 32),
                    Text(
                      'Akses mudah untuk pelayanan lebih baik',
                      style: TextStyle(
                        fontSize: compact ? (wide ? 32 : 28) : (wide ? 38 : 30),
                        fontWeight: FontWeight.w800,
                        height: 1.12,
                        letterSpacing: -.7,
                      ),
                    ),
                    SizedBox(height: compact ? 12 : 16),
                    Text(
                      'Daftar, dapatkan tiket, dan ikuti antrean rumah sakit dalam satu aplikasi. Pelayanan kesehatan jadi lebih tertib, cepat, dan nyaman.',
                      style: TextStyle(
                        color: QueueBStyle.muted,
                        fontSize: compact ? 14 : 15,
                        height: compact ? 1.4 : 1.5,
                      ),
                    ),
                    SizedBox(height: compact ? 20 : 28),
                    _Benefit(
                      icon: Icons.confirmation_number_outlined,
                      title: 'Ambil tiket antrean',
                      description: 'Dengan mudah dan cepat',
                      compact: compact,
                    ),
                    SizedBox(height: compact ? 10 : 16),
                    _Benefit(
                      icon: Icons.schedule_rounded,
                      title: 'Pantau antrean real-time',
                      description: 'Kapan saja, di mana saja',
                      compact: compact,
                    ),
                    SizedBox(height: compact ? 10 : 16),
                    _Benefit(
                      icon: Icons.favorite_border_rounded,
                      title: 'Pelayanan lebih efisien',
                      description: 'Untuk pengalaman lebih baik',
                      compact: compact,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _Benefit extends StatelessWidget {
  const _Benefit({
    required this.icon,
    required this.title,
    required this.description,
    this.compact = false,
  });
  final IconData icon;
  final String title, description;
  final bool compact;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Container(
        width: compact ? 32 : 44,
        height: compact ? 32 : 44,
        decoration: const BoxDecoration(
          color: LoginStyle.white,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: QueueBStyle.darkTeal, size: compact ? 22 : 25),
      ),
      SizedBox(width: compact ? 8 : 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            const SizedBox(height: 3),
            Text(
              description,
              style: const TextStyle(
                color: QueueBStyle.muted,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _DigitalServices extends StatelessWidget {
  const _DigitalServices({this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.all(compact ? 16 : 24),
    decoration: BoxDecoration(
      color: LoginStyle.white.withValues(alpha: .9),
      border: Border.all(color: LoginStyle.rule),
      borderRadius: BorderRadius.circular(22),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Layanan digital rumah sakit',
          style: TextStyle(
            fontSize: compact ? 18 : 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (!compact) const SizedBox(height: 6),
        if (!compact)
          const Text(
            'Kelola kebutuhan layanan kesehatan Anda dengan lebih praktis dan nyaman.',
            style: TextStyle(color: QueueBStyle.muted, height: 1.4),
          ),
        SizedBox(height: compact ? 12 : 22),
        LayoutBuilder(
          builder: (context, box) {
            final items = [
              _Benefit(
                icon: Icons.calendar_month_outlined,
                title: 'Pendaftaran online',
                description: 'Daftar dari mana saja',
                compact: compact,
              ),
              _Benefit(
                icon: Icons.schedule_rounded,
                title: 'Pantau antrean',
                description: 'Posisi antrean real-time',
                compact: compact,
              ),
              _Benefit(
                icon: Icons.monitor_heart_outlined,
                title: 'Akses mudah',
                description: 'Dalam satu aplikasi',
                compact: compact,
              ),
            ];
            return compact || box.maxWidth >= 510
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < items.length; i++) ...[
                        if (i > 0) const SizedBox(width: 12),
                        Expanded(child: items[i]),
                      ],
                    ],
                  )
                : Column(
                    children: [
                      for (var i = 0; i < items.length; i++) ...[
                        if (i > 0) const SizedBox(height: 16),
                        items[i],
                      ],
                    ],
                  );
          },
        ),
      ],
    ),
  );
}
