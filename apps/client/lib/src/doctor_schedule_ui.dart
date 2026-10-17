import 'package:flutter/material.dart';

import 'config.dart';
import 'mobile_ui.dart';

// QueueB existing tokens and navigation; reference: doctor profile + calendar.
// Hallmark · pre-emit critique: P4 H4 E4 S5 R5 V4.
class DoctorProfileCard extends StatelessWidget {
  const DoctorProfileCard({
    super.key,
    required this.doctor,
    required this.clinics,
    this.availability,
    this.onSchedule,
    this.detail = false,
  });
  final Json doctor;
  final String clinics;
  final String? availability;
  final VoidCallback? onSchedule;
  final bool detail;

  @override
  Widget build(BuildContext context) => AppCard(
    color: detail ? QueueBStyle.mint : null,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: detail ? 30 : 24,
              backgroundColor: detail ? Colors.white : QueueBStyle.mint,
              foregroundColor: QueueBStyle.darkTeal,
              child: const Icon(Icons.person_outline_rounded, size: 32),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label(doctor),
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${doctor['spesialisasi'] ?? 'Spesialisasi belum dicantumkan'}',
                    style: const TextStyle(color: QueueBStyle.muted),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    clinics,
                    style: const TextStyle(color: QueueBStyle.darkTeal),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (availability != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(
                Icons.event_available_outlined,
                size: 18,
                color: QueueBStyle.muted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  availability!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: QueueBStyle.muted,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (!detail) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onSchedule,
            icon: const Icon(Icons.calendar_month_outlined, size: 18),
            label: const Text('Lihat Jadwal'),
          ),
        ],
      ],
    ),
  );
}

/// Values are calendar DATE strings from the API, never derived practice days.
class PracticeDateStrip extends StatefulWidget {
  const PracticeDateStrip({
    super.key,
    required this.dates,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });
  final List<String> dates;
  final String value;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  State<PracticeDateStrip> createState() => _PracticeDateStripState();
}

class _PracticeDateStripState extends State<PracticeDateStrip> {
  late final ScrollController controller = ScrollController();

  @override
  void initState() {
    super.initState();
    revealDate();
  }

  @override
  void didUpdateWidget(PracticeDateStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value || oldWidget.dates != widget.dates) {
      revealDate();
    }
  }

  void revealDate() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted || !controller.hasClients) return;
    final index = widget.dates.indexOf(widget.value);
    controller.jumpTo(
      (index * 80.0).clamp(0.0, controller.position.maxScrollExtent),
    );
  });

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 104 * MediaQuery.textScalerOf(context).scale(1),
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: widget.dates.length,
      controller: controller,
      separatorBuilder: (_, index) => const SizedBox(width: 8),
      itemBuilder: (context, index) {
        final text = widget.dates[index], day = DateTime.parse(text);
        final selected = text == widget.value;
        return Semantics(
          selected: selected,
          child: SizedBox(
            width: 72,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                backgroundColor: selected ? QueueBStyle.darkTeal : Colors.white,
                foregroundColor: selected ? Colors.white : QueueBStyle.navy,
                side: BorderSide(
                  color: selected ? QueueBStyle.teal : QueueBStyle.border,
                ),
              ),
              onPressed: widget.enabled ? () => widget.onChanged(text) : null,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    const [
                      'Sen',
                      'Sel',
                      'Rab',
                      'Kam',
                      'Jum',
                      'Sab',
                      'Min',
                    ][day.weekday - 1],
                  ),
                  Text(
                    '${day.day}/${day.month}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text('${day.year}', style: const TextStyle(fontSize: 10)),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

String consultationSlotStatus(Json slot) {
  if (slot['aktif'] == false) return 'Tidak aktif';
  if (slot['sisaKapasitas'] is num && slot['sisaKapasitas'] <= 0) {
    return 'Penuh';
  }
  return slot['tersedia'] == true ? 'Tersedia' : 'Tidak tersedia';
}

class ConsultationSlotGrid extends StatelessWidget {
  const ConsultationSlotGrid({
    super.key,
    required this.slots,
    required this.config,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });
  final List<Json> slots;
  final AppConfig config;
  final String? value;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final columns = box.maxWidth >= 480 ? 3 : 2;
      final width = (box.maxWidth - (columns - 1) * 8) / columns;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final slot in slots)
            SizedBox(
              width: width,
              child: Semantics(
                selected: value == slot['id'],
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 12,
                    ),
                    backgroundColor: value == slot['id']
                        ? QueueBStyle.mint
                        : null,
                    side: BorderSide(
                      color: value == slot['id']
                          ? QueueBStyle.teal
                          : QueueBStyle.border,
                    ),
                  ),
                  onPressed:
                      enabled &&
                          slot['tersedia'] == true &&
                          slot['aktif'] != false
                      ? () => onChanged('${slot['id']}')
                      : null,
                  child: Column(
                    children: [
                      Text(
                        '${config.localInput(slot['mulaiPada']).split('T').last} – ${config.localInput(slot['selesaiPada']).split('T').last}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        consultationSlotStatus(slot),
                        style: const TextStyle(fontSize: 12),
                      ),
                      if (slot['sisaKapasitas'] != null)
                        Text(
                          'Sisa slot ${slot['sisaKapasitas']}',
                          style: const TextStyle(fontSize: 11),
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}
