import 'package:flutter/material.dart';

import 'config.dart';
import 'mobile_ui.dart';
import 'patient_design.dart';
import 'patient_ui.dart';
import 'patient_reservations.dart';

/// A read-only date lens over the existing appointment response, not a scheduler.
class PatientAgenda extends StatefulWidget {
  const PatientAgenda({
    super.key,
    required this.appointments,
    required this.config,
    required this.loading,
    required this.busy,
    required this.onRefresh,
    required this.onTicket,
    this.error,
    this.message,
  });
  final List<Json> appointments;
  final AppConfig config;
  final bool loading, busy;
  final String? error, message;
  final VoidCallback onRefresh;
  final ValueChanged<Json> onTicket;
  @override
  State<PatientAgenda> createState() => _PatientAgendaState();
}

class _PatientAgendaState extends State<PatientAgenda> {
  String? day;
  String dayOf(Json a) => dateOnly(
    object(a['slotPraktik'])['tanggalPelayanan'] ??
        object(object(a['slotPraktik'])['jadwalPraktik'])['tanggal'] ??
        object(a['tiket'])['tanggalPelayanan'] ??
        object(a['tiket'])['tanggalAntrean'],
  );
  @override
  Widget build(BuildContext context) {
    final days =
        widget.appointments
            .map(dayOf)
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final selected = days.contains(day) ? day : null;
    final visible =
        widget.appointments
            .where((a) => selected == null || dayOf(a) == selected)
            .toList()
          ..sort(
            (a, b) => '${object(a['slotPraktik'])['mulaiPada']}'.compareTo(
              '${object(b['slotPraktik'])['mulaiPada']}',
            ),
          );
    return ListView.builder(
      key: const PageStorageKey('patient-agenda'),
      padding: const EdgeInsets.all(16),
      itemCount: 1 + (visible.isEmpty ? 1 : visible.length),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PatientPageIntro(
                title: 'Janji temu saya',
                caption: 'Jadwal kunjungan, dalam satu pandangan.',
                action: IconButton(
                  tooltip: 'Muat ulang janji temu',
                  onPressed: widget.busy || widget.loading
                      ? null
                      : widget.onRefresh,
                  icon: const Icon(Icons.refresh),
                ),
              ),
              if (widget.error != null)
                MobileNotice(widget.error!, error: true),
              if (widget.message != null) MobileNotice(widget.message!),
              if (widget.loading) const LinearProgressIndicator(),
              if (days.isNotEmpty)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: const Text('Semua tanggal'),
                        selected: selected == null,
                        onSelected: widget.busy
                            ? null
                            : (_) => setState(() => day = null),
                      ),
                      for (final d in days)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: ChoiceChip(
                            label: Tooltip(
                              message: patientDate(d),
                              child: Semantics(
                                label: patientDate(d),
                                child: Text(patientCompactDate(d)),
                              ),
                            ),
                            selected: selected == d,
                            onSelected: widget.busy
                                ? null
                                : (_) => setState(() => day = d),
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
            ],
          );
        }
        if (visible.isEmpty) {
          return const EmptyState(
            text: 'Belum ada janji temu.',
            icon: Icons.event_available_outlined,
          );
        }
        final a = visible[index - 1],
            slot = object(a['slotPraktik']),
            session = object(slot['jadwalPraktik']),
            ticket = object(a['tiket']);
        final link = object(session['dokterLayanan']),
            doctor = object(link['dokter']),
            clinic = object(link['layanan']),
            room = object(session['loket']);
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: PatientDesign.paper,
            border: Border.all(color: PatientDesign.border),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      patientDate(dayOf(a)),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: ReservationStatus('${ticket['status'] ?? '—'}'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                slot['mulaiPada'] == null
                    ? 'Waktu belum tersedia'
                    : patientTime(slot, widget.config),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.6,
                  color: PatientDesign.primary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.config.serviceTimeZone,
                style: const TextStyle(
                  fontSize: 11,
                  color: PatientDesign.muted,
                ),
              ),
              const Divider(),
              if (doctor.isNotEmpty)
                Text(
                  label(doctor),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              if (clinic.isNotEmpty)
                Text(
                  label(clinic),
                  style: const TextStyle(
                    fontSize: 13,
                    color: PatientDesign.muted,
                  ),
                ),
              if (room.isNotEmpty)
                Text(
                  'Ruang: ${label(room)}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: PatientDesign.muted,
                  ),
                ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: widget.busy || ticket['id'] == null
                    ? null
                    : () => widget.onTicket(ticket),
                icon: const Icon(Icons.confirmation_number_outlined, size: 18),
                label: const Text('Lihat tiket'),
              ),
            ],
          ),
        );
      },
    );
  }
}
