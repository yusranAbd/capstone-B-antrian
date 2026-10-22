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

/// Presentation only. The existing LoginPage owns validation and authentication.
class LoginLayout extends StatelessWidget {
  const LoginLayout({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final desktop = constraints.maxWidth >= 1024;
      final mobile = constraints.maxWidth < 600;
      final padding = mobile ? 16.0 : 28.0;
      return DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [LoginStyle.paper, LoginStyle.sky, LoginStyle.paper],
          ),
        ),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(padding),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: desktop ? 1440 : 560),
                  child: desktop
                      ? Container(
                          padding: const EdgeInsets.all(18),
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
                              const Expanded(flex: 64, child: _Welcome()),
                              const SizedBox(width: 18),
                              Expanded(flex: 40, child: child),
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
                            child,
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
  const LoginFormCard({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    constraints: BoxConstraints(
      minHeight: MediaQuery.sizeOf(context).width >= 1024 ? 740 : 0,
    ),
    padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 24 : 36),
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
    child: child,
  );
}

class _Welcome extends StatelessWidget {
  const _Welcome();
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= 700;
          final copyWidth = box.maxWidth * .53;
          return Container(
            constraints: const BoxConstraints(minHeight: 550),
            clipBehavior: Clip.antiAlias,
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
                  right: -46,
                  bottom: -20,
                  width: box.maxWidth * .52,
                  height: 470,
                  child: ExcludeSemantics(
                    child: Image.asset(
                      'assets/illustrations/login_hospital.png',
                      fit: BoxFit.contain,
                      alignment: Alignment.bottomRight,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(26),
                  child: SizedBox(
                    width: copyWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const QueueBBrand(),
                        const SizedBox(height: 32),
                        Text(
                          'Akses mudah untuk pelayanan lebih baik',
                          style: TextStyle(
                            fontSize: wide ? 38 : 30,
                            fontWeight: FontWeight.w800,
                            height: 1.12,
                            letterSpacing: -.7,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Daftar, dapatkan tiket, dan ikuti antrean rumah sakit dalam satu aplikasi. Pelayanan kesehatan jadi lebih tertib, cepat, dan nyaman.',
                          style: TextStyle(
                            color: QueueBStyle.muted,
                            fontSize: 15,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 28),
                        const _Benefit(
                          icon: Icons.confirmation_number_outlined,
                          title: 'Ambil tiket antrean',
                          description: 'Dengan mudah dan cepat',
                        ),
                        const SizedBox(height: 16),
                        const _Benefit(
                          icon: Icons.schedule_rounded,
                          title: 'Pantau antrean real-time',
                          description: 'Kapan saja, di mana saja',
                        ),
                        const SizedBox(height: 16),
                        const _Benefit(
                          icon: Icons.favorite_border_rounded,
                          title: 'Pelayanan lebih efisien',
                          description: 'Untuk pengalaman lebih baik',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      const SizedBox(height: 16),
      const _DigitalServices(),
    ],
  );
}

class _Benefit extends StatelessWidget {
  const _Benefit({
    required this.icon,
    required this.title,
    required this.description,
  });
  final IconData icon;
  final String title, description;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(
          color: LoginStyle.white,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: QueueBStyle.darkTeal, size: 25),
      ),
      const SizedBox(width: 12),
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
  const _DigitalServices();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: LoginStyle.white.withValues(alpha: .9),
      border: Border.all(color: LoginStyle.rule),
      borderRadius: BorderRadius.circular(22),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Layanan digital rumah sakit',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Text(
          'Kelola kebutuhan layanan kesehatan Anda dengan lebih praktis dan nyaman.',
          style: TextStyle(color: QueueBStyle.muted, height: 1.4),
        ),
        const SizedBox(height: 22),
        LayoutBuilder(
          builder: (context, box) {
            const items = [
              _Benefit(
                icon: Icons.calendar_month_outlined,
                title: 'Pendaftaran online',
                description: 'Daftar dari mana saja',
              ),
              _Benefit(
                icon: Icons.schedule_rounded,
                title: 'Pantau antrean',
                description: 'Posisi antrean real-time',
              ),
              _Benefit(
                icon: Icons.monitor_heart_outlined,
                title: 'Akses mudah',
                description: 'Dalam satu aplikasi',
              ),
            ];
            return box.maxWidth >= 510
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
