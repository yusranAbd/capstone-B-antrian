import 'package:flutter/material.dart';

import 'config.dart';
import 'mobile_ui.dart';
import 'patient_reservations.dart';
import 'patient_ui.dart';

/// Patient-only density; other role themes and TV typography stay independent.
abstract final class PatientMobileV5 {
  static final theme = QueueBStyle.theme.copyWith(
    textTheme: QueueBStyle.theme.textTheme.copyWith(
      titleLarge: QueueBStyle.theme.textTheme.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
      bodyMedium: QueueBStyle.theme.textTheme.bodyMedium?.copyWith(
        fontSize: 14,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(44, 44),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        textStyle: const TextStyle(fontSize: 13),
        side: const BorderSide(color: QueueBStyle.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    inputDecorationTheme: QueueBStyle.theme.inputDecorationTheme.copyWith(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
  );
}

class PatientTicketCard extends StatelessWidget {
  const PatientTicketCard({
    super.key,
    required this.item,
    required this.config,
    required this.onOpen,
  });
  final PatientReservation item;
  final AppConfig config;
  final VoidCallback? onOpen;
  @override
  Widget build(BuildContext context) {
    final room = object(item.session['loket']).isNotEmpty
        ? object(item.session['loket'])
        : object(item.ticket['loket']);
    final color = switch (item.status) {
      'DIPESAN' => const Color(0xffeaf3ff),
      'CHECK_IN' || 'MENUNGGU' || 'DIPANGGIL' || 'DILAYANI' => QueueBStyle.mint,
      'DILEWATI' => const Color(0xfffff3df),
      'DIBATALKAN' => const Color(0xffffedf0),
      'SELESAI' => QueueBStyle.background,
      _ => Colors.white,
    };
    return Container(
      key: ValueKey('patient-ticket-${item.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: QueueBStyle.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  item.number,
                  style: const TextStyle(
                    fontSize: 26,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                    color: QueueBStyle.navy,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(child: ReservationStatus(item.status)),
            ],
          ),
          const SizedBox(height: 10),
          _fact(Icons.local_hospital_outlined, label(item.clinic)),
          _fact(Icons.calendar_today_outlined, patientDate(item.day)),
          if (item.doctor['nama'] != null)
            _fact(Icons.person_outline, '${item.doctor['nama']}'),
          if (room.isNotEmpty)
            _fact(
              Icons.meeting_room_outlined,
              [
                room['kode'],
                room['nama'],
              ].whereType<String>().where((v) => v.isNotEmpty).join(' · '),
            ),
          if (item.slot['mulaiPada'] != null)
            _fact(
              Icons.schedule_outlined,
              '${patientTime(item.slot, config)} · ${config.serviceTimeZone}',
            ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: onOpen,
            icon: Icon(
              item.terminal
                  ? Icons.description_outlined
                  : Icons.qr_code_rounded,
              size: 18,
            ),
            label: const Text('Lihat Tiket / QR'),
          ),
        ],
      ),
    );
  }

  Widget _fact(IconData icon, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: QueueBStyle.darkTeal),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              height: 1.25,
              color: QueueBStyle.navy,
            ),
          ),
        ),
      ],
    ),
  );
}
