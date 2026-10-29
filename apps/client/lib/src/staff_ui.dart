import 'package:flutter/material.dart';

import 'mobile_ui.dart';

// Operational QueueB / shared blue palette / compact service console.
// Scoped to PETUGAS; see docs/frontend/QUEUEB_UI_UX_GUIDELINES.md.
abstract final class StaffStyle {
  static const radius = 14.0;
  static ThemeData get theme {
    final base = QueueBStyle.theme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    );
    return base.copyWith(
      textTheme: QueueBStyle.operationalTextTheme.copyWith(
        headlineSmall: base.textTheme.headlineSmall?.copyWith(fontSize: 20),
        titleLarge: base.textTheme.titleLarge?.copyWith(fontSize: 17),
        titleMedium: base.textTheme.titleMedium?.copyWith(fontSize: 14),
        titleSmall: base.textTheme.titleSmall?.copyWith(fontSize: 13),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 13),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 12),
        bodySmall: base.textTheme.bodySmall?.copyWith(fontSize: 11),
        labelLarge: base.textTheme.labelLarge?.copyWith(fontSize: 12),
        labelMedium: base.textTheme.labelMedium?.copyWith(fontSize: 11),
      ),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: Colors.white,
        toolbarHeight: QueueBStyle.operationalToolbarHeight,
        scrolledUnderElevation: 0,
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: shape,
          textStyle: base.textTheme.labelLarge?.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 44),
          textStyle: const TextStyle(fontSize: 12),
          shape: shape,
          side: const BorderSide(color: QueueBStyle.border),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 44),
          textStyle: const TextStyle(fontSize: 12),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(40, 40),
          iconSize: 20,
        ),
      ),
    );
  }
}

class StaffPanel extends StatelessWidget {
  const StaffPanel({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.action,
    this.dark = false,
    this.expand = false,
  });
  final String title;
  final IconData icon;
  final Widget child;
  final Widget? action;
  final bool dark, expand;
  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    explicitChildNodes: true,
    child: Material(
      color: dark ? QueueBStyle.console : Colors.white,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: dark ? QueueBStyle.console : QueueBStyle.border,
        ),
        borderRadius: BorderRadius.circular(StaffStyle.radius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: dark ? QueueBStyle.mint : QueueBStyle.darkTeal,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: dark ? Colors.white : QueueBStyle.navy,
                    ),
                  ),
                ),
                ?action,
              ],
            ),
            const SizedBox(height: 8),
            if (expand) Expanded(child: child) else child,
          ],
        ),
      ),
    ),
  );
}

class StaffEmpty extends StatelessWidget {
  const StaffEmpty(this.text, {super.key, this.dark = false});
  final String text;
  final bool dark;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.inbox_outlined,
          size: 24,
          color: dark ? QueueBStyle.mint : QueueBStyle.muted,
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: dark ? Colors.white : QueueBStyle.muted,
            ),
          ),
        ),
      ],
    ),
  );
}
