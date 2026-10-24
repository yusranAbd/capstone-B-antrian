import 'package:flutter/material.dart';

import 'config.dart';
import 'mobile_ui.dart';
import 'patient_ui.dart';
import 'doctor_professional.dart';

abstract final class PatientHomeStyle {
  static const background = Color(0xfff7fafc);
  static const welcomeTint = Color(0xffeaf8fc);
  static const shadow = Color(0x06007f80);
  static const heroStart = Color(0xff006c75);
  static const heroEnd = Color(0xff008184);
  static const clinicSurface = Color(0xffe7f8f7);
  static const appointmentInk = Color(0xff1766c5);
  static const appointmentSurface = Color(0xffeaf3ff);
  static const ticketInk = Color(0xffb94a2c);
  static const ticketSurface = Color(0xfffff1e9);
  static const historyInk = Color(0xff64509c);
  static const historySurface = Color(0xfff1edfc);
  static const visitSurface = Color(0xffeaf8f7);
}

// Home-only visual layer. Existing booking, session and realtime owners stay in
// PatientPage. Hallmark self-review: P5 H5 E4 S5 R5 V4 (visit-first healthcare).
class PatientHomeBrand extends StatelessWidget {
  const PatientHomeBrand({super.key});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: QueueBStyle.teal,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(
          Icons.local_hospital_rounded,
          color: Colors.white,
          size: 26,
        ),
      ),
      const SizedBox(width: 8),
      const Flexible(
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(text: 'QueueB\n'),
              TextSpan(
                text: 'Hospital',
                style: TextStyle(color: QueueBStyle.darkTeal),
              ),
            ],
          ),
          style: TextStyle(
            fontSize: 17,
            height: 1.05,
            fontWeight: FontWeight.w800,
            color: QueueBStyle.navy,
          ),
        ),
      ),
    ],
  );
}

class PatientHomeSurface extends StatelessWidget {
  const PatientHomeSurface({
    super.key,
    required this.child,
    this.color = Colors.white,
  });
  final Widget child;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: QueueBStyle.border.withValues(alpha: .6)),
      boxShadow: const [
        BoxShadow(
          color: PatientHomeStyle.shadow,
          blurRadius: 16,
          offset: Offset(0, 4),
        ),
      ],
    ),
    padding: const EdgeInsets.all(16),
    child: child,
  );
}

class PatientHomeWelcome extends StatelessWidget {
  const PatientHomeWelcome({
    super.key,
    required this.name,
    required this.onSearch,
    this.avatar,
  });
  final String name;
  final ValueChanged<String> onSearch;
  final Widget? avatar;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (avatar != null) ...[
        Row(
          children: [
            avatar!,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Selamat datang,',
                    style: TextStyle(color: QueueBStyle.muted, fontSize: 13),
                  ),
                  Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: QueueBStyle.navy,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
      ],
      const Text(
        'Bagaimana kabar Anda hari ini?',
        style: TextStyle(
          fontSize: 28,
          height: 1.2,
          fontWeight: FontWeight.w800,
          color: QueueBStyle.navy,
        ),
      ),
      const SizedBox(height: 16),
      TextField(
        onChanged: onSearch,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Cari dokter, poliklinik, atau layanan...',
          hintStyle: const TextStyle(fontSize: 12, color: QueueBStyle.muted),
          prefixIcon: const Icon(Icons.search_rounded, color: QueueBStyle.navy),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 17,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: QueueBStyle.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: QueueBStyle.border),
          ),
        ),
      ),
    ],
  );
}

