import 'package:flutter/material.dart';

import 'queueb_palette.dart';

/// Periwinkle blue: scoped to patients and the shared sign-in entry point.
/// Role-specific typography and layout stay independent from shared colors.
class PatientAppearance extends ThemeExtension<PatientAppearance> {
  const PatientAppearance();
  @override
  PatientAppearance copyWith() => this;
  @override
  PatientAppearance lerp(covariant PatientAppearance? other, double t) => this;
}

abstract final class PatientDesign {
  static const primary = QueueBPalette.primary;
  static const hero = QueueBPalette.hero;
  static const accent = QueueBPalette.cyan;
  static const background = QueueBPalette.background;
  static const paper = QueueBPalette.paper;
  static const ink = QueueBPalette.ink;
  static const muted = QueueBPalette.muted;
  static const border = QueueBPalette.border;
  static const soft = QueueBPalette.soft;
  static const success = Color(0xff2b674b);
  static const warning = Color(0xff825400);
  static const danger = Color(0xffa43946);
  static const radius = 20.0;
  static const space = 16.0;
  static const smallSpace = 8.0;
  static const mediumSpace = 12.0;
  // Compatibility names for existing patient components, never global tokens.
  static const navy = ink, teal = primary, darkTeal = primary, mint = soft;

  static bool active(BuildContext context) =>
      Theme.of(context).extension<PatientAppearance>() != null;

  static Color statusInk(String status) => switch (status) {
    'MENUNGGU' || 'CHECK_IN' => warning,
    'SELESAI' || 'DILAYANI' => success,
    'DIBATALKAN' => danger,
    'DILEWATI' => const Color(0xff9a491d),
    'DIPANGGIL' => const Color(0xff355d85),
    'DIPESAN' => primary,
    _ => muted,
  };
  static Color statusSurface(String status) => switch (status) {
    'MENUNGGU' || 'CHECK_IN' => const Color(0xfffff0d7),
    'SELESAI' || 'DILAYANI' => const Color(0xffe6f0e7),
    'DIBATALKAN' => const Color(0xfffceaed),
    'DILEWATI' => const Color(0xfffcebd9),
    'DIPANGGIL' => const Color(0xffe7eff8),
    'DIPESAN' => soft,
    _ => const Color(0xffedf1f7),
  };
  static IconData statusIcon(String status) => switch (status) {
    'SELESAI' => Icons.check_circle_outline,
    'DIBATALKAN' => Icons.cancel_outlined,
    'DILEWATI' => Icons.skip_next_outlined,
    'DIPANGGIL' => Icons.volume_up_outlined,
    'DILAYANI' => Icons.medical_services_outlined,
    _ => Icons.schedule_outlined,
  };

  static final ThemeData theme = _theme();
  static ThemeData _theme() {
    final scheme = ColorScheme.fromSeed(seedColor: primary).copyWith(
      primary: primary,
      onPrimary: Colors.white,
      secondary: accent,
      onSecondary: Colors.white,
      surface: paper,
      onSurface: ink,
      onSurfaceVariant: muted,
      outline: muted,
      outlineVariant: border,
      error: danger,
      surfaceTint: Colors.transparent,
    );
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    final input = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: border),
    );
    return base.copyWith(
      extensions: const [PatientAppearance()],
      scaffoldBackgroundColor: background,
      textTheme: base.textTheme
          .apply(bodyColor: ink, displayColor: ink)
          .copyWith(
            titleLarge: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              height: 1.2,
              letterSpacing: -.4,
              color: ink,
            ),
            titleMedium: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              height: 1.3,
              color: ink,
            ),
            bodyMedium: const TextStyle(fontSize: 14, height: 1.45, color: ink),
            bodySmall: const TextStyle(fontSize: 12, height: 1.4, color: muted),
          ),
      cardTheme: CardThemeData(
        color: paper,
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: const BorderSide(color: border),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: primary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(44, 48),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          shape: shape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          minimumSize: const Size(44, 48),
          side: const BorderSide(color: border),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          shape: shape,
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 44),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: paper,
        isDense: true,
        border: input,
        enabledBorder: input,
        focusedBorder: input.copyWith(
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        labelStyle: const TextStyle(color: muted, fontSize: 13),
        hintStyle: const TextStyle(color: muted, fontSize: 13),
        prefixIconColor: muted,
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: paper,
        indicatorColor: soft,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: paper,
        selectedColor: soft,
        side: const BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        labelStyle: const TextStyle(fontSize: 12, color: ink),
      ),
      dividerTheme: const DividerThemeData(
        color: border,
        thickness: 1,
        space: 24,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: paper,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: paper,
        modalBackgroundColor: paper,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 2,
        extendedTextStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class PatientPageIntro extends StatelessWidget {
  const PatientPageIntro({
    super.key,
    required this.title,
    required this.caption,
    this.action,
  });
  final String title, caption;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
            ?action,
          ],
        ),
        const SizedBox(height: 4),
        Text(
          caption,
          style: const TextStyle(color: PatientDesign.muted, fontSize: 13),
        ),
      ],
    ),
  );
}
