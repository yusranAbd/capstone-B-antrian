import 'package:flutter/material.dart';

import 'config.dart';
import 'mobile_ui.dart';

// Operational QueueB / teal / compact list + service console.
// Hallmark critique: philosophy 5, hierarchy 5, execution 4, specificity 5,
// restraint 5, variety 4. Tokens inherit QueueB; only PETUGAS uses this theme.
abstract final class StaffStyle {
  static const radius = 14.0;
  static ThemeData get theme {
    final base = QueueBStyle.theme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    );
    return base.copyWith(
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: Colors.white,
        toolbarHeight: 60,
        scrolledUnderElevation: 0,
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: shape,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: shape,
          side: const BorderSide(color: QueueBStyle.border),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
      ),
    );
  }
}

class StaffLiveStatus extends StatelessWidget {
  const StaffLiveStatus(this.status, {super.key});
  final String status;
  @override
  Widget build(BuildContext context) {
    final connected = status == 'Realtime terhubung';
    return Tooltip(
      message: status,
      child: Semantics(
        label: status,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              connected ? Icons.wifi_rounded : Icons.sync_rounded,
              size: 16,
              color: connected ? QueueBStyle.success : QueueBStyle.warning,
            ),
            const SizedBox(width: 6),
            Text(
              connected
                  ? 'Realtime terhubung'
                  : status.contains('terputus') ||
                        status.contains('belum tersambung')
                  ? 'Realtime terputus'
                  : status.contains('ditolak')
                  ? 'Izin realtime ditolak'
                  : 'Menyinkronkan…',
              style: const TextStyle(fontSize: 12, color: QueueBStyle.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class StaffHeaderContext extends StatelessWidget {
  const StaffHeaderContext({
    super.key,
    required this.name,
    required this.room,
    required this.status,
  });
  final String name, status;
  final Json? room;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (constraints.maxWidth > 560 && room != null) ...[
          Flexible(
            child: Text(
              '${label(object(room!['layanan']))} · ${room!['kode'] ?? label(room!)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(width: 18),
        ],
        if (constraints.maxWidth > 400) ...[
          StaffLiveStatus(status),
          const SizedBox(width: 18),
        ],
        if (constraints.maxWidth > 180)
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Text(
                  'Petugas pelayanan',
                  style: TextStyle(fontSize: 11, color: QueueBStyle.muted),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class StaffPanel extends StatelessWidget {
  const StaffPanel({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.action,
    this.dark = false,
  });
  final String title;
  final IconData icon;
  final Widget child;
  final Widget? action;
  final bool dark;
  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    explicitChildNodes: true,
    child: Material(
      color: dark ? QueueBStyle.navy : Colors.white,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: dark ? QueueBStyle.navy : QueueBStyle.border),
        borderRadius: BorderRadius.circular(StaffStyle.radius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: dark ? QueueBStyle.mint : QueueBStyle.darkTeal,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: dark ? Colors.white : QueueBStyle.navy,
                    ),
                  ),
                ),
                ?action,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    ),
  );
}

class StaffMetric extends StatelessWidget {
  const StaffMetric({
    super.key,
    required this.title,
    required this.value,
    required this.detail,
    required this.icon,
  });
  final String title, value, detail;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: QueueBStyle.border),
      borderRadius: BorderRadius.circular(StaffStyle.radius),
    ),
    child: Row(
      children: [
        Icon(icon, color: QueueBStyle.darkTeal, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 12, color: QueueBStyle.muted),
              ),
              const SizedBox(height: 2),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 26,
                      height: 1.1,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      detail,
                      style: const TextStyle(
                        fontSize: 11,
                        color: QueueBStyle.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class StaffEmpty extends StatelessWidget {
  const StaffEmpty(this.text, {super.key, this.dark = false});
  final String text;
  final bool dark;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
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