class PatientHomeBanner extends StatelessWidget {
  const PatientHomeBanner({super.key, required this.onRegister});
  final VoidCallback? onRegister;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(22),
      gradient: const LinearGradient(
        colors: [PatientHomeStyle.heroStart, PatientHomeStyle.heroEnd],
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(18, 20, 8, 18),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Daftar antrean lebih cepat dari mana saja',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 9),
                const Text(
                  'Pilih poliklinik dan dokter, dapatkan nomor antrean secara online.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: onRegister,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: QueueBStyle.darkTeal,
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          'Ambil Antrean',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      SizedBox(width: 6),
                      Icon(Icons.arrow_forward_rounded, size: 17),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            flex: 2,
            child: ExcludeSemantics(
              child: Image.asset(
                'assets/illustrations/patient_ticket.png',
                fit: BoxFit.contain,
                errorBuilder: (_, error, stack) => const Icon(
                  Icons.confirmation_number_rounded,
                  size: 64,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class PatientHomeShortcuts extends StatelessWidget {
  const PatientHomeShortcuts({
    super.key,
    required this.enabled,
    required this.onClinics,
    required this.onAppointment,
    required this.onTickets,
    required this.onHistory,
  });
  final bool enabled;
  final VoidCallback onClinics, onAppointment, onTickets, onHistory;
  @override
  Widget build(BuildContext context) => PatientHomeSurface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Akses cepat',
          style: TextStyle(fontSize: 12, color: QueueBStyle.muted),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, box) {
            final columns = box.maxWidth < 270 ? 2 : 4;
            return Wrap(
              spacing: 8,
              runSpacing: 12,
              children: [
                for (final item
                    in <(String, IconData, Color, Color, VoidCallback)>[
                      (
                        'Poliklinik dan Dokter',
                        Icons.medical_services_outlined,
                        QueueBStyle.darkTeal,
                        PatientHomeStyle.clinicSurface,
                        onClinics,
                      ),
                      (
                        'Janji Temu Dokter',
                        Icons.calendar_month_outlined,
                        PatientHomeStyle.appointmentInk,
                        PatientHomeStyle.appointmentSurface,
                        onAppointment,
                      ),
                      (
                        'Antrean Saya',
                        Icons.confirmation_number_outlined,
                        PatientHomeStyle.ticketInk,
                        PatientHomeStyle.ticketSurface,
                        onTickets,
                      ),
                      (
                        'Riwayat Kunjungan',
                        Icons.history_rounded,
                        PatientHomeStyle.historyInk,
                        PatientHomeStyle.historySurface,
                        onHistory,
                      ),
                    ])
                  SizedBox(
                    width: (box.maxWidth - (columns - 1) * 8) / columns,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: enabled ? item.$5 : null,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                            children: [
                              Container(
                                width: 52,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: item.$4,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Icon(item.$2, color: item.$3, size: 27),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                item.$1,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 11,
                                  height: 1.35,
                                  fontWeight: FontWeight.w600,
                                  color: QueueBStyle.navy,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    ),
  );
}

class PatientHomeSectionTitle extends StatelessWidget {
  const PatientHomeSectionTitle(
    this.title, {
    super.key,
    this.action,
    this.onPressed,
  });
  final String title;
  final String? action;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: QueueBStyle.navy,
          ),
        ),
      ),
      if (action != null)
        TextButton(
          onPressed: onPressed,
          child: Text(action!, style: const TextStyle(fontSize: 12)),
        ),
    ],
  );
}

class PatientHomeVisit extends StatelessWidget {
  const PatientHomeVisit({
    super.key,
    required this.ticket,
    required this.doctor,
    required this.onTicket,
    required this.config,
    this.appointment,
  });
  final Json ticket, doctor;
  final Json? appointment;
  final AppConfig config;
  final VoidCallback? onTicket;
  Json get room {
    final booked = object(
      object(object(appointment?['slotPraktik'])['jadwalPraktik'])['loket'],
    );
    return booked.isNotEmpty ? booked : object(ticket['loket']);
  }

  @override
  Widget build(BuildContext context) => PatientHomeSurface(
    color: PatientHomeStyle.appointmentSurface,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (doctor['id'] != null) ...[
              ProfessionalDoctorAvatar(
                config: config,
                photo: doctor['fotoProfil'],
                radius: 27,
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    doctor['nama'] != null
                        ? label(doctor)
                        : label(object(ticket['layanan'])),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: QueueBStyle.navy,
                    ),
                  ),
                  if (doctor['spesialisasi'] != null)
                    Text(
                      '${doctor['spesialisasi']}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: QueueBStyle.muted,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            StatusBadge(ticket['status']),
            Text(
              label(object(ticket['layanan'])),
              style: const TextStyle(fontSize: 12, color: QueueBStyle.muted),
            ),
          ],
        ),
        if (room.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              [
                room['kode'],
                room['nama'],
              ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
              style: const TextStyle(fontSize: 12, color: QueueBStyle.muted),
            ),
          ),
        const SizedBox(height: 14),
        const Text(
          'Nomor antrean',
          style: TextStyle(fontSize: 11, color: QueueBStyle.muted),
        ),
        Text(
          '${ticket['nomorAntrean'] ?? 'Nomor belum tersedia'}',
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: QueueBStyle.navy,
          ),
        ),
        Text(
          patientDate(
            '${ticket['tanggalPelayanan'] ?? ticket['tanggalAntrean']}',
          ),
          style: const TextStyle(fontSize: 12, color: QueueBStyle.muted),
        ),
        if (appointment != null)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              '${patientTime(object(appointment!['slotPraktik']), config)} · ${config.serviceTimeZone}',
              style: const TextStyle(fontSize: 12, color: QueueBStyle.darkTeal),
            ),
          ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onTicket,
                child: const Text('Lihat Detail'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: onTicket,
                icon: const Icon(Icons.qr_code_rounded, size: 18),
                label: const Text('QR Code'),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class PatientHomeEmpty extends StatelessWidget {
  const PatientHomeEmpty({
    super.key,
    required this.text,
    this.action,
    this.onPressed,
  });
  final String text;
  final String? action;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => PatientHomeSurface(
    child: Row(
      children: [
        const Icon(
          Icons.event_note_outlined,
          color: QueueBStyle.teal,
          size: 27,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: QueueBStyle.muted,
                ),
              ),
              if (action != null)
                TextButton(
                  onPressed: onPressed,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    alignment: Alignment.centerLeft,
                  ),
                  child: Text(action!),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class PatientHomeLoading extends StatelessWidget {
  const PatientHomeLoading({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Memuat ringkasan pelayanan',
    child: ExcludeSemantics(
      child: PatientHomeSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 12,
              decoration: BoxDecoration(
                color: QueueBStyle.border,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(height: 10),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: .6,
              child: Container(
                height: 12,
                decoration: BoxDecoration(
                  color: QueueBStyle.border,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class HomeDoctorPreview {
  const HomeDoctorPreview(this.doctor, this.clinic, this.session);
  final Json doctor, clinic;
  final Json? session;
}

// Derive display-only data without mutating server lists or booking selections.
List<HomeDoctorPreview> homeDoctorPreviews(
  List<Json> doctors,
  List<Json> clinics,
  List<Json> sessions,
  AppConfig config,
  String search, {
  String? clinicId,
}) {
  final result = <HomeDoctorPreview>[];
  for (final doctor in doctors.where((d) => d['aktif'] != false)) {
    final links = rows(doctor['dokterLayanan']).where(
      (l) =>
          l['aktif'] == true &&
          (clinicId == null || l['layananId'] == clinicId) &&
          clinics.any((c) => c['id'] == l['layananId'] && c['aktif'] != false),
    );
    if (links.isEmpty) continue;
    final upcoming =
        sessions.where((s) {
            final link = object(s['dokterLayanan']);
            return s['aktif'] != false &&
                object(s['loket'])['aktif'] != false &&
                link['aktif'] != false &&
                (link['dokterId'] ?? object(link['dokter'])['id']) ==
                    doctor['id'] &&
                links.any(
                  (l) =>
                      (l['id'] != null && l['id'] == s['dokterLayananId']) ||
                      l['layananId'] == link['layananId'] ||
                      l['layananId'] == object(link['layanan'])['id'],
                ) &&
                dateOnly(s['tanggal']).compareTo(config.today) >= 0 &&
                (DateTime.tryParse('${s['selesaiPada']}')
                        ?.isAfter(config.now) ??
                    false);
          }).toList()
          ..sort((a, b) => '${a['mulaiPada']}'.compareTo('${b['mulaiPada']}'));
    final session = upcoming.firstOrNull;
    final sl = object(session?['dokterLayanan']);
    final previewClinicId =
        sl['layananId'] ??
        object(sl['layanan'])['id'] ??
        links.first['layananId'];
    final clinic = clinics.where((c) => c['id'] == previewClinicId).firstOrNull;
    if (clinic == null) continue;
    if (!('${label(doctor)} ${doctor['spesialisasi'] ?? ''} ${label(clinic)}')
        .toLowerCase()
        .contains(search)) {
      continue;
    }
    result.add(HomeDoctorPreview(doctor, clinic, session));
  }
  result.sort((a, b) {
    if (a.session == null) {
      return b.session == null ? label(a.doctor).compareTo(label(b.doctor)) : 1;
    }
    if (b.session == null) return -1;
    return '${a.session!['mulaiPada']}'.compareTo('${b.session!['mulaiPada']}');
  });
  return result;
}

Json? nearestHomeTicket(
  List<Json> tickets,
  List<Json> appointments,
  String today,
) {
  final byId = <Object?, Json>{
    for (final a in appointments)
      if (object(a['tiket'])['id'] != null)
        object(a['tiket'])['id']: {
          ...object(a['tiket']),
          if (a['nomorAntrean'] != null) 'nomorAntrean': a['nomorAntrean'],
          if (a['tanggalPelayanan'] != null)
            'tanggalPelayanan': a['tanggalPelayanan'],
        },
    for (final t in tickets)
      if (t['id'] != null) t['id']: t,
  };
  final candidates = byId.values
      .where(
        (t) =>
            !['SELESAI', 'DIBATALKAN'].contains(t['status']) &&
            dateOnly(t['tanggalPelayanan'] ?? t['tanggalAntrean'])
                    .compareTo(today) >=
                0,
      )
      .toList();
  candidates.sort((a, b) {
    final day = dateOnly(a['tanggalPelayanan'] ?? a['tanggalAntrean'])
        .compareTo(dateOnly(b['tanggalPelayanan'] ?? b['tanggalAntrean']));
    if (day != 0) return day;
    // Display priority only; this never changes the server queue order.
    int status(Json t) => switch (t['status']) {
      'DILAYANI' => 0,
      'DIPANGGIL' => 1,
      'MENUNGGU' => 2,
      'CHECK_IN' => 3,
      'DILEWATI' => 4,
      _ => 5,
    };
    final state = status(a).compareTo(status(b));
    if (state != 0) return state;
    String start(Json ticket) =>
        '${object(appointments.where((a) => object(a['tiket'])['id'] == ticket['id']).firstOrNull?['slotPraktik'])['mulaiPada'] ?? ''}';
    final slot = start(a).compareTo(start(b));
    return slot != 0 ? slot : '${a['id']}'.compareTo('${b['id']}');
  });
  return candidates.firstOrNull;
}

class PatientHomeDoctor extends StatelessWidget {
  const PatientHomeDoctor({
    super.key,
    required this.preview,
    required this.config,
    required this.onTap,
    this.scheduleUnavailable = false,
  });
  final HomeDoctorPreview preview;
  final AppConfig config;
  final VoidCallback? onTap;
  final bool scheduleUnavailable;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: QueueBStyle.border),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            ProfessionalDoctorAvatar(
              config: config,
              photo: preview.doctor['fotoProfil'],
              radius: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label(preview.doctor),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: QueueBStyle.navy,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${preview.doctor['spesialisasi'] ?? 'Spesialisasi belum dicantumkan'} · ${label(preview.clinic)}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: QueueBStyle.muted,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    scheduleUnavailable
                        ? 'Jadwal belum dapat dimuat.'
                        : preview.session == null
                        ? 'Jadwal belum tersedia.'
                        : '${patientDate('${preview.session!['tanggal']}')}\n${patientTime(preview.session!, config)} · ${config.serviceTimeZone}',
                    style: const TextStyle(
                      fontSize: 11,
                      height: 1.4,
                      color: QueueBStyle.darkTeal,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Detail Dokter',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: QueueBStyle.darkTeal,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right_rounded,
              color: QueueBStyle.darkTeal,
              size: 20,
            ),
          ],
        ),
      ),
    ),
  );
}

class PatientHomeTip extends StatelessWidget {
  const PatientHomeTip({super.key});
  @override
  Widget build(BuildContext context) => PatientHomeSurface(
    color: QueueBStyle.mint,
    child: const Row(
      children: [
        Icon(
          Icons.lightbulb_outline_rounded,
          color: QueueBStyle.darkTeal,
          size: 30,
        ),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tips Cepat',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: QueueBStyle.navy,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Datang sebelum jadwal pelayanan dan siapkan tiket QR Anda.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: QueueBStyle.muted,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
