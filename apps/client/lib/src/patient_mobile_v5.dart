import 'package:flutter/material.dart';

import 'config.dart';
import 'patient_design.dart';
import 'patient_reservations.dart';
import 'patient_ui.dart';

/// Patient-only density; other role themes and TV typography stay independent.
abstract final class PatientMobileV5 {
  static final theme = PatientDesign.theme;
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
    return Container(
      key: ValueKey('patient-ticket-${item.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: PatientDesign.paper,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: PatientDesign.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: item.terminal
                  ? const Color(0xfff0ecef)
                  : PatientDesign.soft,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    item.number,
                    style: const TextStyle(
                      fontSize: 30,
                      height: 1.1,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.7,
                      color: PatientDesign.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(child: ReservationStatus(item.status)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _fact(
                  Icons.local_hospital_outlined,
                  label(item.clinic),
                  strong: true,
                ),
                if (item.doctor['nama'] != null)
                  _fact(Icons.person_outline, '${item.doctor['nama']}'),
                if (room.isNotEmpty)
                  _fact(
                    Icons.meeting_room_outlined,
                    [room['kode'], room['nama']]
                        .whereType<String>()
                        .where((s) => s.isNotEmpty)
                        .join(' · '),
                  ),
                const SizedBox(height: 2),
                _fact(Icons.calendar_today_outlined, patientDate(item.day)),
                if (item.slot['mulaiPada'] != null)
                  _fact(
                    Icons.schedule_outlined,
                    '${patientTime(item.slot, config)} · ${config.serviceTimeZone}',
                  ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SizedBox(
              height: 1,
              child: CustomPaint(painter: _TicketRule()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: item.terminal
                ? OutlinedButton.icon(
                    onPressed: onOpen,
                    icon: const Icon(Icons.description_outlined, size: 18),
                    label: const Text('Lihat Tiket / QR'),
                  )
                : FilledButton.icon(
                    onPressed: onOpen,
                    icon: const Icon(Icons.qr_code_rounded, size: 18),
                    label: const Text('Lihat Tiket / QR'),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _fact(IconData icon, String value, {bool strong = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: PatientDesign.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              height: 1.3,
              color: strong ? PatientDesign.ink : PatientDesign.muted,
              fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ],
    ),
  );
}

class _TicketRule extends CustomPainter {
  const _TicketRule();
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = PatientDesign.border
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 8) {
      canvas.drawLine(
        Offset(x, 0),
        Offset((x + 4).clamp(0, size.width), 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TicketRule oldDelegate) => false;
}
