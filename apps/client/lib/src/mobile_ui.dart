import 'package:flutter/material.dart';

import 'patient_design.dart';
import 'queueb_palette.dart';

abstract final class QueueBStyle {
  static const teal = QueueBPalette.primary;
  static const darkTeal = QueueBPalette.primary;
  static const navy = QueueBPalette.ink;
  static const background = QueueBPalette.background;
  static const mint = QueueBPalette.soft;
  static const border = QueueBPalette.border;
  static const muted = QueueBPalette.muted;
  static const success = Color(0xff16804a);
  static const warning = Color(0xff996200);
  static const danger = Color(0xffba303e);
  static const hero = QueueBPalette.hero;
  static const console = QueueBPalette.console;
  static const radius = 20.0;
  static const space = 16.0;
  static const smallSpace = 8.0;
  static const mediumSpace = 12.0;
  static const operationalToolbarHeight = 56.0;

  static final ThemeData theme = _buildTheme();

  /// Operational typography only. Mobile patient and TV text retain their scale.
  static final TextTheme operationalTextTheme = theme.textTheme.copyWith(
    headlineLarge: theme.textTheme.headlineLarge?.copyWith(fontSize: 22),
    headlineMedium: theme.textTheme.headlineMedium?.copyWith(fontSize: 22),
    headlineSmall: theme.textTheme.headlineSmall?.copyWith(fontSize: 20),
    titleLarge: theme.textTheme.titleLarge?.copyWith(fontSize: 17),
    titleMedium: theme.textTheme.titleMedium?.copyWith(fontSize: 15),
    titleSmall: theme.textTheme.titleSmall?.copyWith(fontSize: 14),
    bodyLarge: theme.textTheme.bodyLarge?.copyWith(fontSize: 14),
    bodyMedium: theme.textTheme.bodyMedium?.copyWith(fontSize: 13),
    bodySmall: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
    labelLarge: theme.textTheme.labelLarge?.copyWith(fontSize: 13),
    labelMedium: theme.textTheme.labelMedium?.copyWith(fontSize: 12),
    labelSmall: theme.textTheme.labelSmall?.copyWith(fontSize: 11),
  );

  static ThemeData _buildTheme() {
    final scheme = ColorScheme.fromSeed(seedColor: teal).copyWith(
      primary: darkTeal,
      onPrimary: Colors.white,
      secondary: QueueBPalette.cyan,
      onSecondary: Colors.white,
      onSurfaceVariant: muted,
      outline: muted,
      surface: Colors.white,
      onSurface: navy,
      outlineVariant: border,
    );
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    return base.copyWith(
      scaffoldBackgroundColor: background,
      textTheme: base.textTheme.apply(bodyColor: navy, displayColor: navy),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: navy,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: const BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: background,
        contentPadding: const EdgeInsets.all(space),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          side: const BorderSide(color: border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: mint,
        height: 76,
      ),
    );
  }
}

class QueueBBrand extends StatelessWidget {
  const QueueBBrand({super.key, this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: compact ? 32 : 48,
        height: compact ? 32 : 48,
        decoration: BoxDecoration(
          color: QueueBStyle.teal,
          borderRadius: BorderRadius.circular(compact ? 10 : 16),
        ),
        child: Icon(
          Icons.local_hospital_rounded,
          color: Colors.white,
          size: compact ? 23 : 36,
        ),
      ),
      const SizedBox(width: 10),
      Flexible(
        child: Text.rich(
          TextSpan(
            children: [
              const TextSpan(
                text: 'QueueB',
                style: TextStyle(color: QueueBStyle.navy),
              ),
              TextSpan(
                text: compact ? ' Hospital' : '\nHospital',
                style: const TextStyle(color: QueueBStyle.darkTeal),
              ),
            ],
          ),
          style: TextStyle(
            fontSize: compact ? 18 : 30,
            height: 1.05,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    ],
  );
}

class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.color});
  final Widget child;
  final Color? color;
  @override
  Widget build(BuildContext context) => Card(
    color: color,
    child: Padding(
      padding: const EdgeInsets.all(QueueBStyle.space),
      child: child,
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.text,
    this.icon = Icons.inbox_outlined,
  });
  final String text;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: QueueBStyle.mediumSpace),
    child: Column(
      children: [
        Icon(
          icon,
          size: 32,
          color: PatientDesign.active(context)
              ? PatientDesign.primary
              : QueueBStyle.darkTeal,
        ),
        const SizedBox(height: QueueBStyle.smallSpace),
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: PatientDesign.active(context)
                ? PatientDesign.muted
                : QueueBStyle.muted,
          ),
        ),
      ],
    ),
  );
}

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {super.key});
  final Object? status;
  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'SELESAI' => QueueBStyle.success,
      'DILEWATI' || 'DIBATALKAN' => QueueBStyle.danger,
      'MENUNGGU' || 'CHECK_IN' => QueueBStyle.warning,
      _ => QueueBStyle.darkTeal,
    };
    return Chip(
      label: Text('$status'.replaceAll('_', ' ')),
      avatar: Icon(Icons.circle, size: 9, color: color),
      labelStyle: TextStyle(
        color: color,
        fontWeight: FontWeight.w700,
        fontSize: 12,
      ),
      backgroundColor: color.withValues(alpha: .08),
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
    );
  }
}

class ClinicCard extends StatelessWidget {
  const ClinicCard({
    super.key,
    required this.name,
    required this.selected,
    required this.onTap,
  });
  final String name;
  final bool selected;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    child: Material(
      color: selected
          ? (PatientDesign.active(context)
                ? PatientDesign.soft
                : QueueBStyle.mint)
          : (PatientDesign.active(context)
                ? PatientDesign.paper
                : Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected
              ? (PatientDesign.active(context)
                    ? PatientDesign.primary
                    : QueueBStyle.teal)
              : (PatientDesign.active(context)
                    ? PatientDesign.border
                    : QueueBStyle.border),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.local_hospital_outlined,
                color: PatientDesign.active(context)
                    ? PatientDesign.primary
                    : QueueBStyle.darkTeal,
                size: 28,
              ),
              const SizedBox(height: 8),
              Text(
                name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class MobileNotice extends StatelessWidget {
  const MobileNotice(this.text, {super.key, this.error = false});
  final String text;
  final bool error;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.symmetric(vertical: 8),
    padding: const EdgeInsets.all(QueueBStyle.space),
    decoration: BoxDecoration(
      color: error
          ? Theme.of(context).colorScheme.errorContainer
          : (PatientDesign.active(context)
                ? PatientDesign.soft
                : QueueBStyle.mint),
      borderRadius: BorderRadius.circular(16),
    ),
    child: SelectableText(
      text,
      style: TextStyle(
        color: error
            ? Theme.of(context).colorScheme.onErrorContainer
            : (PatientDesign.active(context)
                  ? PatientDesign.ink
                  : QueueBStyle.navy),
      ),
    ),
  );
}
